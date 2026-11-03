extends Node
## 灰堤 P1 的验收出图。
##
## 用法（必须带窗口，headless 没有渲染帧）：
##   godot --path . res://tools/dike_shot.tscn
##
## 机位一律写地图坐标（X 东、Y 北、H 高），进 for 循环时统一翻成 Godot 的
## (X, H, −Y)。这样改机位时可以直接对着规划文档的表格填数，不用心算 Z 取反。
##
## 出图到 res://shots/，文件名带序号，方便按顺序看动线。


const SCENE := preload("res://scenes/gray_dike_p1.tscn")

## name / 地图坐标 pos / 看向的地图坐标 look / fov
##
## 注意：pos 和 look 的第三个分量都是**地图 Y**，不是 Godot Z。脚本里统一取负。
## 写成负值就等于「往南看」—— 这个坑已经踩过一次。
const SHOTS := [
	# ---- 动线 A：站台 → 出站 → 广场 → 大道（这是第一部分的正面视角）
	{"name": "01_platform", "pos": Vector3(6.0, 1.75, -45.0),
		"look": Vector3(0.0, 6.0, 30.0), "fov": 70.0},
	{"name": "02_exit", "pos": Vector3(0.0, 1.70, -37.0),
		"look": Vector3(0.0, 16.0, 70.0), "fov": 68.0},
	{"name": "03_plaza", "pos": Vector3(0.0, 1.70, -32.0),
		"look": Vector3(0.0, 22.0, 110.0), "fov": 62.0},
	{"name": "04_avenue_mid", "pos": Vector3(0.0, 1.70, 42.0),
		"look": Vector3(0.0, 32.0, 146.0), "fov": 58.0},
	{"name": "05_avenue_end", "pos": Vector3(0.0, 1.70, 60.0),
		"look": Vector3(0.0, 30.0, 146.0), "fov": 62.0},

	# ---- 回望：塔在背后，确认站台方向有东西可看，不是一片空地
	{"name": "06_look_back", "pos": Vector3(0.0, 1.70, 60.0),
		"look": Vector3(0.0, 8.0, -50.0), "fov": 66.0},

	# ---- 广场四周的立面：旅馆、食堂/时钟铺
	{"name": "07_inn", "pos": Vector3(12.0, 1.70, -8.0),
		"look": Vector3(-45.0, 7.0, -8.0), "fov": 62.0},
	{"name": "08_clock_shop", "pos": Vector3(24.0, 1.70, 2.0),
		"look": Vector3(38.0, 3.0, 2.0), "fov": 55.0},

	# ---- 站台本身：雨棚、轨道、天桥
	{"name": "09_platform_wide", "pos": Vector3(-43.0, 2.2, -44.5),
		"look": Vector3(50.0, 2.6, -44.0), "fov": 72.0},
	{"name": "10_tracks", "pos": Vector3(10.0, 3.5, -44.0),
		"look": Vector3(30.0, -1.0, -58.0), "fov": 60.0},

	# ---- 总览：从站台上空朝北，整条动线和塔在同一张图里
	{"name": "11_overview", "pos": Vector3(0.0, 96.0, -66.0),
		"look": Vector3(0.0, 0.0, 96.0), "fov": 74.0},
]


func _ready() -> void:
	var level := SCENE.instantiate()
	add_child(level)

	# 玩家自己有相机和鼠标捕获。截图时把它整棵子树停掉，改用自由机位 ——
	# 否则第一张图之后相机就被玩家抢走了。
	var player := level.get_node_or_null("Player")
	if player != null:
		player.process_mode = Node.PROCESS_MODE_DISABLED
		if player is Node3D:
			(player as Node3D).visible = false

	var cam := Camera3D.new()
	cam.name = "ShotCam"
	cam.near = 0.1
	cam.far = 900.0
	add_child(cam)
	cam.make_current()

	DirAccess.make_dir_recursive_absolute("res://shots")

	# CSG 的第一帧还在烘焙，等两帧再拍，否则前几张会拍到没生成完的体量。
	for i in 3:
		await get_tree().process_frame

	for shot: Dictionary in SHOTS:
		var p: Vector3 = shot["pos"]
		var t: Vector3 = shot["look"]
		cam.fov = float(shot["fov"])
		cam.global_position = Vector3(p.x, p.y, -p.z)
		cam.look_at(Vector3(t.x, t.y, -t.z), Vector3.UP)
		print("[shot] %s cam=%v rot=%v" % [shot["name"], cam.global_position,
			cam.global_rotation_degrees])
		for i in 4:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("res://shots/%s.png" % String(shot["name"]))
		print("[shot] ", shot["name"])

	print("[shot] 完成 %d 张" % SHOTS.size())
	get_tree().quit()
