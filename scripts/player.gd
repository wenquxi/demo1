extends CharacterBody3D
## 第三人称角色控制器
##
## 设计要点：
## - 移动方向相对于摄像机，摄像机用 SpringArm3D 做碰撞回缩（贴墙时镜头不会穿模）
## - 跳跃手感参数用「跳跃高度 + 到达顶点耗时」表达，比直接调重力直观得多，
##   并且上升/下降用不同重力（下降更快），这是平台游戏手感的关键
## - 加入 coyote time（离开平台后的宽限）与 jump buffer（落地前的预输入缓存）
## - 身体朝向只做水平旋转，与摄像机解耦：镜头转，人不跟着转
## - 自动上台阶：见 _try_step_up()，按 T 可实时开关以对比手感差异

@export_group("移动")
## 常规移动速度（米/秒）
@export var walk_speed := 5.0
## 按住 Shift 的冲刺速度
@export var sprint_speed := 8.5
## 地面加速度，越大越跟手
@export var acceleration := 45.0
## 空中加速度，明显低于地面以保留惯性与跳跃弧线
@export var air_acceleration := 12.0
## 松开按键后的地面减速
@export var friction := 40.0
## 身体转向速度（越大转得越快）
@export var turn_speed := 14.0

@export_group("跳跃")
## 跳跃最高能到多少米
@export var jump_height := 1.5
## 从起跳到最高点的时间，越小越"脆"
@export var jump_time_to_peak := 0.38
## 从最高点落回地面的时间，比上升短则手感更利落
@export var jump_time_to_descent := 0.30
## 离开平台后仍允许起跳的宽限时间
@export var coyote_time := 0.12
## 落地前提前按跳的缓存时间
@export var jump_buffer_time := 0.14

@export_group("上台阶")
## 是否启用自动上台阶（游戏中按 T 切换）
@export var step_up_enabled := true
## 单次能迈上去的最大高度。设成 0 等于关闭；设得比 0.5 大就会显得像在爬墙
@export var max_step_height := 0.45
## 判定「被挡住」的阈值：实际位移低于期望位移的这个比例时，才尝试上台阶。
## 设得太高会把正常减速也误判成撞墙，设得太低则在斜擦墙面时不触发
@export_range(0.1, 0.95) var step_blocked_ratio := 0.7

@export_group("摄像机")
## 鼠标灵敏度
@export var mouse_sensitivity := 0.0025
## 俯仰角下限（负值 = 从上方俯视）
@export var pitch_min := -1.20
## 俯仰角上限
@export var pitch_max := 0.50
## 启动时自动锁定鼠标
@export var capture_mouse_on_start := true

# 由跳跃参数反推出来的物理量
var _jump_velocity := 0.0
var _rise_gravity := 0.0
var _fall_gravity := 0.0

var _yaw := 0.0
var _pitch := -0.22
var _coyote_left := 0.0
var _buffer_left := 0.0

@onready var visual: Node3D = $Visual
@onready var cam_rig: SpringArm3D = $CamRig
@onready var _body_shape: CollisionShape3D = $CollisionShape3D

## 碰撞体半径，在 _ready() 里从实际形状读出来。
## 上台阶需要它：被竖直墙面挡住时，墙面距角色原点约为一个半径，
## 硬编码数字会在换角色尺寸时静默失效。
var _radius := 0.4

## 上台阶探针找到的落点，由 _probe_step_landing() 写入
var _probe_landing := Transform3D()


func _ready() -> void:
	add_to_group("player")

	# 由「高度 h、到顶耗时 t」反推：重力 g = 2h / t²，初速度 v = g * t
	_rise_gravity = 2.0 * jump_height / pow(jump_time_to_peak, 2.0)
	_fall_gravity = 2.0 * jump_height / pow(jump_time_to_descent, 2.0)
	_jump_velocity = _rise_gravity * jump_time_to_peak

	# 让弹簧臂忽略角色自身的碰撞体，否则镜头会把自己顶飞
	cam_rig.add_excluded_object(get_rid())
	_read_body_radius()
	_apply_camera()

	if capture_mouse_on_start:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_step_up"):
		step_up_enabled = not step_up_enabled
	elif event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			var motion: InputEventMouseMotion = event
			_yaw -= motion.relative.x * mouse_sensitivity
			_pitch = clampf(_pitch - motion.relative.y * mouse_sensitivity, pitch_min, pitch_max)
			_apply_camera()
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	_update_timers(delta)

	var speed := sprint_speed if Input.is_action_pressed("sprint") else walk_speed
	var wish_dir := _wish_direction()

	_apply_horizontal(delta, wish_dir, speed)
	_apply_vertical(delta)
	_apply_facing(delta, wish_dir)

	# 记录滑动前的状态，move_and_slide 会改写 velocity 和 position
	var desired_velocity := velocity
	var before := global_position
	move_and_slide()
	_try_step_up(delta, desired_velocity, before)


## 把 WASD 输入按摄像机朝向映射到世界坐标下的期望移动方向
func _wish_direction() -> Vector3:
	var input_vec := Input.get_vector("move_left", "move_right", "move_backward", "move_forward")
	if input_vec == Vector2.ZERO:
		return Vector3.ZERO

	# 摄像机朝向压平到水平面，避免抬镜头时角色往上飘
	var cam_forward := -cam_rig.global_transform.basis.z
	var forward := Vector3(cam_forward.x, 0.0, cam_forward.z).normalized()
	var right := Vector3(-forward.z, 0.0, forward.x)

	return (right * input_vec.x + forward * input_vec.y).normalized()


