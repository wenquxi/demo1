extends Node
## 灰堤 P1 的验收探针。
##
## 用的全是规划文档里的硬规则，不是「看起来对不对」：
##   §7 规则一 —— 钟塔必须从全城任何角落看得见（这里验动线上的 8 个点）
##   §7 规则二 —— 大道两侧 40 m 内不得有 6 m 以上的实体凸进路面
##   §10 P1   —— 站台 → 出站 → 广场 → 大道，一条动线走通
##
## 无头跑：godot --headless --path . tests/gray_dike_smoke.tscn


const SCENE := preload("res://scenes/gray_dike_p1.tscn")

## 塔在 (0, 146)，Godot 世界坐标里是 z = −146
const TOWER_Z := -146.0
## 塔身半径（最上一段 8×8，取 4 m；留 3 m 余量给不同高度的命中点）
const TOWER_HALF := 7.0
## 眼高。站台面 0.25，其他地方 0 —— 统一取 1.7，对 100 m 外的射线误差忽略不计
const EYE := 1.7

## 动线上的 8 个采样点（地图 Y）。从站台一路走到大道北端。
const SIGHT_Y := [
	{"y": -44.0, "label": "站台中央"},
	{"y": -37.0, "label": "出站口"},
	{"y": -30.0, "label": "广场南（S3 站位）"},
	{"y": -15.0, "label": "广场中（报时亭旁）"},
	{"y": 5.0, "label": "广场北"},
	{"y": 20.0, "label": "大道南"},
	{"y": 50.0, "label": "大道中"},
	{"y": 88.0, "label": "大道北"},
]

var _fails := 0
var _level: Node3D


func _check(name: String, cond: bool) -> void:
	print(("  PASS  " if cond else "  FAIL  ") + name)
	if not cond:
		_fails += 1


func _ready() -> void:
	_level = SCENE.instantiate()
	add_child(_level)
	# CSG 的碰撞形状是运行时生成的，要等物理帧注册完才能 raycast
	for i in 3:
		await get_tree().physics_frame

	_test_structure()
	_test_ground()
	_test_sight()
	_test_clearance()

	if _fails == 0:
		print("SMOKE OK")
	else:
		print("SMOKE FAILED: %d 处断言未通过" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)


# ---------------------------------------------------------------- 结构

func _test_structure() -> void:
	print("[结构]")
	var spire := _level.get_node_or_null("World/Tower/TowerSpire")
	_check("钟塔尖顶存在", spire != null)
	if spire != null:
		var y := (spire as Node3D).global_position.y
		_check("塔尖高度 ≥ 46 m（实际 %.1f）" % y, y >= 46.0)

	var base := _level.get_node_or_null("World/Tower/TowerBase")
	_check("塔基存在", base != null)

	var player := _level.get_node_or_null("Player")
	_check("玩家已生成", player != null)
	if player != null:
		var py := (player as Node3D).global_position.y
		# 站台面 0.25 + 出生点留的 5 cm 余量，落稳后应该在 0.25 附近
		_check("玩家站在站台面上（y = %.2f）" % py, absf(py - 0.25) < 0.20)
		# 出生点必须在站台的 X 范围内，否则第一帧会掉进轨道沟
		var px := (player as Node3D).global_position.x
		_check("出生点在站台范围内（x = %.1f）" % px, px > -45.0 and px < 45.0)

	var platform := _level.get_node_or_null("World/Ground/PlatformSlab")
	_check("站台面存在", platform != null)

	var north := _level.get_node_or_null("World/Bounds/NorthWall")
	_check("P1 北界存在", north != null)


# ---------------------------------------------------------------- 主轴可站立

func _test_ground() -> void:
	print("[主轴]")
	var space: PhysicsDirectSpaceState3D = _level.get_world_3d().direct_space_state
	for y in [-44.0, -30.0, 0.0, 30.0, 60.0, 90.0]:
		var q := PhysicsRayQueryParameters3D.create(
			Vector3(0.0, 3.0, -y), Vector3(0.0, -1.0, -y))
		var hit: Dictionary = space.intersect_ray(q)
		var ok := not hit.is_empty() and float((hit["position"] as Vector3).y) < 0.40
		_check("Y = %d 主轴上站得住" % int(y), ok)


# ---------------------------------------------------------------- 视线

## 从 (x, EYE, −y) 朝塔身中部 (0, 30, −146) 打一条射线，
## 要求命中点落在塔的截面范围内。
func _sees_tower(y: float) -> bool:
	var from := Vector3(0.0, EYE, -y)
	var to := Vector3(0.0, 30.0, TOWER_Z)
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collide_with_areas = false
	var hit: Dictionary = _level.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return false
	var p: Vector3 = hit["position"]
	var ok := absf(p.x) < TOWER_HALF and absf(p.z - TOWER_Z) < TOWER_HALF
	if not ok:
		print("        ↑ 被 %s 挡住，命中点 %v" % [hit["collider"].name, p])
	return ok


func _test_sight() -> void:
	print("[视线 —— 规划 §7 规则一]")
	for item: Dictionary in SIGHT_Y:
		_check("%s 能看见钟塔" % String(item["label"]), _sees_tower(float(item["y"])))

	# 反向对照：站在广场再往西 60 m（旅馆背后），塔应该被建筑挡住。
	# 没有这条，「全部看得见」可能只是因为射线什么都没打到。
	var blocked := true
	var from := Vector3(-60.0, EYE, 8.0)
	var to := Vector3(0.0, 30.0, TOWER_Z)
	var q := PhysicsRayQueryParameters3D.create(from, to)
	var hit: Dictionary = _level.get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		var p: Vector3 = hit["position"]
		blocked = not (absf(p.x) < TOWER_HALF and absf(p.z - TOWER_Z) < TOWER_HALF)
	_check("对照组：旅馆背后的塔被建筑挡住（说明射线确实在测遮挡）", blocked)


# ---------------------------------------------------------------- 路面净空

func _test_clearance() -> void:
	print("[净空 —— 规划 §7 规则二]")
	var space: PhysicsDirectSpaceState3D = _level.get_world_3d().direct_space_state
	# 在 6 m 高处横打 7 m（大道路面半宽）。为什么是 6 m 而不是 5 m：
	# 规划允许招牌挑出 0.9 m，但必须挂在 4.5 m 以上 —— 所以 5 m 打到招牌
	# 是合规的，不是缺陷。这条要守的是「6 m 以上不许有东西」。
	# 端点取 ±6.8 而不是 ±7：±7 正好是两侧店铺的墙面，必然命中。
	for y in [20.0, 40.0, 60.0, 80.0]:
		for sx in [-1.0, 1.0]:
			var q := PhysicsRayQueryParameters3D.create(
				Vector3(0.0, 6.0, -y), Vector3(sx * 6.8, 6.0, -y))
			var hit: Dictionary = space.intersect_ray(q)
			_check("Y = %d 路面%s侧 6 m 高净空" % [int(y), "东" if sx > 0.0 else "西"],
				hit.is_empty())
