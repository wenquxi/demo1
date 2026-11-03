extends Node3D
## 灰堤 · P1 —— 第一部分（S1 末 / S2 / S3）的可玩段。
##
## 覆盖规划文档 docs/城市规划-灰堤.md §10 的 P1：灰堤站 + 站台 + 站前广场 +
## 钟塔大道前 90 m + 钟塔远景色块。
##
## 为什么几何全在代码里生成、.tscn 只放一个根节点：
## 这一版有六百多个部件，改一个尺寸（比如大道从 14 m 放宽到 16 m）要同步
## 几十个 transform。写成配方之后，尺寸是常量，体量是循环，改动只碰一行。
## 代价是编辑器里看不到东西 —— 用 tools 里的截图脚本看。
##
## 坐标：地图 X 向东、Y 向北、H 是地面高；Godot 里北 = −Z，世界坐标 = (X, H, −Y)。
## 所有常量都写地图坐标，转换统一交给 DikeBuilder.to_world()。


const B := preload("res://levels/gray_dike/dike_builder.gd")
const P := preload("res://levels/gray_dike/dike_palette.gd")
const PLAYER_SCENE := preload("res://scenes/player.tscn")

# ---------------------------------------------------------------- 边界
# 规划 §10 写的 P1 是「约 140 × 110」，110 是按「站前广场到大道中段」估的。
# 实际要走到能看见塔压下来（仰角 30° 以上）得站到 Y ≈ +100，所以北界放到 100。
const X_MIN := -70.0
const X_MAX := 70.0
const Y_MIN := -70.0
const Y_MAX := 100.0

# ---------------------------------------------------------------- 各段尺寸
const PLAT_X0 := -45.0
const PLAT_X1 := 45.0
const PLAT_Y0 := -48.0  ## 站台朝轨道的边
const PLAT_Y1 := -40.0  ## 站台朝广场的边
const PLAT_H := 0.25  ## 站台比地面高 25 cm，一步就能迈上去

const TRACK_Y0 := -60.0  ## 轨道沟北沿
const TRACK_Y1 := -50.0  ## 轨道沟南沿
const TRACK_DEPTH := 1.15  ## 轨面比站台低这么多，所以火车地板差不多齐站台

const PLAZA_X := 32.0
const PLAZA_Y0 := -40.0
const PLAZA_Y1 := 10.0

const AVE_HALF := 7.0
const AVE_Y0 := 10.0
const AVE_Y1 := 100.0
const FLARE_Y0 := 70.0  ## 漏斗段起点：路面从这里开始放宽
const FLARE_HALF := 8.0

const TOWER_Y := 146.0
const TOWER_H := 48.0

## 出生点：站台上，靠东一点，面朝出站方向（北）。
const SPAWN_X := 6.0
const SPAWN_Y := -44.0

## 每层楼高。立面分层、腰线位置、窗顶高度全从这一个数推出来。
const FLOOR_H := 3.4


func _ready() -> void:
	_environment()

	var world := Node3D.new()
	world.name = "World"
	add_child(world)

	_ground(world)
	_rails(world)
	_station(world)
	_plaza(world)
	_avenue(world)
	_road_patches(world)
	_west_side(world)
	_east_side(world)
	_avenue_shops(world)
	_far_plaza(world)
	_tower(world)
	_bounds(world)
	_station_flanks(world)
	_station_props(world)
	_plaza_props(world)
	_plaza_dressing(world)

	_setup_player()


func _group(parent: Node3D, node_name: String) -> Node3D:
	var n := Node3D.new()
	n.name = node_name
	parent.add_child(n)
	return n


# ================================================================ 环境

