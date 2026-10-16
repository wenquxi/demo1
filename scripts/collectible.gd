extends Area3D
## 可拾取的收集物。
##
## 自转 + 上下浮动吸引注意力；玩家碰到后播放「上浮缩小」消散动画，
## 并通知 Game 单例计数。用 Area3D 而非 StaticBody3D，因为它是触发器不是障碍物。

## 每秒旋转弧度
@export var spin_speed := 1.8
## 上下浮动幅度（米）
@export var bob_height := 0.16
## 浮动频率
@export var bob_speed := 2.2

# 采集后停掉自转浮动，否则会和消散动画争夺 position/rotation 控制权
var _taken := false
var _base_y := 0.0
var _elapsed := 0.0


func _ready() -> void:
	# 供关卡统计数量用。父节点 _ready() 在本函数之后执行，所以统计时已入组
	add_to_group("collectible")
	_base_y = position.y
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	if _taken:
		return
	rotate_y(spin_speed * delta)
	_elapsed += delta
	position.y = _base_y + sin(_elapsed * bob_speed) * bob_height


func _on_body_entered(body: Node3D) -> void:
	if _taken or not body.is_in_group("player"):
		return
	_taken = true
	# 立即关闭监听，避免消散动画期间重复触发
	set_deferred("monitoring", false)
	Game.collect()
	_play_pickup_effect()


func _play_pickup_effect() -> void:
	var tween := create_tween().set_parallel(true)
	# 缩到 0 会让变换矩阵奇异，Jolt 会持续警告，所以留一个极小值
	tween.tween_property(self, "scale", Vector3.ONE * 0.01, 0.28) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "position", position + Vector3.UP * 1.1, 0.28)
	tween.chain().tween_callback(queue_free)