func _apply_horizontal(delta: float, wish_dir: Vector3, speed: float) -> void:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if wish_dir == Vector3.ZERO:
		if is_on_floor():
			horizontal = horizontal.move_toward(Vector3.ZERO, friction * delta)
	else:
		var accel := acceleration if is_on_floor() else air_acceleration
		horizontal = horizontal.move_toward(wish_dir * speed, accel * delta)

	velocity.x = horizontal.x
	velocity.z = horizontal.z


func _apply_vertical(delta: float) -> void:
	if is_on_floor():
		# 略微向下压，避免在斜坡上因贴合抖动而反复起跳
		if velocity.y < 0.0:
			velocity.y = -0.1
	else:
		velocity.y -= (_rise_gravity if velocity.y > 0.0 else _fall_gravity) * delta

	if _coyote_left > 0.0 and _buffer_left > 0.0:
		velocity.y = _jump_velocity
		_coyote_left = 0.0
		_buffer_left = 0.0
	elif velocity.y > 0.0 and not Input.is_action_pressed("jump"):
		# 提前松手就削减上升速度 —— 可变跳跃高度
		velocity.y = lerpf(velocity.y, 0.0, minf(1.0, 12.0 * delta))


## 身体只做水平旋转，平滑转向移动方向（视觉体朝向 +Z）
func _apply_facing(delta: float, wish_dir: Vector3) -> void:
	if wish_dir == Vector3.ZERO:
		return
	var target := atan2(wish_dir.x, wish_dir.z)
	visual.rotation.y = lerp_angle(visual.rotation.y, target, 1.0 - exp(-turn_speed * delta))


func _update_timers(delta: float) -> void:
	if is_on_floor():
		_coyote_left = coyote_time
	else:
		_coyote_left = maxf(0.0, _coyote_left - delta)

	if Input.is_action_just_pressed("jump"):
		_buffer_left = jump_buffer_time
	else:
		_buffer_left = maxf(0.0, _buffer_left - delta)


func _apply_camera() -> void:
	# Node3D.rotation 默认欧拉序为 YXZ，先偏航再俯仰，正是第一/三人称所需
	cam_rig.rotation = Vector3(_pitch, _yaw, 0.0)


## 自动上台阶。
##
## 流程是「抬高 → 前推 → 落下」，全部成功才提交位移，否则回滚到原位。
## 四道关卡：
##   1. 只在水平位移确实被挡住的帧才触发（否则平地上每帧都白算一次）
##   2. 头顶要有空间抬起来
##   3. 抬高后必须真的能前进一段 —— 前进不了说明是高于 max_step_height 的墙，
##      这一步同时替代了"墙还是台阶"的判断
##   4. 落下后必须站得住：落点法线在 floor_max_angle 之内，且最终高度高于起点
##
## 关键细节：前推距离不能用「速度 × delta」。被竖直墙面挡住时，墙面距角色原点
## 约为一个碰撞半径，只推进一点点的话原点仍落在台阶外侧，下落时直接掉回地面，
## 还会横向嵌进台阶被物理引擎推回来，形成永远上不去的死循环。
## 所以前推距离至少取「半径 + 余量」，让原点落到台面正上方；同时用
## move_and_collide 吃掉多余距离，不会越过下一个障碍。
func _try_step_up(delta: float, desired_velocity: Vector3, before: Vector3) -> void:
	if not step_up_enabled or not is_on_floor():
		return

	var intended := Vector3(desired_velocity.x, 0.0, desired_velocity.z) * delta
	if intended.length_squared() < 0.000001:
		return

	# 关卡 1：被挡住了吗？
	var moved := Vector3(global_position.x - before.x, 0.0, global_position.z - before.z)
	if moved.length() > intended.length() * step_blocked_ratio:
		return

	var lift := Vector3.UP * max_step_height
	# 关卡 2：头顶空间
	if test_move(global_transform, lift):
		return

	var lifted := global_transform.translated(lift)
	if not _probe_step_landing(lifted, intended.normalized()):
		return

	# 探针已确认可行，一次性提交，不再试探性移动
	global_position = _probe_landing.origin


## 在抬高后的高度上扫描前推距离，找第一个「能站住、且确实比现在高」的落点。
##
## 为什么不能直接用固定距离：
## 被竖直墙面挡住时，角色原点距墙面约为一个碰撞半径。推得太近，原点落在台阶外侧，
## 下落时直接掉回地面（原地死循环）；推得太远则会越过本级台阶，让胶囊卡在上一级
## 台阶的棱边上 —— 棱边接触法线可以陡到 60° 以上，远超 floor_max_angle，站不住。
## 台阶越窄可行区间越窄（本级深度接近碰撞半径时甚至只有几厘米），所以细粒度扫描，
## 并且取最小的可行距离，让上台阶时向前冲的幅度尽量小。
func _probe_step_landing(lifted: Transform3D, dir: Vector3) -> bool:
	var probe_down := Vector3.DOWN * (max_step_height + 0.05)
	var stride := maxf(_radius * 0.1, 0.03)
	var offset := _radius * 0.9
	var limit := _radius + 0.35

	while offset <= limit:
		offset += stride
		# 抬高到这个距离时仍有阻挡，说明这一档会撞上更高的障碍
		if test_move(lifted, dir * offset):
			continue
		var candidate := lifted.translated(dir * offset)
		var hit := KinematicCollision3D.new()
		if not test_move(candidate, probe_down, hit):
			continue
		if hit.get_normal().angle_to(Vector3.UP) > floor_max_angle:
			continue
		var landing := candidate.translated(hit.get_travel())
		if landing.origin.y <= global_position.y + 0.02:
			continue
		_probe_landing = landing
		return true

	return false


func _read_body_radius() -> void:
	var shape: Shape3D = _body_shape.shape
	if shape is CapsuleShape3D:
		_radius = (shape as CapsuleShape3D).radius
	elif shape is SphereShape3D:
		_radius = (shape as SphereShape3D).radius