func _environment() -> void:
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	var env := Environment.new()

	# 天空：上方还留着蓝，地平线是夕阳的橙。这个组合是「暮色」最省的做法 ——
	# 不需要体积云，也不需要后处理，只要两个颜色对。
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	# 上方的蓝压深、地平线的橙降饱和。第一版 #2f3350 → #d99a63 在 24 m 的
	# 视高里铺满半个屏幕，粉紫的过渡带比整条街还抢眼 —— 天空比建筑亮是对的，
	# 但天空的颜色不该是画面里最鲜艳的东西。
	psm.sky_top_color = Color("#262c47")
	psm.sky_horizon_color = Color("#c9926b")
	psm.sky_curve = 0.32
	psm.ground_horizon_color = Color("#7d6149")
	psm.ground_bottom_color = Color("#241f1a")
	psm.sun_angle_max = 22.0
	sky.sky_material = psm
	env.sky = sky

	env.background_mode = Environment.BG_SKY
	# 环境光不用 SKY 而用手调的冷灰。用 SKY 的话天空的上半是深蓝紫，阴影面
	# 会被染成明确的天蓝 —— 站台在雨棚底下只剩这一路光，整块地面看起来像雪。
	# 冷灰（#8b90a3）保住了「阴影偏冷」的物理，但饱和度和天空解耦了。
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#8b90a3")
	env.ambient_light_energy = 0.68
	env.ambient_light_sky_contribution = 0.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	# white 的作用是压高光。6.0 会把整个画面往下压一档，暗部直接糊死；
	# 1.0 是「只压灯头和窗户」，街面保住细节。
	env.tonemap_white = 1.0

	# 深度雾是「塔看起来在远处」的唯一手段，但 0.0045 会把整场糊成一片土黄 ——
	# 试出来的甜点是 0.0016：146 m 外的塔保住约 79% 对比度，轮廓清楚但不刺眼。
	env.fog_enabled = true
	env.fog_light_color = Color("#bd9d7a")
	env.fog_density = 0.0016
	env.fog_sky_affect = 0.12

	# AO 是这套立面能不能读出来的关键。墙脚、窗套、腰线都只有 6…15 cm 的凸出，
	# 靠直射光根本投不出影子（太阳仰角 16°，全在墙的另一侧），全靠这一层
	# 接触阴影把它们从墙面上「抠」出来。
	#
	# 半径必须压到 1 m 以内。第一版给 2.0，采样范围盖过了一整扇窗，结果
	# 所有细节的对比全被平均掉 —— AO 开着，画面反而更平。
	env.ssao_enabled = true
	env.ssao_radius = 0.9
	env.ssao_intensity = 2.6
	env.ssao_power = 1.8
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.12

	# 轻微提对比、压一点饱和：程序化纹理本身是灰度的，颜色全来自 albedo_color，
	# 不提对比的话整条街会糊成一片米黄。
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.05

	we.environment = env
	add_child(we)

	# 低角度夕阳从西边（海那边）照进来。仰角压到 14°，正好让所有横向的墙
	# 在另一侧投出长影子 —— 这是工业城黄昏最早读出来的东西。
	#
	# 方位从 −112° 改到 −80°。−112° 是从西北来，而玩家的主视向是朝北 ——
	# 结果是所有临街的南立面全在阴影里，整条街黑成一片剪影，立面上做的
	# 门窗细节一个都看不见。−80° 略偏西南，东西向的立面各有一半受光。
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color("#ffb27a")
	sun.light_energy = 1.5
	sun.rotation_degrees = Vector3(-14.0, -80.0, 0.0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 140.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	# 影子边缘要有一点软过渡。硬边的 16° 斜阳会把墙面切成「亮」和「黑」两块，
	# 中间什么都没有 —— 而这套立面的全部信息都在中间调里。
	sun.shadow_blur = 1.6
	add_child(sun)

	# 天光补光。夕阳从西边低角度照进来，14 m 宽的大道是一条街谷 ——
	# 东侧立面整天收不到直射光，只剩天空 ambient，渲染出来是死黑。
	# 这里补一盏无阴影的冷色平行光模拟天空漫射：阴影面因此偏冷，受光面偏暖，
	# 冷暖对比本身就是黄昏的读法。能量从 0.34 提到 0.48 —— 0.34 时背光立面
	# 只剩轮廓，门窗这些细节全部沉进黑里，等于白做。
	var fill := DirectionalLight3D.new()
	fill.name = "SkyFill"
	fill.light_color = Color("#8ba4c8")
	fill.light_energy = 0.60
	fill.rotation_degrees = Vector3(-58.0, 62.0, 0.0)
	fill.shadow_enabled = false
	add_child(fill)


# ================================================================ 立面工具箱

## 一堵带全套零件的立面。
##
## 这是这一版「房子为什么好看」的全部答案，集中在这里：一块墙之所以读成房子，
## 不是因为墙本身，而是因为它上面有东西投下影子。清单按视觉贡献排：
##   1. 窗套 + 窗台 —— 每扇窗在墙上挖出一个有厚度的洞
##   2. 墙脚 + 檐口 —— 把墙和地、墙和屋顶的交接压住
##   3. 腰线 —— 分层，两层楼和三层楼因此不同
##   4. 转角条 —— 给直角一个厚度
##   5. 雨落管 —— 一根细线，撑起整面墙的尺度感
##
## 参数 x/y 是**墙面中心**的地图坐标，axis 指向室外，along 是这面墙的宽。
func _facade(g: Node3D, tag: String, x: float, y: float, axis: Vector3,
		along: float, height: float, cols: int, floors: int,
		door_col: int, wall_mat: String, ground: float = 0.0) -> void:
	# 沿墙方向的单位步进（地图坐标）。世界方向转 90° 之后 Y 要再翻一次。
	var step := Vector2(-axis.z, -axis.x)
	var spacing := along / float(cols)
	var fh := (height - ground) / float(floors)

	# ---- 腰线：每层顶一条，底层不画（墙脚已经占了位置）
	for f in range(1, floors):
		B.string_course(g, "%sCourse%d" % [tag, f], x, y,
			ground + fh * float(f) - 0.12, axis, along + 0.06)

	# ---- 转角条：两端各一条
	for s in [-1.0, 1.0]:
		B.corner_band(g, "%sQuoin%s" % [tag, "A" if s < 0.0 else "B"],
			x + step.x * along * 0.5 * s, y + step.y * along * 0.5 * s,
			height - ground, axis, -s, 0.44, wall_mat)

	# ---- 雨落管：只在一端放一根。两端都放会变成对称装饰，反而假。
	B.downpipe(g, "%sPipe" % tag, x + step.x * (along * 0.5 - 0.55),
		y + step.y * (along * 0.5 - 0.55), height - 0.40, axis)

	# ---- 窗与门
	for f in floors:
		var win_h := fh * 0.46
		var base := ground + fh * float(f) + fh * 0.26
		for c in cols:
			var off := (float(c) + 0.5 - float(cols) * 0.5) * spacing
			var px := x + step.x * off
			var py := y + step.y * off
			if f == 0 and c == door_col:
				B.doorway(g, "%sDoor" % tag, px, py, axis, minf(1.9, spacing * 0.6),
					fh * 0.75)
				continue
			# 窗宽不超过柱距的 62%：再宽就没有墙垛，一排窗会连成玻璃幕墙
			var ww := minf(1.55, spacing * 0.62)
			# 三扇里有一扇是暗的（屋里没人）。全亮像布景，全暗像废弃。
			var gm := "window_dim" if ((c + f * 3) % 3) == 2 else "window"
			B.window(g, "%sWin%d%d" % [tag, f, c], px, py, base, axis, ww, win_h, gm)


## 一栋排屋：主体 + 屋顶 + 朝街的全套立面 + 两端山墙上的窗。
##
## 山墙也要开窗。侧墙是一整片 13×8 m 的纯色平面，玩家从广场一路走过来，
## 看到的第一面往往是山墙 —— 一面空白的墙把「这是一栋楼」的全部信息
## 抵消掉了，比正立面做得再好都亏。
func _shophouse(g: Node3D, tag: String, cx: float, cy: float, w: float, d: float,
		h: float, axis: Vector3, cols: int, floors: int, door_col: int,
		wall: String, roof: String) -> void:
	B.box(g, "%sBody" % tag, cx, cy, 0.0, w, h, d, wall)
	B.plinth(g, "%sPlinth" % tag, cx, cy, w, d)
	B.cornice(g, "%sCornice" % tag, cx, cy, h, w, d)
	B.gable_roof(g, "%sRoof" % tag, cx, cy, h, w + 1.1, d + 1.1, h * 0.26, roof)
	# 山墙：屋脊南北向，所以三角在南北两端
	B.gable_wall(g, "%sGableN" % tag, cx, cy + d * 0.5 + 0.35, h, w + 0.9,
		h * 0.26, wall)
	B.gable_wall(g, "%sGableS" % tag, cx, cy - d * 0.5 - 0.35, h, w + 0.9,
		h * 0.26, wall)
	# 两端山墙各三扇窗 + 山尖一个圆窗。比正立面的窗小一号、暗一档：朝北
	# 那面整天没有直射光，而且这是一堵 13 m 宽的端墙 —— 只放两扇小窗的话，
	# 走近了看到的仍然是一块空板子。
	var gfh := h / float(floors)
	for s in [-1.0, 1.0]:
		var gax: Vector3 = B.AX_N if s > 0.0 else B.AX_S
		var gy: float = cy + s * d * 0.5
		for f in floors:
			for c in 3:
				B.window(g, "%sSw%d%d" % [tag, int(s + 1.0), f * 10 + c],
					cx + (float(c) - 1.0) * w * 0.30,
					gy, gfh * float(f) + gfh * 0.26, gax, 1.3, gfh * 0.46,
					"window_dim")
		# 山尖圆窗：三角区是一大片纯色，一个洞就够破局
		var rw := MeshInstance3D.new()
		rw.name = "%sOculus%d" % [tag, int(s + 1.0)]
		var rcm := CylinderMesh.new()
		rcm.top_radius = 0.72
		rcm.bottom_radius = 0.72
		rcm.height = 0.26
		rcm.radial_segments = 10
		rw.mesh = rcm
		rw.rotation.x = PI * 0.5
		rw.material_override = P.get_mat("trim_dark")
		rw.position = Vector3(cx, h + h * 0.26 * 0.34,
			-(gy + s * 0.38))
		g.add_child(rw)
	# 朝街那一面。墙面位置由 axis 决定：沿 axis 从中心推出去半个进深或半宽。
	var fx := cx + axis.x * (w * 0.5 if absf(axis.x) > 0.5 else 0.0)
	var fy := cy - axis.z * (d * 0.5 if absf(axis.z) > 0.5 else 0.0)
	var along := d if absf(axis.x) > 0.5 else w
	_facade(g, tag, fx, fy, axis, along, h, cols, floors, door_col, wall)


# ================================================================ 地面

func _ground(world: Node3D) -> void:
	var g := _group(world, "Ground")

	# 底层一通到底，顶面 −1.15：轨道沟就是靠它当地面，不需要单独挖。
	B.box(g, "Bed", 0.0, (Y_MIN + Y_MAX) * 0.5, -2.15,
		X_MAX - X_MIN, 1.0, Y_MAX - Y_MIN, "ground")

	# 南北两块垫到 0。中间 TRACK_Y0…TRACK_Y1 那 10 m 不垫，自然成为沟。
	B.box(g, "FillNorth", 0.0, (TRACK_Y0 + Y_MAX) * 0.5, -TRACK_DEPTH,
		X_MAX - X_MIN, TRACK_DEPTH, Y_MAX - TRACK_Y0, "ground")
	B.box(g, "FillSouth", 0.0, (Y_MIN + TRACK_Y1) * 0.5, -TRACK_DEPTH,
		X_MAX - X_MIN, TRACK_DEPTH, TRACK_Y1 - Y_MIN, "ground")

	# 沟底道床：碎石，比土略亮一点，否则整条沟是个黑洞
	B.slab(g, "Ballast", 0.0, (TRACK_Y0 + TRACK_Y1) * 0.5, -TRACK_DEPTH + 0.04,
		X_MAX - X_MIN, TRACK_Y1 - TRACK_Y0, "coal")

	# 广场与大道。都是贴面薄板，压在 FillNorth 顶面上。
	B.slab(g, "PlazaFloor", 0.0, (PLAZA_Y0 + PLAZA_Y1) * 0.5, 0.02,
		PLAZA_X * 2.0, PLAZA_Y1 - PLAZA_Y0, "stone")
	B.slab(g, "AveFloor", 0.0, (AVE_Y0 + FLARE_Y0) * 0.5, 0.03,
		AVE_HALF * 2.0, FLARE_Y0 - AVE_Y0, "road")

	# 漏斗段：6 段 5 m，宽度从 14 线性插到 16。
	# 一块梯形要自建多边形；这里用 6 块渐宽的矩形拼，2 m 的总变化分摊到
	# 6 段上，每段只宽 17 cm —— 走过时看不出台阶感，但视线会觉得路面在张开。
	var seg := (AVE_Y1 - FLARE_Y0) / 6.0
	for i in 6:
		var t := (float(i) + 0.5) / 6.0
		var half := lerpf(AVE_HALF, FLARE_HALF, t)
		B.slab(g, "AveFlare%d" % i, 0.0, FLARE_Y0 + seg * (float(i) + 0.5), 0.03,
			half * 2.0, seg + 0.02, "road")

	# 大道两侧的路缘石：一条 30 cm 高、25 cm 宽的石条。没有它，路面和
	# 店铺墙根是直接相连的，读起来像一块水泥大板而不是街。
	for side in [-1.0, 1.0]:
		var x: float = AVE_HALF * side
		B.box(g, "CurbW" if side < 0.0 else "CurbE", x, (AVE_Y0 + FLARE_Y0) * 0.5,
			0.0, 0.28, 0.16, FLARE_Y0 - AVE_Y0, "curb", false)
		var cx: float = FLARE_HALF * side
		B.box(g, "CurbFlareW" if side < 0.0 else "CurbFlareE", cx,
			(AVE_Y1 + FLARE_Y0) * 0.5, 0.0, 0.28, 0.16,
			AVE_Y1 - FLARE_Y0, "curb", false)

	# 站台面。整块抬高 25 cm，边沿用同一块盒子的侧面 —— 站台边天然有一道
	# 25 cm 的坎，玩家迈一步就上去了（上限 45 cm）。
	B.box(g, "PlatformSlab", 0.0, (PLAT_Y0 + PLAT_Y1) * 0.5, 0.0,
		PLAT_X1 - PLAT_X0, PLAT_H, PLAT_Y1 - PLAT_Y0, "platform")
	# 安全黄线，贴在站台边往里 40 cm
	B.box(g, "PlatformLine", 0.0, PLAT_Y0 + 0.4, PLAT_H, PLAT_X1 - PLAT_X0,
		0.02, 0.16, "brass", false)
	# 站台边沿那圈石条。比台面深一档，把 25 cm 的坎画出厚度。
	B.box(g, "PlatformNose", 0.0, PLAT_Y0 + 0.08, 0.0, PLAT_X1 - PLAT_X0, PLAT_H,
		0.16, "curb", false)


func _rails(world: Node3D) -> void:
	var g := _group(world, "Rails")
	# 两股道：Y = −58（货运）、Y = −52（客运）。每股两根轨，标准轨距 1.435 m。
	# 轨面在 −1.10，比沟底高 5 cm。
	for lane_y in [-58.0, -52.0]:
		for off in [-0.72, 0.72]:
			B.box(g, "Rail_%d_%d" % [int(lane_y), int(off * 100.0)],
				0.0, lane_y + off, -TRACK_DEPTH + 0.05,
				X_MAX - X_MIN, 0.10, 0.09, "rail", false)
		# 枕木。4 m 一根 —— 间距再密玩家在站台上也分辨不出来，但节点数会翻倍。
		var x := X_MIN
		while x < X_MAX:
			B.box(g, "Tie_%d_%d" % [int(lane_y), int(x)],
				x, lane_y, -TRACK_DEPTH + 0.02, 0.26, 0.12, 2.6, "timber", false)
			x += 4.0


# ================================================================ 灰堤站

func _station(world: Node3D) -> void:
	var g := _group(world, "Station")

	# ---- 站房。规划表里写的是 (0, −52) 90×14，那是「跨线站房」的算法，
	# 但跨线站房会把站台和广场之间的动线切断。改成侧式站房放在站台西端：
	# 玩家下车站台，站房在左手边，正面朝北直接进广场 —— 这是 S2 需要的动线。
	var st_x := -56.0
	var st_y := -44.0
	var st_w := 20.0
	var st_d := 16.0
	var st_h := 7.2
	B.box(g, "StationBody", st_x, st_y, 0.0, st_w, st_h, st_d, "wall_b")
	B.plinth(g, "StationPlinth", st_x, st_y, st_w, st_d)
	# 二层挑出 1.2 m，形成一道压在头上的檐口
	B.box(g, "StationUpper", st_x, st_y, st_h * 0.58, st_w + 1.2, st_h * 0.42,
		st_d + 1.2, "wall_a")
	B.cornice(g, "StationCornice", st_x, st_y, st_h, st_w + 1.2, st_d + 1.2)
	B.gable_roof(g, "StationRoof", st_x, st_y, st_h, st_w + 2.0, st_d + 2.0, 3.2,
		"roof_slate")
	B.gable_wall(g, "StationGableN", st_x, st_y + st_d * 0.5 + 0.8, st_h, st_w + 1.6,
		3.2, "wall_a")
	B.gable_wall(g, "StationGableS", st_x, st_y - st_d * 0.5 - 0.8, st_h, st_w + 1.6,
		3.2, "wall_a")

	# 站房朝站台（东）的那一面。这是玩家出生后正对着的立面 —— 全关卡唯一
	# 一处值得做满的地方：双层挑檐、三扇高窗、门、雨水管、转角条。
	var st_face := st_x + st_w * 0.5
	var st_axis := B.AX_E
	# 下层三扇高窗（候车室）
	for i in 3:
		B.window(g, "StWin%d" % i, st_face, st_y - 4.4 + float(i) * 3.2, 1.35,
			st_axis, 1.9, 2.5, "window" if i != 1 else "window_dim")
	B.doorway(g, "StDoor", st_face, st_y + 5.2, st_axis, 2.2, 3.0)
	# 上层三扇矮窗，比下层小 —— 二层是办公室，不是候车室
	for i in 3:
		B.window(g, "StWinUp%d" % i, st_face, st_y - 4.4 + float(i) * 3.2, 5.0,
			st_axis, 1.5, 1.6, "window_dim")
	B.string_course(g, "StCourse", st_face, st_y, st_h * 0.58 - 0.15, st_axis,
		st_d + 1.4)
	for s in [-1.0, 1.0]:
		B.corner_band(g, "StQuoin%s" % ("S" if s < 0.0 else "N"), st_face,
			st_y + s * st_d * 0.5, st_h, st_axis, s, 0.5, "wall_a")
	B.downpipe(g, "StPipe", st_face, st_y - st_d * 0.5 + 0.7, st_h * 0.58, st_axis)

	# 站牌：两根柱子撑一块横牌。这是玩家出站前唯一会读的字 ——
	# 做不了字，就给一块铜牌加两道压边，读起来像「有字的牌子」。
	B.box(g, "SignPostA", st_face + 1.6, st_y - 6.2, 0.0, 0.14, 3.2, 0.14,
		"metal", false)
	B.box(g, "SignPostB", st_face + 1.6, st_y - 2.2, 0.0, 0.14, 3.2, 0.14,
		"metal", false)
	B.box(g, "SignBoard", st_face + 1.6, st_y - 4.2, 2.5, 0.10, 0.86, 4.4,
		"brass", false)
	for s in [-1.0, 1.0]:
		B.box(g, "SignEdge%s" % ("S" if s < 0.0 else "N"), st_face + 1.6,
			st_y - 4.2 + s * 2.16, 2.44, 0.14, 0.98, 0.10, "trim_dark", false)

	# ---- 站台雨棚。铁架 + 波纹铁皮，柱每 7 m。
	# 顶板做成两块中间留一条 30 cm 的缝：从下方看能看见一线天，站台才不像
	# 一条走廊。缝在正中间，玩家抬头就在它下面。
	var aw_y := (PLAT_Y0 + PLAT_Y1) * 0.5
	var aw_x0 := PLAT_X0 + 3.0
	var aw_x1 := PLAT_X1
	var aw_w := aw_x1 - aw_x0
	for side in [-1.0, 1.0]:
		B.box(g, "AwningRoof%s" % ("N" if side > 0.0 else "S"),
			(aw_x0 + aw_x1) * 0.5, aw_y + side * 2.05, 4.62,
			aw_w, 0.18, 3.6, "roof_tin", false)
	# 雨棚的前后檐口压条，让 4.6 m 高那块板有个厚度
	for side in [-1.0, 1.0]:
		B.box(g, "AwningEdge%s" % ("N" if side > 0.0 else "S"),
			(aw_x0 + aw_x1) * 0.5, aw_y + side * 3.83, 4.44,
			aw_w, 0.34, 0.16, "trim_dark", false)
	# 柱距 7 m，但起点偏 3.5 m：不偏的话会有一根柱子正好立在 x = 0 的中轴上，
	# 从站台中央看塔时被它劈成两半。偏半跨之后中轴空出 7 m 宽的一跨，
	# 玩家出站时看到的是一个「门」，不是一根柱。
	for i in 12:
		var px := aw_x0 + 3.5 + float(i) * 7.0
		if px > aw_x1:
			break
		for side in [-1.0, 1.0]:
			var cy: float = aw_y + side * 3.5
			B.box(g, "AwCol%d%s" % [i, "N" if side > 0.0 else "S"], px, cy,
				PLAT_H, 0.24, 4.4, 0.24, "metal", true)
			# 柱脚一块铸铁墩 + 柱头一块托板：柱子两端有交代，才不像插在地里
			B.box(g, "AwFoot%d%s" % [i, "N" if side > 0.0 else "S"], px, cy,
				PLAT_H, 0.44, 0.24, 0.44, "metal", false)
			B.box(g, "AwCap%d%s" % [i, "N" if side > 0.0 else "S"], px, cy,
				PLAT_H + 4.30, 0.42, 0.12, 0.42, "metal", false)
	# 柱子上挂的钟。规划说 6 口，全停 11:40 —— 这里只做摆件，指针角度后面
	# 接「回响」系统时再动。位置必须落在柱子上（每根柱间隔 7 m，隔一根挂一只），
	# 否则钟会悬在半空 —— 第一版按 13.5 m 均分，六只全飘着。
	for i in 6:
		var px := aw_x0 + 3.5 + float(i * 2) * 7.0
		B.box(g, "ClockRim%d" % i, px, aw_y + 3.5, 3.3, 0.50, 0.50, 0.10,
			"trim_dark", false)
		B.box(g, "ClockFace%d" % i, px, aw_y + 3.5, 3.36, 0.42, 0.42, 0.10,
			"brass", false)

	# ---- 跨轨天桥。放在站台东端之外，跨过两股道通向煤场（不开放）。
	# 它存在的唯一理由是给站台加一道压下来的水平线 —— 站台空间太扁了。
	var br_x := 52.0
	B.box(g, "BridgeDeck", br_x, -48.0, 6.2, 7.0, 0.36, 30.0, "metal", false)
	for side in [-1.0, 1.0]:
		B.box(g, "BridgeRail%s" % ("E" if side > 0.0 else "W"),
			br_x + side * 3.3, -48.0, 6.56, 0.12, 0.9, 30.0, "metal", false)
	# 四根支撑立柱，落在沟底
	for px in [br_x - 2.6, br_x + 2.6]:
		for py in [-58.0, -52.0]:
			B.box(g, "BridgeLeg", px, py, -TRACK_DEPTH, 0.34, 6.2 + TRACK_DEPTH, 0.34,
				"metal", true)


## 站台东西两端之外的厂区体量。
##
## 没有它们，站在站台中央往东西看，115 m 外就是底板边缘 —— 地平线上会出现
## 一条「世界断掉」的直线，天空直接压在土地断面上。几栋矮楼加两座烟囱，
## 让边界看起来是「城镇继续往那边长」，而不是地图到此为止。
func _station_flanks(world: Node3D) -> void:
	var g := _group(world, "StationFlanks")

	# 东端：货场仓库 + 煤棚，压在 X = +58 … +70
	B.box(g, "EastShed", 62.0, -44.0, 0.0, 16.0, 7.0, 26.0, "brick_dark")
	B.cornice(g, "EastShedCornice", 62.0, -44.0, 7.0, 16.0, 26.0)
	B.gable_roof(g, "EastShedRoof", 62.0, -44.0, 7.0, 17.2, 27.2, 2.4, "roof_tin")
	# 仓库门：一扇 5 m 宽的推拉门，四道竖向压条当门框
	B.box(g, "EastShedDoor", 54.0, -44.0, 0.0, 0.16, 4.2, 5.0, "timber", false)
	for i in 3:
		B.box(g, "EastShedDoorRib%d" % i, 53.92, -45.6 + float(i) * 1.6, 0.0,
			0.10, 4.0, 0.14, "trim_dark", false)
	B.box(g, "EastStack", 66.0, -58.0, 7.0, 2.0, 12.0, 2.0, "brick")
	B.box(g, "EastStackCap", 66.0, -58.0, 18.7, 2.4, 0.4, 2.4, "trim_dark", false)

	# 西端：站房背后再垫一栋，把 X = −70 那条边填掉
	B.box(g, "WestShed", -66.0, -30.0, 0.0, 8.0, 8.0, 22.0, "wall_b2")
	B.gable_roof(g, "WestShedRoof", -66.0, -30.0, 8.0, 9.2, 23.2, 2.2, "roof")

	# 南面越过轨道的煤场：几座煤仓剪影，高度压到 9 m 以下 —— 它们在南边界外，
	# 但只要抬头就能越过栅栏看见，太高的会顶到塔的视线里。
	# 底板只铺到 Y = −70，所以这条带要单独垫一块，否则煤仓是悬空的。
	B.box(g, "SouthApron", 0.0, -86.0, -2.15, 144.0, 2.15, 32.0, "ground", false)
	for i in 4:
		var cx := -48.0 + float(i) * 30.0
		var sh := 8.0 + float(i % 2) * 2.0
		B.box(g, "CoalSilo%d" % i, cx, -82.0, 0.0, 10.0, sh, 12.0, "wall_b2")
		B.box(g, "CoalSiloCap%d" % i, cx, -82.0, sh, 10.8, 0.34, 12.8, "roof_tin",
			false)


func _station_props(world: Node3D) -> void:
	var g := _group(world, "StationProps")

	# 站台长椅 ×3
	for i in 3:
		var x := -18.0 + float(i) * 22.0
		B.box(g, "BenchSeat%d" % i, x, PLAT_Y1 - 1.4, PLAT_H + 0.44, 2.2, 0.12, 0.52,
			"timber", true)
		B.box(g, "BenchBack%d" % i, x, PLAT_Y1 - 1.12, PLAT_H + 0.52, 2.2, 0.62, 0.10,
			"timber", true)
		for side in [-1.0, 1.0]:
			B.box(g, "BenchLeg%d" % i, x + side * 0.9, PLAT_Y1 - 1.4, PLAT_H,
				0.12, 0.44, 0.46, "metal", false)

	# 行李推车（锚点 E）。规划 §8 里「自己滑回货堆、重复三次」的演出落点，
	# 这一版只放静态车，行为等剧情系统接进来。
	var cx := 18.0
	var cy := -52.0
	B.box(g, "CartBed", cx, cy, 0.62, 2.4, 0.14, 1.3, "timber", true)
	B.box(g, "CartLoad", cx, cy, 0.76, 1.7, 0.62, 1.0, "brick", true)
	for side in [-1.0, 1.0]:
		for fy in [-0.5, 0.5]:
			B.box(g, "CartWheel%d" % int(side * fy * 10.0), cx + side * 0.95,
				cy + fy, 0.28, 0.16, 0.56, 0.56, "metal", false)
	# 货堆。三个不齐的箱子，和一排整齐的箱子读起来完全是两种场所。
	B.box(g, "CargoA", 24.0, -53.4, 0.0, 1.5, 1.1, 1.3, "timber", true)
	B.box(g, "CargoB", 24.4, -53.0, 1.1, 1.2, 0.9, 1.0, "timber", true)
	B.box(g, "CargoC", 26.2, -52.6, 0.0, 1.3, 1.5, 1.4, "brick", true)

	# 站台边那道黄线外面再加一道矮栏 —— 防止玩家直接走下 1.15 m 的轨道沟。
	# 不做隐形墙：矮栏看得见，玩家知道自己为什么过不去。
	# 用 wall 而不是 fence：fence 的柱子是从地面起的，会陷进 25 cm 的站台里。
	B.wall(g, "PlatformGuard", PLAT_X0, PLAT_Y0 + 0.15, PLAT_X1, PLAT_Y0 + 0.15,
		PLAT_H, 1.05, 0.12, "metal")


# ================================================================ 站前广场

func _plaza(world: Node3D) -> void:
	var g := _group(world, "Plaza")

	# 报时亭：四柱、一块顶、一口铜钟。规划 §6.5 说它是 S3「报时的铜铃」。
	#
	# 尺寸从 6×6 缩到 5×5、柱高从 3.4 压到 3.0：亭子和钟塔都在 X = 0 这条
	# 中轴上，站在出站口看过去，6 m 宽的亭子顶（檐高 5 m）正好把塔的下半截
	# 切掉 —— 这直接违反 §7「塔必须永远看得见」。5×5 的情况下，从 S3 站位
	# (4, −30) 看，亭子顶仰角 8.5°、塔顶仰角 15°，塔还留着 6.5° 的余量。
	# 亭子放在 x = −15 而不是广场正中。它和钟塔同在中轴上的话，从站台到广场
	# 这一段（Y −37 … −16）看过去，塔的下半截永远被它切掉 —— 实测探针
	# 「广场南」那一条就是被 PavilionRoof 挡住的。铺装的放射线仍然从广场
	# 几何中心出发：线是地面纹理，亭子是一件家具，两件事不该绑在一起。
	var px := -15.0
	var py := -15.0
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			B.box(g, "PavilionCol%s%s" % ["W" if sx < 0.0 else "E",
				"S" if sy < 0.0 else "N"],
				px + sx * 2.1, py + sy * 2.1, 0.0, 0.30, 3.0, 0.30, "trim", true)
			# 柱础：一块 10 cm 高的方墩，柱子才不是直接从地砖里长出来的
			B.box(g, "PavilionBase%s%s" % ["W" if sx < 0.0 else "E",
				"S" if sy < 0.0 else "N"],
				px + sx * 2.1, py + sy * 2.1, 0.0, 0.48, 0.14, 0.48, "trim_dark", false)
	B.box(g, "PavilionRing", px, py, 3.0, 5.0, 0.26, 5.0, "trim", false)
	B.gable_roof(g, "PavilionRoof", px, py, 3.26, 5.8, 5.8, 1.1, "roof_slate")
	# 铜钟：圆柱当钟身。停在 11:40 这件事这版只做姿态，不做动画。
	var bell := MeshInstance3D.new()
	bell.name = "PavilionBell"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.30
	cyl.bottom_radius = 0.46
	cyl.height = 0.74
	cyl.radial_segments = 12
	bell.mesh = cyl
	bell.material_override = P.get_mat("brass")
	bell.position = Vector3(px, 2.50, -py)
	g.add_child(bell)
	B.box(g, "PavilionBellYoke", px, py, 2.90, 0.14, 0.26, 0.14, "metal", false)

	# 广场铺装的放射线。规划 §6.5 说「故意画偏 3°」，第一眼看不出、走近发现
	# 线不指向钟塔 —— 这是给二周目的。用 12 条深色石条从亭子向外铺。
	for i in 12:
		var ang := TAU * float(i) / 12.0 + deg_to_rad(3.0)
		var bar_len := 30.0
		var cx := cos(ang) * bar_len * 0.5
		var cy := -15.0 + sin(ang) * bar_len * 0.5
		# 厚度只有 4 mm。0.04 m 时侧壁在低角度夕阳下会形成一条连续亮线 ——
		# 因为水平法线在这个光照下比地面亮得多，整片铺装看起来像画了白线。
		var bar := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(bar_len, 0.004, 0.30)
		bar.name = "Radial%d" % i
		bar.mesh = bm
		bar.material_override = P.get_mat("curb")
		# 局部 X 轴要指向 (cos ang, 0, −sin ang)：绕 Y 转 ang 正好做到
		bar.rotation.y = ang
		bar.position = Vector3(cx, 0.0225, -cy)
		g.add_child(bar)


func _plaza_props(world: Node3D) -> void:
	var g := _group(world, "PlazaProps")
	# 四角煤气灯。规划 §6.5：「暮色演出时同时暗一格」—— 这一版只放灯，
	# 暗一格的编排等暮色事件系统。
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			B.lamp_post(g, "Lamp%d%d" % [int(sx), int(sy)], sx * 26.0,
				-34.0 if sy < 0.0 else 4.0)

	# 广场周边零散道具：一张告示牌、两堆货
	B.box(g, "BoardPostA", -20.0, -30.0, 0.0, 0.12, 2.2, 0.12, "timber", false)
	B.box(g, "BoardPostB", -18.4, -30.0, 0.0, 0.12, 2.2, 0.12, "timber", false)
	B.box(g, "BoardPanel", -19.2, -30.0, 1.1, 1.9, 1.0, 0.12, "timber", false)
	for i in 3:
		B.box(g, "PlazaCrate%d" % i, 24.0 + float(i) * 0.1, 6.0 + float(i) * 1.1, 0.0,
			1.2, 0.9 + float(i) * 0.2, 1.0, "timber", true)


## 广场的陈设。一片 64×50 m 的空地在暮色里就是一张地砖矢量图 ——
## 只有亭子和四盏灯撑不住。这里补的是「有人在这儿活动」的证据：
## 树池、长椅、货板车、酒桶。全部避开 X = 0 的中轴（塔的视线是硬规则）。
func _plaza_dressing(world: Node3D) -> void:
	var g := _group(world, "PlazaDressing")

	# ---- 四个树池，两排，把广场从中间往外撑开
	for spec in [[-24.0, -24.0], [24.0, -24.0], [-25.0, -4.0], [25.0, -13.0]]:
		var px: float = spec[0]
		var py: float = spec[1]
		var tag := "Planter%d%d" % [int(px), int(py)]
		B.box(g, "%sRim" % tag, px, py, 0.0, 2.4, 0.54, 2.4, "trim", true)
		B.box(g, "%sCope" % tag, px, py, 0.48, 2.62, 0.10, 2.62, "trim_dark", false)
		B.box(g, "%sSoil" % tag, px, py, 0.42, 2.05, 0.10, 2.05, "ground", false)
		# 树比大道的行道树小一号：栽在池子里的是景观树，长不了那么高
		B.tree(g, "%sTree" % tag, px, py, 0.78)

	# ---- 长椅。背朝中轴，坐的人面朝塔
	for sx in [-1.0, 1.0]:
		var bx: float = sx * 9.0
		var by := -26.0
		var tag := "PlazaBench%d" % int(sx)
		B.box(g, "%sSeat" % tag, bx, by, 0.46, 2.4, 0.12, 0.56, "timber", true)
		B.box(g, "%sBack" % tag, bx, by - sx * 0.26, 0.54, 2.4, 0.66, 0.10, "timber",
			true)
		for side in [-1.0, 1.0]:
			B.box(g, "%sLeg%d" % [tag, int(side)], bx + side * 1.0, by, 0.0, 0.12, 0.46,
				0.48, "metal", false)

	# ---- 货运板车。广场是货站门口，没有车才是怪的。
	var cx := -30.0
	var cy := -30.0
	B.box(g, "PlazaCartBed", cx, cy, 0.58, 3.2, 0.14, 1.5, "timber", true)
	for side in [-1.0, 1.0]:
		B.box(g, "PlazaCartSide%d" % int(side), cx, cy + side * 0.72, 0.70,
			3.2, 0.42, 0.08, "timber", false)
	for wx in [-1.0, 1.0]:
		B.box(g, "PlazaCartWheel%d" % int(wx), cx + wx * 1.05, cy, 0.30,
			0.14, 0.58, 0.58, "metal", false)
	# 车辕：两根伸向前面的长杆，超出来这一节让车不像一块板
	for side in [-1.0, 1.0]:
		B.box(g, "PlazaCartShaft%d" % int(side), cx + 2.5, cy + side * 0.55, 0.62,
			1.8, 0.10, 0.10, "timber", false)
	# 车上堆的货：三只桶，高度不齐
	for i in 3:
		var barrel := MeshInstance3D.new()
		barrel.name = "PlazaBarrel%d" % i
		var cm := CylinderMesh.new()
		cm.top_radius = 0.30
		cm.bottom_radius = 0.34
		cm.height = 0.78
		cm.radial_segments = 10
		barrel.mesh = cm
		barrel.material_override = P.get_mat("timber")
		barrel.position = Vector3(cx - 0.7 + float(i) * 0.72, 1.06, -cy + (0.0 if i < 2 else 0.5))
		g.add_child(barrel)

	# ---- 酒桶堆：贴着食堂那一侧，说明这儿是卸货点
	for i in 4:
		var bx := 27.5 + float(i % 2) * 0.85
		var by := -30.0 + float(i / 2) * 0.9
		var cm2 := CylinderMesh.new()
		cm2.top_radius = 0.32
		cm2.bottom_radius = 0.36
		cm2.height = 0.86
		cm2.radial_segments = 10
		var br := MeshInstance3D.new()
		br.name = "PlazaKeg%d" % i
		br.mesh = cm2
		br.material_override = P.get_mat("timber")
		br.position = Vector3(bx, 0.43, -by)
		g.add_child(br)


# ================================================================ 钟塔大道

func _avenue(world: Node3D) -> void:
	var g := _group(world, "Avenue")
	# 大道两侧的树。规划 §7 规则三：漏斗段两侧只种树、不建屋。
	# 一棵树是树干 + 三层锥形树冠。第一版用三个方盒子叠起来，20 m 外读成
	# 一排悬空的箱子 —— 锥体是低多边形树唯一的正确答案，斜边的剪影在
	# 逆光下就是一棵树，多一个面都不需要。
	for i in 9:
		# 位置和高度都要抖。等距等高的树列读出来是一条带锯齿的墙，
		# 而规划要的是「路边长着树」。
		for side in [-1.0, 1.0]:
			var y := 74.0 + float(i) * 3.0 + (_rnd(i, int(side) + 5) - 0.5) * 0.9
			var s := 0.92 + _rnd(i, int(side) + 9) * 0.30
			B.tree(g, "%s%d" % ["W" if side < 0.0 else "E", i],
				side * (FLARE_HALF + 2.4) + (_rnd(i, int(side) + 21) - 0.5) * 0.5,
				y, s)


## 确定性伪随机：同一个 (i, salt) 永远同一个值。
##
## 关卡里所有「随机」的摆放都走这里 —— 用 RandomNumberGenerator 的话每次
## 进游戏补丁位置都不同，截图没法比对，探针的断言也会时好时坏。
func _rnd(i: int, salt: int) -> float:
	return float(absi((i * 733 + salt * 1013) * 2654435761) % 9973) / 9973.0


## 路面补丁。整条大道是一块 14×60 的同色铺装，平铺纹理的周期一眼可见 ——
## 走上去像走在方格纸上。撒二十几块深浅不一的补石板，边缘在低角度斜光下
## 各有一条细影，地面立刻有了「被人一处处修过」的层次。
##
## 补丁只有 1 cm 厚且不带碰撞：它是一层贴花，不该绊到玩家。
func _road_patches(world: Node3D) -> void:
	var g := _group(world, "RoadPatches")
	for i in 22:
		var x := lerpf(-6.2, 6.2, _rnd(i, 1))
		var y := lerpf(AVE_Y0 + 3.0, AVE_Y1 - 5.0, _rnd(i, 2))
		# 靠路缘的补丁多、路中央少：中央是车辙走的地方，反而磨得干净
		if absf(x) < 3.0 and _rnd(i, 3) < 0.55:
			continue
		B.box(g, "Patch%d" % i, x, y, 0.030,
			1.1 + _rnd(i, 4) * 2.4, 0.010, 0.9 + _rnd(i, 5) * 2.0,
			"patch_dark" if _rnd(i, 6) < 0.55 else "patch_light", false)
	# 广场下半区也撒几块 —— 出站口到大道之间是同一片铺装，不能只在北边有。
	for i in 10:
		var x := lerpf(-26.0, 26.0, _rnd(i, 7))
		var y := lerpf(PLAZA_Y0 + 4.0, PLAZA_Y1 - 4.0, _rnd(i, 8))
		B.box(g, "PlazaPatch%d" % i, x, y, 0.024,
			1.3 + _rnd(i, 9) * 2.8, 0.010, 1.1 + _rnd(i, 10) * 2.4,
			"patch_dark" if _rnd(i, 11) < 0.5 else "patch_light", false)


# ================================================================ 广场西侧

func _west_side(world: Node3D) -> void:
	var g := _group(world, "WestSide")

	# ---- 旅馆「锚与铆钉」：24×16，11 m，凯尔下榻处（策划案 §8.2）。
	# 它是广场西侧唯一的立面，所以做得比别处细：三层窗、一道门廊、屋顶天窗。
	var hx := -45.0
	var hy := -8.0
	var hw := 24.0
	var hd := 16.0
	var hh := 9.6
	B.box(g, "InnBody", hx, hy, 0.0, hw, hh, hd, "wall_a")
	B.plinth(g, "InnPlinth", hx, hy, hw, hd)
	B.cornice(g, "InnCornice", hx, hy, hh, hw, hd)
	B.gable_roof(g, "InnRoof", hx, hy, hh, hw + 1.4, hd + 1.4, 3.0, "roof_slate")
	B.gable_wall(g, "InnGableN", hx, hy + hd * 0.5 + 0.4, hh, hw + 1.2, 3.0, "wall_a")
	B.gable_wall(g, "InnGableS", hx, hy - hd * 0.5 - 0.4, hh, hw + 1.2, 3.0, "wall_a")
	# 朝东（面向广场）的全套立面：3 层 × 4 列，门在第 2 列
	_facade(g, "Inn", hx + hw * 0.5, hy, B.AX_E, hd, hh, 4, 3, 1, "wall_a")
	# 南北山墙各三扇。朝北那面对着站台 —— 玩家从站台走下来，第一眼看到
	# 的是旅馆的侧墙，不是正立面。
	for sd in [-1.0, 1.0]:
		var gax: Vector3 = B.AX_N if sd > 0.0 else B.AX_S
		for c in 3:
			B.window(g, "InnSw%d%d" % [int(sd + 1.0), c],
				hx + (float(c) - 1.0) * 6.4, hy + sd * hd * 0.5, 1.6,
				gax, 1.4, 1.9, "window_dim")
	# 门廊：一块出挑 2 m 的雨檐 + 两根柱。它盖住了正门 —— 所以门那列
	# 要挪到正中，否则雨檐下面是个窗。
	B.box(g, "InnPorch", hx + hw * 0.5 + 1.0, hy, 3.5, 2.2, 0.24, 5.4, "roof_tin",
		false)
	for sy in [-1.0, 1.0]:
		B.box(g, "InnPorchCol%s" % ("S" if sy < 0.0 else "N"),
			hx + hw * 0.5 + 1.9, hy + sy * 2.3, 0.0, 0.22, 3.5, 0.22, "trim", true)
		B.box(g, "InnPorchCap%s" % ("S" if sy < 0.0 else "N"),
			hx + hw * 0.5 + 1.9, hy + sy * 2.3, 3.3, 0.32, 0.20, 0.32, "trim_dark",
			false)
	# 屋顶两扇老虎窗：斜坡上一块凸起 + 一扇小窗。有它们，屋顶才不是一块斜板。
	for i in 2:
		var dx := hx - 5.0 + float(i) * 10.0
		B.box(g, "InnDormer%d" % i, dx, hy + hd * 0.5 - 1.2, hh + 1.1, 2.4, 2.0, 1.7,
			"wall_a", false)
		B.gable_roof(g, "InnDormerRoof%d" % i, dx, hy + hd * 0.5 - 1.2, hh + 3.1,
			2.9, 2.0, 0.9, "roof_slate", false)
		B.window(g, "InnDormerWin%d" % i, dx, hy + hd * 0.5 - 0.32, hh + 1.45,
			B.AX_N, 1.1, 1.2, "window")

	# ---- 广场西侧再往南，一栋低矮的仓库把西边界填满
	B.box(g, "WestWarehouse", -60.0, -26.0, 0.0, 20.0, 6.0, 18.0, "wall_b2")
	B.plinth(g, "WestWhPlinth", -60.0, -26.0, 20.0, 18.0)
	B.cornice(g, "WestWhCornice", -60.0, -26.0, 6.0, 20.0, 18.0)
	B.gable_roof(g, "WestWhRoof", -60.0, -26.0, 6.0, 21.2, 19.2, 2.0, "roof_tin")
	# 仓库朝东一面：一扇大推拉门 + 两道高窗，别的一概不做
	B.box(g, "WestWhDoor", -50.0, -26.0, 0.0, 0.16, 4.2, 4.6, "timber", false)
	for i in 3:
		B.box(g, "WestWhDoorRib%d" % i, -50.08, -27.5 + float(i) * 1.5, 0.0,
			0.10, 4.0, 0.12, "trim_dark", false)
	B.window(g, "WestWhWin", -50.0, -21.5, 4.6, B.AX_E, 1.4, 1.0, "window_dim")
	B.downpipe(g, "WestWhPipe", -50.0, -17.4, 6.0, B.AX_E)


# ================================================================ 广场东侧

func _east_side(world: Node3D) -> void:
	var g := _group(world, "EastSide")

	# ---- 食堂「三班倒」：20×14，8 m。米拉常客（§4.3）。
	var mx := 42.0
	var my := -20.0
	var mh := 7.6
	B.box(g, "MessBody", mx, my, 0.0, 20.0, mh, 14.0, "wall_b")
	B.plinth(g, "MessPlinth", mx, my, 20.0, 14.0)
	B.cornice(g, "MessCornice", mx, my, mh, 20.0, 14.0)
	B.gable_roof(g, "MessRoof", mx, my, mh, 21.0, 15.0, 2.2, "roof")
	B.gable_wall(g, "MessGableN", mx, my + 7.4, mh, 20.4, 2.2, "wall_b")
	B.gable_wall(g, "MessGableS", mx, my - 7.4, mh, 20.4, 2.2, "wall_b")
	# 朝西（面向广场）的立面：两层 × 3 列
	_facade(g, "Mess", mx - 10.0, my, B.AX_W, 14.0, mh, 3, 2, 1, "wall_b")
	# 山墙窗：食堂的北面对着大道口，是一整片 20 m 宽的空白墙
	for sd in [-1.0, 1.0]:
		var gax: Vector3 = B.AX_N if sd > 0.0 else B.AX_S
		for c in 3:
			B.window(g, "MessSw%d%d" % [int(sd + 1.0), c],
				mx + (float(c) - 1.0) * 5.6, my + sd * 7.0, 1.8,
				gax, 1.3, 1.7, "window_dim")
	# 食堂的遮阳篷。规划说这里永远有人在吃 —— 篷是「营业中」最直接的信号。
	B.awning(g, "MessAwn", mx - 10.0, my - 3.6, 3.1, B.AX_W, 4.2, 1.3)
	# 烟囱：食堂自己烧灶，这是工业城最合理的一根
	B.box(g, "MessChimney", mx + 6.0, my - 4.0, mh, 1.2, 4.4, 1.2, "brick")
	B.box(g, "MessChimneyCap", mx + 6.0, my - 4.0, mh + 4.4, 1.5, 0.3, 1.5,
		"trim_dark", false)

	# ---- 时钟铺「准点」：10×8，7 m。锚点 C —— 橱窗里 40 口钟全停 11:40。
	var cx := 40.0
	var cy := 2.0
	var ch := 6.4
	B.box(g, "ClockBody", cx, cy, 0.0, 10.0, ch, 8.0, "wall_a3")
	B.plinth(g, "ClockPlinth", cx, cy, 10.0, 8.0)
	B.cornice(g, "ClockCornice", cx, cy, ch, 10.0, 8.0)
	B.gable_roof(g, "ClockRoof", cx, cy, ch, 11.0, 9.0, 1.8, "roof")
	B.gable_wall(g, "ClockGableN", cx, cy + 4.4, ch, 10.4, 1.8, "wall_a3")
	B.gable_wall(g, "ClockGableS", cx, cy - 4.4, ch, 10.4, 1.8, "wall_a3")
	# 橱窗：朝西（面向大道）一整片玻璃。窗套比一般的窗厚 —— 它是店面。
	var cfx := cx - 5.0
	B.window(g, "ClockCase", cfx, cy, 0.9, B.AX_W, 4.6, 2.4, "window")
	B.doorway(g, "ClockDoor", cfx, cy - 3.2, B.AX_W, 1.3, 2.5)
	# 橱窗里的 40 口钟：5×8 的小圆盘，全部同一个角度（11:40，时针在 11 和 12
	# 之间偏 11、分针在 8）。
	#
	# 位置必须落在玻璃**前面**。玻璃的外表面在墙面外 13.5 cm，第一版把钟
	# 放在 6 cm 处，等于整排钟埋在发光玻璃后面 —— 一个都看不见，橱窗只剩
	# 一片暖光。
	for row in 5:
		for col in 8:
			var zy := cy - 1.90 + float(col) * 0.545
			var zh := 1.30 + float(row) * 0.42
			B.box(g, "PocketWatch", cfx - 0.17, zy, zh, 0.08, 0.24, 0.24, "brass",
				false)
	# 店招：垂直于墙挑出的深色背板 + 两面铜牌 + 两道挂杆
	B.box(g, "ClockSignBack", cfx - 0.42, cy + 2.4, 3.94, 0.90, 0.88, 0.20,
		"trim_dark", false)
	B.box(g, "ClockSign", cfx - 0.44, cy + 2.4, 4.06, 0.70, 0.64, 0.23, "brass", false)
	for ry in [-0.4, 0.4]:
		B.box(g, "ClockSignRod%d" % int(ry * 10.0), cfx - 0.36, cy + 2.4 + ry, 4.82,
			0.72, 0.06, 0.06, "metal", false)
	B.downpipe(g, "ClockPipe", cfx, cy + 3.4, ch, B.AX_W)


# ================================================================ 大道两侧店铺

func _avenue_shops(world: Node3D) -> void:
	var g := _group(world, "AvenueShops")
	# 6 间，两侧各 3 间。进深 13 m，面宽 14 m，中间留 2 m 的巷。
	# 高度故意不等（8.2 / 9.6 / 7.4）：等高的排屋连成一片会读成一堵墙，
	# 而规划要的是「一条街」。墙色和屋顶也跟着换 —— 相邻两栋同色的话，
	# 高度差会被同色抹平，还是读成一片。中间那间是砖房：整条街只有它
	# 露出一身砌体，反而最像真的。
	var spans := [
		{"y0": 12.0, "h": 8.2, "wall": "wall_a", "roof": "roof", "f": 2, "c": 4},
		{"y0": 28.0, "h": 9.6, "wall": "brick", "roof": "roof_slate", "f": 2, "c": 4},
		{"y0": 44.0, "h": 7.4, "wall": "wall_b2", "roof": "roof_tin", "f": 1, "c": 4},
	]
	var idx := 0
	for side in [-1.0, 1.0]:
		for spec: Dictionary in spans:
			var y0: float = spec["y0"]
			var hh: float = spec["h"]
			var cy: float = y0 + 7.0
			var cx: float = side * 13.5
			var tag := "%s%s" % ["W" if side < 0.0 else "E", str(int(y0))]
			var axis: Vector3 = B.AX_E if side < 0.0 else B.AX_W
			# 两侧错开配色：同一高度的两栋不用同一个色，从街上左右看一眼不重样
			var wall: String = spec["wall"]
			if idx % 2 == 1:
				wall = "wall_a2" if wall == "wall_a" else wall
			_shophouse(g, "Shop%s" % tag, cx, cy, 13.0, 14.0, hh, axis,
				int(spec["c"]), int(spec["f"]), 1, wall, String(spec["roof"]))
			idx += 1
			# 一层店面的遮阳篷。规划 §7 规则二：招牌在 4.5 m 以上，
			# 篷压在 3.0 m —— 只探 1.3 m，不挡站在路中央看塔的视线。
			B.awning(g, "Awn%s" % tag, cx + axis.x * 7.0, cy - 3.3, 3.05, axis,
				3.6, 1.25)
			# 招牌：挑出 0.72 m，挂在 4.5 m。两块板 —— 深色背板 + 黄铜面。
			# 单片的黄铜板在暮色里就是一坨亮黄，加一圈深色边框之后才读成
			# 「牌子」；两根吊杆连回墙面，不然一块板悬在墙外像没做完。
			#
			# 尺寸是 (沿轴厚度, 高, 沿墙宽) —— 招牌是垂直于墙面挑出去的，
			# 写反成 (0.2, 0.8, 2.6) 就变成一块贴在墙上的平板，从街上看
			# 只有一个深色矩形，完全不像牌子。
			var fx: float = cx + axis.x * 7.0
			B.box(g, "SignBack%s" % tag, fx + axis.x * 0.40, cy + 1.2, 4.44,
				0.80, 0.82, 0.18, "trim_dark", false)
			B.box(g, "SignFace%s" % tag, fx + axis.x * 0.42, cy + 1.2, 4.55,
				0.62, 0.58, 0.21, "brass", false)
			for ry in [-1.0, 1.0]:
				B.box(g, "SignRod%s%d" % [tag, int(ry * 10.0)],
					fx + axis.x * 0.36, cy + 1.2 + ry, 5.20, 0.72, 0.06, 0.06,
					"metal", false)

	# 六间店背后的厂区体量。它们不进 P1 的可走范围，只负责把天际线抬起来，
	# 让玩家在大道上转身时不是看见一片空地。
	B.box(g, "BackWorksW", -40.0, 40.0, 0.0, 36.0, 11.0, 40.0, "brick_dark")
	B.cornice(g, "BackWorksWCornice", -40.0, 40.0, 11.0, 36.0, 40.0)
	B.gable_roof(g, "BackWorksWRoof", -40.0, 40.0, 11.0, 37.2, 41.2, 3.0, "roof_tin")
	B.box(g, "BackWorksE", 44.0, 44.0, 0.0, 34.0, 12.0, 44.0, "wall_b2")
	B.cornice(g, "BackWorksECornice", 44.0, 44.0, 12.0, 34.0, 44.0)
	B.gable_roof(g, "BackWorksERoof", 44.0, 44.0, 12.0, 35.2, 45.2, 3.2, "roof_slate")
	# 两根烟囱，全城最高的排烟
	B.box(g, "ChimneyW", -52.0, 52.0, 11.0, 2.2, 16.0, 2.2, "brick")
	B.box(g, "ChimneyWCap", -52.0, 52.0, 26.7, 2.6, 0.4, 2.6, "trim_dark", false)
	B.box(g, "ChimneyE", 54.0, 56.0, 12.0, 2.4, 15.0, 2.4, "brick")
	B.box(g, "ChimneyECap", 54.0, 56.0, 26.7, 2.8, 0.4, 2.8, "trim_dark", false)


# ================================================================ 远景（P2 的钟塔广场）

func _far_plaza(world: Node3D) -> void:
	var g := _group(world, "FarPlaza")

	# 塔脚下的广场铺装。玩家走不到（北界在 Y = 100），但没有它塔就是立在一片
	# 暗土上 —— 46 m 外一眼能看出「这里是空的」，剪影会变成贴片。
	B.slab(g, "FarPlazaFloor", 0.0, 128.0, 0.02, 76.0, 56.0, "stone")

	# 塔基裙台：三级石阶，比塔基 14 m 宽出一圈。有了它塔才是「长在地上」。
	for i in 3:
		var w := 20.0 - float(i) * 2.0
		B.box(g, "TowerStep%d" % i, 0.0, TOWER_Y, float(i) * 0.25, w, 0.25, w,
			"stone", false)

	# 广场东侧：哨塔学院主楼。P2 才开放，这一版只做体量和一层窗 ——
	# 塔的右边必须有个东西，否则那半边天是空的。
	B.box(g, "CollegeMain", 62.0, 138.0, 5.0, 40.0, 12.0, 22.0, "plaster")
	B.plinth(g, "CollegePlinth", 62.0, 138.0, 40.0, 22.0)
	B.gable_roof(g, "CollegeRoof", 62.0, 138.0, 17.0, 41.4, 23.4, 3.4, "roof_slate")
	for i in 3:
		for c in 6:
			B.window(g, "CollegeWin%d%d" % [i, c], 42.0, 130.0 + 2.6 + float(c) * 2.6,
				7.2 + float(i) * 3.0, B.AX_W, 1.3, 1.7)
	# 学院台阶：12 级、0.42 踢面 —— 规划 §6.5 说故意踩在 0.45 的上限边缘，
	# 走上去会有明显的抬腿动作。12 级正好从 0 上到 +5 m 台地。
	for i in 12:
		B.box(g, "CollegeStep%d" % i, 34.0, 124.0 + float(i) * 0.6, 0.0,
			16.0, 0.42 * float(i + 1), 0.6, "stone", false)

	# 广场西侧：两栋临街楼，把放射铺装的左边封住
	B.box(g, "FarWestA", -52.0, 116.0, 0.0, 24.0, 10.0, 26.0, "wall_a2")
	B.cornice(g, "FarWestACornice", -52.0, 116.0, 10.0, 24.0, 26.0)
	B.gable_roof(g, "FarWestARoof", -52.0, 116.0, 10.0, 25.2, 27.2, 2.6, "roof")
	B.box(g, "FarWestB", -58.0, 144.0, 0.0, 20.0, 12.0, 24.0, "wall_b")
	B.gable_roof(g, "FarWestBRoof", -58.0, 144.0, 12.0, 21.2, 25.2, 3.0, "roof_slate")
	# 远处这两栋走不到跟前，只做一层窗就够 —— 46 m 外窗只是个亮点。
	for c in 5:
		B.window(g, "FarWestAWin%d" % c, -40.0, 105.0 + 2.4 + float(c) * 2.6, 2.0,
			B.AX_E, 1.2, 1.6, "window_dim")


# ================================================================ 钟塔

func _tower(world: Node3D) -> void:
	var g := _group(world, "Tower")

	# 塔脚下那块地。P1 边界在 Y = +100，塔在 +146，中间这段玩家走不到，
	# 但没有它塔就是悬空的 —— 47 m 的空气底座在远景里看得出来。
	B.box(g, "TowerGround", 0.0, 138.0, -TRACK_DEPTH, 140.0, TRACK_DEPTH, 76.0,
		"ground", false)

	# 石砌基座 14×14×10。收分从这里有：基座 → 塔身 → 钟室 → 尖顶。
	B.box(g, "TowerBase", 0.0, TOWER_Y, 0.0, 14.0, 10.0, 14.0, "brick")
	# 基座的四道扶壁，朝四个方向各凸出 1 m
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			B.box(g, "TowerButtress%s%s" % ["W" if sx < 0.0 else "E",
				"S" if sy < 0.0 else "N"],
				sx * 7.0, TOWER_Y + sy * 7.0, 0.0, 2.6, 8.0, 2.6, "brick", false)
	# 基座顶端一道挑檐，把 14 m 的砖和上面 10 m 的墙分开
	B.box(g, "TowerBaseCap", 0.0, TOWER_Y, 9.7, 15.2, 0.4, 15.2, "trim_dark", false)
	B.box(g, "TowerShaft1", 0.0, TOWER_Y, 10.0, 10.0, 16.0, 10.0, "wall_b")
	B.box(g, "TowerShaft2", 0.0, TOWER_Y, 26.0, 8.0, 12.0, 8.0, "wall_b")
	# 塔身竖向壁柱：四角各一道，让 16 m 高的墙不是一整块
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			B.box(g, "TowerPilaster%s%s" % ["W" if sx < 0.0 else "E",
				"S" if sy < 0.0 else "N"],
				sx * 5.0, TOWER_Y + sy * 5.0, 10.0, 0.9, 16.0, 0.9, "wall_b3", false)
	B.box(g, "TowerShaftCap", 0.0, TOWER_Y, 37.5, 11.0, 0.5, 11.0, "trim_dark", false)
	# 钟室：四面敞开，四角立柱撑一块顶。黄昏时能透过它看见后面的天。
	B.box(g, "TowerChamber", 0.0, TOWER_Y, 38.0, 7.0, 0.6, 7.0, "metal", false)
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			B.box(g, "TowerPost%s%s" % ["W" if sx < 0.0 else "E",
				"S" if sy < 0.0 else "N"],
				sx * 3.2, TOWER_Y + sy * 3.2, 38.0, 0.5, 6.0, 0.5, "metal", false)
	# 钟面：四面各一块黄铜方盘。东西两面薄在 X 上，南北两面薄在 Z 上 ——
	# 不旋转，直接给两种尺寸，比算四元数省事也不会转错方向。
	for i in 4:
		var ang := TAU * float(i) / 4.0
		var fx := cos(ang) * 3.45
		var fy := sin(ang) * 3.45
		var thin_x := (i % 2 == 0)
		B.box(g, "TowerFaceRim%d" % i, fx, TOWER_Y + fy, 40.2,
			0.10 if thin_x else 2.7, 2.7, 2.7 if thin_x else 0.10, "trim_dark", false)
		B.box(g, "TowerFace%d" % i, fx, TOWER_Y + fy, 40.4,
			0.12 if thin_x else 2.4, 2.4, 2.4 if thin_x else 0.12, "brass", false)
	B.box(g, "TowerChamberRoof", 0.0, TOWER_Y, 44.0, 8.4, 0.5, 8.4, "metal", false)
	B.box(g, "TowerChamberEave", 0.0, TOWER_Y, 44.4, 9.4, 0.22, 9.4, "trim_dark",
		false)

	# 尖顶：CylinderMesh 把 top_radius 设 0 就是四棱锥，比自建三角面省事。
	var spire := MeshInstance3D.new()
	spire.name = "TowerSpire"
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = 5.4
	cm.height = 4.0
	cm.radial_segments = 4
	spire.mesh = cm
	spire.material_override = P.get_mat("roof_slate")
	spire.rotation.y = PI * 0.25
	spire.position = Vector3(0.0, 46.0, -TOWER_Y)
	g.add_child(spire)


# ================================================================ 边界

func _bounds(world: Node3D) -> void:
	var g := _group(world, "Bounds")

	# 南界：铁轨往南是煤场，一道 65 cm 高的石基 + 1.5 m 的铁栅栏。
	# 石基比 45 cm 的台阶上限高，玩家跨不过去 —— 但它看得见，所以不是隐形墙。
	B.box(g, "SouthBase", 0.0, Y_MIN + 0.6, 0.0, X_MAX - X_MIN, 0.65, 0.4, "wall_b2")
	B.fence(g, "SouthFence", X_MIN, Y_MIN + 0.6, X_MAX, Y_MIN + 0.6, 1.5, "metal", 2.6)

	# 煤堆：贴着南栅栏，高低不平。三堆就够，再多会变成一堵黑墙。
	for i in 5:
		var cx := -52.0 + float(i) * 26.0
		B.box(g, "CoalPile%d" % i, cx, Y_MIN + 3.2, 0.0, 9.0, 1.4 + float(i % 3) * 0.5,
			4.0, "coal")

	# 东西两侧：围墙。西侧到 X = −70，站房已经占了 −66…−46，墙只要补两头。
	B.box(g, "WestWall", X_MIN + 0.5, 15.0, 0.0, 0.6, 4.0, Y_MAX - Y_MIN, "wall_b2")
	B.box(g, "EastWall", X_MAX - 0.5, 15.0, 0.0, 0.6, 4.0, Y_MAX - Y_MIN, "wall_b2")

	# 北界：P1 的临时边界。用 1.1 m 的矮墙而不是 1.8 m 的栅栏 ——
	# 栅栏在 1.7 m 的眼高下会连成一片，正好把塔的下半截切掉，而「看得见塔」
	# 是这一版唯一的验收标准。矮墙跨不过去（台阶上限 0.45），视线完全通透。
	# P2 拆它的时候只要删这一行，墙外已经是铺好的钟塔广场。
	B.box(g, "NorthWall", 0.0, Y_MAX, 0.0, X_MAX - X_MIN, 1.1, 0.5, "wall_b2")


# ================================================================ 玩家

func _setup_player() -> void:
	var p := PLAYER_SCENE.instantiate()
	p.name = "Player"
	# 站台顶面 0.25，脚底再留 5 cm 余量，避免第一帧和站台面互穿
	p.position = Vector3(SPAWN_X, PLAT_H + 0.05, -SPAWN_Y)
	add_child(p)
