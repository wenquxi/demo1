extends RefCounted
## 灰堤的几何工厂。
##
## 只做三件事：把地图坐标换成 Godot 坐标、按「占地 + 层高」摆盒子、生成几种
## 复用率高的构件（坡屋顶、窗、转角条、雨落管）。城市长什么样不在这里，在 p1.gd。
##
## 坐标约定（来自 docs/城市规划-灰堤.md §4）：地图 X 向东、Y 向北，H 是地面高。
## Godot 里北 = −Z，所以 world = (X, H, −Y)。
##
## 立面方向用 axis 表示：一个指向「室外」的水平单位向量，只有 (±1,0,0) 和
## (0,0,±1) 四种取值。所有贴面构件都按它决定宽度沿哪根轴、厚度沿哪根轴，
## 这样同一套窗能挂到朝东、朝南的墙上，不需要为每个朝向写一份。

const P := preload("res://levels/gray_dike/dike_palette.gd")

const AX_E := Vector3(1, 0, 0)
const AX_W := Vector3(-1, 0, 0)
const AX_N := Vector3(0, 0, -1)  ## 地图 +Y
const AX_S := Vector3(0, 0, 1)  ## 地图 −Y


static func to_world(x: float, y: float, h: float = 0.0) -> Vector3:
	return Vector3(x, h, -y)


# ---------------------------------------------------------------- 基本体

## 实心盒子。尺寸按 (X 宽, 高, Y 深) 给，这样写建筑表时可以直接抄规划文档里的
## 「占地 X×Y」，不用心算转换。h 是底面高而不是中心高 —— 建筑几乎都是从地面
## 长出来的，按底面写能少一半加法。
##
## 为什么不用 CSGBox3D：这关的几何全是「加」，一次布尔运算都没有 —— CSG 唯一
## 的价值只剩 use_collision 这一行便捷，代价是改任何一个尺寸都要重新烘焙整棵
## CSG 树。四百个盒子时出图脚本每帧都在等它；换成 BoxMesh + BoxShape3D 之后
## 是即时的，也才敢往上堆窗套、腰线这些零件。
##
## 返回的根节点名字永远是 node_name（测试和调试按它找），子节点固定叫 Mesh / Shape。
static func box(parent: Node3D, node_name: String, x: float, y: float, h: float,
		sx: float, sy: float, sz: float, mat: String,
		collide: bool = true) -> Node3D:
	var bm := BoxMesh.new()
	bm.size = Vector3(sx, sy, sz)
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	mi.material_override = P.get_mat(mat)
	var pos := Vector3(x, h + sy * 0.5, -y)
	if not collide:
		mi.name = node_name
		mi.position = pos
		parent.add_child(mi)
		return mi
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = pos
	parent.add_child(body)
	mi.name = "Mesh"
	body.add_child(mi)
	var shape := BoxShape3D.new()
	shape.size = Vector3(sx, sy, sz)
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	cs.shape = shape
	body.add_child(cs)
	return body


## 铺装薄板。顶面正好落在 h 上，板厚 0.06，所以不会和底板打架。
## 默认不带碰撞：底板已经是一整块实心，铺装只是贴图。
static func slab(parent: Node3D, node_name: String, x: float, y: float, h: float,
		sx: float, sz: float, mat: String) -> Node3D:
	return box(parent, node_name, x, y, h - 0.06, sx, 0.06, sz, mat, false)


## 贴面盒：贴着立面挂的东西（窗套、门套、腰线、招牌）。
##
## `along` 是沿墙方向的尺寸，`depth` 是垂直墙面的尺寸，`out` 是它从墙面往
## 外凸出多少（负值就是凹进墙里）。四个朝向共用这一份换算。
static func face_box(parent: Node3D, node_name: String, x: float, y: float,
		h: float, axis: Vector3, along: float, sy: float, depth: float,
		out: float, mat: String, collide: bool = false) -> Node3D:
	var cx := x + axis.x * (out + depth * 0.5)
	var cy := y - axis.z * (out + depth * 0.5)
	var sx := depth if absf(axis.x) > 0.5 else along
	var sz := along if absf(axis.x) > 0.5 else depth
	return box(parent, node_name, cx, cy, h, sx, sy, sz, mat, collide)


# ---------------------------------------------------------------- 屋顶

## 双坡屋顶，屋脊沿地图 Y（南北向）。
##
## 为什么默认是南北向屋脊：灰堤的建筑立面几乎都朝东西 —— 广场在中间，房子
## 在两侧；大道也南北走，店铺在左右。屋脊必须平行于正面，否则从街上看到的是
## 一个三角形山墙贴着路面，读起来像仓库（公会那次的同一个教训）。
##
## eave 是檐口高度（墙顶），rise 是屋脊比檐口高多少。两片斜板按真实坡度转角，
## 不做「一堆小台阶去凑」—— 20 m 宽的屋顶上一眼就能看出锯齿。
##
## 三件套：两片瓦面 + 屋脊压条。屋脊那条比瓦暗，把两侧屋面在最高处分隔开；
## 没有它，两个斜面会在脊线上糊成一片，屋顶读起来像一块折过的纸板。
static func gable_roof(parent: Node3D, node_name: String, x: float, y: float,
		eave: float, sx: float, sz: float, rise: float,
		mat: String = "roof", ridge: bool = true) -> void:
	var run := sx * 0.5
	var slope := atan2(rise, run)
	var panel := sqrt(run * run + rise * rise)
	var thick := 0.22
	for side in [-1.0, 1.0]:
		# side = +1 是东坡（x 更大），−1 是西坡
		var bm := BoxMesh.new()
		bm.size = Vector3(panel + 0.35, thick, sz)
		var mi := MeshInstance3D.new()
		mi.name = "%s_%s" % [node_name, "E" if side > 0.0 else "W"]
		mi.mesh = bm
		mi.material_override = P.get_mat(mat)
		# 绕 Z 转 −slope 让局部 +X 指向下沉方向，法线朝上偏外
		mi.rotation.z = -slope * side
		mi.position = Vector3(x + side * run * 0.5, eave + rise * 0.5, -y)
		parent.add_child(mi)
	if ridge:
		box(parent, "%sRidge" % node_name, x, y, eave + rise - 0.14, 0.42, 0.20, sz,
			"trim_dark", false)


## 山墙三角，配南北向屋脊用 —— 两面山墙朝南北，三角形在 XY 平面。
##
## 用 PrismMesh 而不是自建三角面：它的三角形本来就在 XY 平面、沿 Z 拉伸，
## 正是这个朝向，连旋转都省了。它不需要碰撞（在檐口以上）。
static func gable_wall(parent: Node3D, node_name: String, x: float, y_end: float,
		eave: float, width: float, rise: float, mat: String = "wall_a") -> void:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var pm := PrismMesh.new()
	pm.size = Vector3(width, rise, 0.3)
	pm.left_to_right = 0.5
	mi.mesh = pm
	mi.material_override = P.get_mat(mat)
	mi.position = Vector3(x, eave + rise * 0.5, -y_end)
	parent.add_child(mi)


# ---------------------------------------------------------------- 立面零件

## 一扇窗。窗套 + 分格玻璃 + 窗台。
##
## 为什么不是「贴一片发光板」：贴片没有厚度，黄昏的斜光打不上去，读起来就是
## 一张便利贴 —— 这是第一版最丑的地方。窗套比墙面凸 12 cm，玻璃退回窗套里
## 4 cm，两者之间那 8 cm 的落差就是「这里有个洞」的全部信息；窗台再往外挑
## 10 cm，把窗套的投影截住，窗才不会浮在墙上。
##
## 玻璃必须分格。第一版是一整块 1.5×1.9 的自发光平面，在 tonemap 之后是一张
## 没有任何像素细节的白纸 —— 分格之后每一块的亮度都还在，窗棂的暗线才有
## 东西可压。格数按尺寸算，但最多 3×3：再多就是网格噪点了。
##
## x / y 给的是墙面上的位置（地图坐标），h 是窗台底面高。
static func window(parent: Node3D, node_name: String, x: float, y: float,
		h: float, axis: Vector3, w: float, hgt: float,
		mat: String = "window", sill: bool = true) -> void:
	# 窗套：一整片浅色板，玻璃贴在它前面，露出来的一圈就是框。
	# 拆成四根条要四个盒子，一整片只要一个 —— 视觉上没区别。
	#
	# 顺序必须是「窗套在后、玻璃在前」。反过来（玻璃塞进窗套里面）的话，
	# 窗套是一整块实心板，会把玻璃整个埋掉 —— 从正面看到的永远是那块浅色
	# 板子被夕阳烧成一片纯白。第一版之所以「窗户像便利贴」，机械原因就是
	# 玻璃的法线方向永远背对镜头，一个像素都没露出来过。
	face_box(parent, "%sFrame" % node_name, x, y, h - 0.10, axis,
		w + 0.24, hgt + 0.24, 0.12, 0.0, "trim")
	# 玻璃分格。格缝露出的是窗套的浅色，等于给窗棂上了一层亮漆 ——
	# 工业城的窗框就是刷白的，这一条不用额外做。
	var stp := Vector2(-axis.z, -axis.x)
	var cols := clampi(int(round(w / 0.80)), 2, 3)
	var rows := clampi(int(round(hgt / 0.85)), 2, 3)
	var gap := 0.085
	var gw := (w - gap * float(cols - 1)) / float(cols)
	var gh := (hgt - gap * float(rows - 1)) / float(rows)
	for r in rows:
		for c in cols:
			var ox := (float(c) - float(cols - 1) * 0.5) * (gw + gap)
			var oy := (float(r) - float(rows - 1) * 0.5) * (gh + gap)
			face_box(parent, "%sPane%d%d" % [node_name, r, c],
				x + stp.x * ox, y + stp.y * ox,
				h + hgt * 0.5 + oy - gh * 0.5, axis, gw, gh, 0.03, 0.105, mat)
	if sill:
		face_box(parent, "%sSill" % node_name, x, y, h - 0.20, axis,
			w + 0.40, 0.09, 0.24, 0.0, "trim_dark", true)


## 一扇门。门套 + 内凹的门板 + 门前一级石阶。
##
## 门板要比墙暗：暮色里门口是一个黑洞，这才符合「屋里没开灯」。门套用浅色
## 是为了在暗色门板外留一圈边，不然整面墙读下来只剩一个缺口。
static func doorway(parent: Node3D, node_name: String, x: float, y: float,
		axis: Vector3, w: float, hgt: float, step_depth: float = 0.5,
		mat: String = "timber") -> void:
	face_box(parent, "%sFrame" % node_name, x, y, 0.0, axis,
		w + 0.30, hgt + 0.20, 0.12, 0.0, "trim")
	face_box(parent, "%sLeaf" % node_name, x, y, 0.0, axis,
		w, hgt, 0.03, 0.105, mat)
	# 门楣上方一块小挑檐。有它，门才「嵌在墙里」而不是「印在墙上」。
	face_box(parent, "%sHood" % node_name, x, y, hgt + 0.14, axis,
		w + 0.46, 0.12, 0.26, 0.0, "trim_dark")
	# 石阶：比门宽一圈，往路面方向铺出去 step_depth
	var sx := w + 0.7 if absf(axis.x) > 0.5 else step_depth + 0.5
	var sz := step_depth + 0.5 if absf(axis.x) > 0.5 else w + 0.7
	box(parent, "%sStep" % node_name, x + axis.x * step_depth * 0.5,
		y - axis.z * step_depth * 0.5, 0.0, sx, 0.14, sz, "trim_dark", false)


## 转角竖条：贴在建筑角上、通高的一道明度分界。
##
## 没有它，两堵不同朝向的墙在角上直接相交，受光面亮、背光面暗，但中间是一条
## 硬切的直角 —— 远看像两个盒子拼在一起。加一条 45 cm 宽的凸出竖条之后，
## 转角有了「厚度」，也顺手把两面的纹理投影接缝藏掉。
##
## side = ±1 决定沿墙往哪边偏（角点的另一侧属于另一个立面，那边会自己再贴一条）。
static func corner_band(parent: Node3D, node_name: String, x: float, y: float,
		height: float, axis: Vector3, side: float, w: float = 0.45,
		mat: String = "trim") -> void:
	# 沿墙方向在世界里是 axis 转 90°，换成地图坐标要再翻一次 Y
	var map_tx := -axis.z * side
	var map_ty := -axis.x * side
	face_box(parent, node_name, x + map_tx * w * 0.5, y + map_ty * w * 0.5,
		0.0, axis, w, height, 0.09, 0.0, mat)


## 楼层腰线：一道凸出 8 cm 的横向石带，把立面按层分开。
##
## 高窗的排屋如果只有一片墙 + 几个洞，三层和两层看起来一模一样。腰线是
## 最便宜的分层手段 —— 一条 20 cm 高的亮线，比再画十个窗有效。
static func string_course(parent: Node3D, node_name: String, x: float, y: float,
		h: float, axis: Vector3, along: float, mat: String = "trim") -> void:
	face_box(parent, node_name, x, y, h, axis, along, 0.20, 0.14, 0.0, mat)


## 雨落管：一根从檐口伸到墙脚的细管 + 两个卡箍。
##
## 工业城最不缺的就是这个。它的价值在剪影 —— 一堵平整的墙前竖着一根细线，
## 尺度感立刻有了；而且它会挡掉一部分纹理平铺的规律性。
static func downpipe(parent: Node3D, node_name: String, x: float, y: float,
		top: float, axis: Vector3, mat: String = "metal") -> void:
	face_box(parent, "%sPipe" % node_name, x, y, 0.05, axis,
		0.11, top - 0.05, 0.11, 0.05, mat)
	for t in [0.30, 0.72]:
		face_box(parent, "%sClamp%d" % [node_name, int(t * 100.0)], x, y,
			top * t, axis, 0.20, 0.09, 0.18, 0.03, mat)
	# 檐沟落水口
	face_box(parent, "%sShoe" % node_name, x, y, top - 0.30, axis,
		0.26, 0.30, 0.26, 0.02, mat)


## 店招遮阳篷：一块向外倾斜的板 + 两根斜撑。
##
## 沿墙方向分成 4 条是因为条纹 —— 单一材质贴不出斜纹，而实心一色的篷
## 在暮色里就是一块黑三角。四色交替之后，它才像布。
static func awning(parent: Node3D, node_name: String, x: float, y: float,
		h: float, axis: Vector3, along: float, out: float = 1.3) -> void:
	var stripes := 4
	var sw := along / float(stripes)
	# 沿墙轴切分：axis 是 X 向时宽度沿 Z，反之亦然。用步进量统一表达。
	var step := Vector3(0, 0, sw) if absf(axis.x) > 0.5 else Vector3(sw, 0, 0)
	for i in stripes:
		var px := x + step.x * float(i)
		var py := y - step.z * float(i)
		var mat := "awning_a" if (i % 2) == 0 else "awning_b"
		# 一块斜板：绕沿墙轴转 22°，外沿比内沿低
		var bm := BoxMesh.new()
		bm.size = Vector3(out + 0.3, 0.06, sw * 0.96) if absf(axis.x) > 0.5 \
			else Vector3(sw * 0.96, 0.06, out + 0.3)
		var mi := MeshInstance3D.new()
		mi.name = "%sCloth%d" % [node_name, i]
		mi.mesh = bm
		mi.material_override = P.get_mat(mat)
		if absf(axis.x) > 0.5:
			mi.rotation.z = -axis.x * 0.38
		else:
			mi.rotation.x = axis.z * 0.38
		mi.position = Vector3(px + axis.x * out * 0.5, h, -py + axis.z * out * 0.5)
		parent.add_child(mi)
	# 两根斜撑，从篷外沿斜着抵回墙。顶端必须落在篷的外沿下沿 ——
	# 第一版把中心放在 h - 0.42，杆的下端悬在篷口下面半米，看着像一根
	# 插在墙上的长针。
	if absf(axis.x) > 0.5:
		for s in [-1.0, 1.0]:
			var bar := MeshInstance3D.new()
			bar.name = "%sBrace%d" % [node_name, int(s)]
			var bm2 := BoxMesh.new()
			bm2.size = Vector3(1.55, 0.05, 0.05)
			bar.mesh = bm2
			bar.material_override = P.get_mat("metal")
			bar.rotation.z = -axis.x * 0.72
			bar.position = Vector3(x + axis.x * out * 0.58, h - 0.72,
				-(y + s * along * 0.42))
			parent.add_child(bar)


# ---------------------------------------------------------------- 围护

## 一棵树：树干 + 一丛压扁的低分段球。
##
## 试过两版：方盒子（20 m 外是一排悬空的箱子）和锥体（一路读成圣诞树 ——
## 三层规整的尖锥，对称、等距、每棵一样）。灰堤的街树是阔叶，不是针叶。
##
## 四颗半径不同的球错开高度和水平位置，就够读出「一丛叶子」：
## 低分段球（7×4）本来就是多面体，棱角正好配这套低面数风格，
## 而且不会像高分段球那样在暮色里糊成一坨。
##
## 整套偏移都用坐标哈希，所以同一个位置永远是同一棵树 —— 截图能比对。
static func tree(parent: Node3D, node_name: String, x: float, y: float,
		s: float = 1.0) -> void:
	var trunk_h := 2.8 * s
	box(parent, "%sTrunk" % node_name, x, y, 0.0, 0.30 * s, trunk_h, 0.30 * s,
		"timber", true)
	# [水平 x, 高度, 水平 z, 半径]，单位是 s
	var clusters := [
		Vector4(0.00, 3.95, 0.00, 1.62),
		Vector4(-0.64, 3.20, 0.44, 1.18),
		Vector4(0.68, 4.55, -0.36, 1.02),
		Vector4(0.14, 2.72, 0.66, 0.92),
	]
	# 每棵树绕 Y 转一个自己的角度，四颗球的错位方向就不会全街一致
	var yaw := float(absi(int(x * 37.0 + y * 91.0)) % 360) * PI / 180.0
	var cs := cos(yaw)
	var sn := sin(yaw)
	for i in clusters.size():
		var c: Vector4 = clusters[i]
		var cm := SphereMesh.new()
		cm.radius = c.w * s
		cm.height = c.w * 1.52 * s
		cm.radial_segments = 7
		cm.rings = 4
		var mi := MeshInstance3D.new()
		mi.name = "%sCanopy%d" % [node_name, i]
		mi.mesh = cm
		mi.material_override = P.get_mat("foliage")
		# 轻微压扁 + 随机吸一点：完全的球看着像气球
		mi.scale = Vector3(1.0, 0.86 + float(i % 2) * 0.1, 1.0)
		mi.position = Vector3(
			x + (c.x * cs - c.z * sn) * s,
			c.y * s + trunk_h * 0.20,
			-y + (c.x * sn + c.z * cs) * s)
		mi.rotation.y = yaw
		parent.add_child(mi)


## 沿直线摆一列栅栏：立柱 + 两道横杆。
##
## 用来做城镇边界。规划里南侧是铁轨与煤堆，需要一道「看得见走不过去」的软边界 ——
## 栅栏满足这个，而且比隐形墙诚实：玩家知道自己为什么过不去。
static func fence(parent: Node3D, node_name: String, x0: float, y0: float,
		x1: float, y1: float, height: float = 1.6,
		mat: String = "metal", step: float = 2.4) -> void:
	var dx := x1 - x0
	var dy := y1 - y0
	var span := sqrt(dx * dx + dy * dy)
	if span < 0.01:
		return
	var count := maxi(2, int(round(span / step)) + 1)
	for i in count + 1:
		var t := float(i) / float(count)
		box(parent, "%s_post%d" % [node_name, i], x0 + dx * t, y0 + dy * t, 0.0,
			0.11, height, 0.11, mat, false)
	for level in [0.34, 0.82]:
		var bm := BoxMesh.new()
		bm.size = Vector3(span, 0.07, 0.05)
		var mi := MeshInstance3D.new()
		mi.name = "%s_bar%d" % [node_name, int(level * 100.0)]
		mi.mesh = bm
		mi.material_override = P.get_mat(mat)
		mi.rotation.y = atan2(dy, dx)
		mi.position = Vector3((x0 + x1) * 0.5, height * level, -(y0 + y1) * 0.5)
		parent.add_child(mi)


## 一道通长的墙。两端各给一次坐标，比算中心 + 长度好读。
static func wall(parent: Node3D, node_name: String, x0: float, y0: float,
		x1: float, y1: float, bottom: float, height: float, thick: float,
		mat: String, collide: bool = true) -> void:
	var dx := x1 - x0
	var dy := y1 - y0
	var span := sqrt(dx * dx + dy * dy)
	if span < 0.01:
		return
	var bm := BoxMesh.new()
	bm.size = Vector3(span, height, thick)
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	mi.material_override = P.get_mat(mat)
	mi.rotation.y = atan2(dy, dx)
	var pos := Vector3((x0 + x1) * 0.5, bottom + height * 0.5, -(y0 + y1) * 0.5)
	if not collide:
		mi.name = node_name
		mi.position = pos
		parent.add_child(mi)
		return
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = pos
	body.rotation.y = mi.rotation.y
	parent.add_child(body)
	mi.name = "Mesh"
	mi.rotation.y = 0.0
	body.add_child(mi)
	var shape := BoxShape3D.new()
	shape.size = Vector3(span, height, thick)
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	cs.shape = shape
	body.add_child(cs)


## 煤气灯柱。柱子 + 灯头 + 一盏点光源。
##
## 灯头用 unshaded 自发光，不再被夕阳照 —— 它已经是光源，再吃一层橙色会变成
## 一块橙白斑。范围压到 12 m，只够照亮脚下那圈砖，多一盏就变成白天。
static func lamp_post(parent: Node3D, node_name: String, x: float, y: float,
		height: float = 4.2) -> void:
	box(parent, "%s_base" % node_name, x, y, 0.0, 0.46, 0.34, 0.46, "metal", true)
	box(parent, "%s_pole" % node_name, x, y, 0.34, 0.14, height - 0.34, 0.14,
		"metal", false)
	# 灯罩：四片斜板围一个方锥，比一个方块更像提灯
	for s in 4:
		var ang := TAU * float(s) / 4.0
		var bm := BoxMesh.new()
		bm.size = Vector3(0.34, 0.30, 0.04)
		var mi := MeshInstance3D.new()
		mi.name = "%s_shade%d" % [node_name, s]
		mi.mesh = bm
		mi.material_override = P.get_mat("metal")
		mi.rotation.y = ang
		mi.position = Vector3(x + cos(ang) * 0.19, height - 0.02,
			-y + sin(ang) * 0.19)
		parent.add_child(mi)
	box(parent, "%s_head" % node_name, x, y, height - 0.16, 0.26, 0.30, 0.26,
		"lamp", false)
	box(parent, "%s_cap" % node_name, x, y, height + 0.12, 0.38, 0.08, 0.38,
		"metal", false)
	var l := OmniLight3D.new()
	l.name = "%s_light" % node_name
	l.position = Vector3(x, height - 0.1, -y)
	l.light_color = Color("#ffc98a")
	l.light_energy = 1.6
	l.omni_range = 12.0
	l.shadow_enabled = false
	parent.add_child(l)


## 檐口：墙顶下方一条凸出 15 cm 的深色带。
##
## 没有它，一面墙就是一个纯色块，屋顶像是直接扣在盒子上的。有了它，屋檐有了
## 厚度，阳光会在墙面投下一条 15 cm 的阴影线 —— 这是「这是栋房子」最便宜的信号。
static func cornice(parent: Node3D, node_name: String, x: float, y: float,
		eave: float, sx: float, sz: float,
		mat: String = "trim_dark") -> void:
	box(parent, node_name, x, y, eave - 0.34, sx + 0.34, 0.34, sz + 0.34, mat, false)


## 墙脚：底部 55 cm 的石带，凸出 6 cm。
##
## 建筑「像悬空的盒子」这个感觉，八成来自墙和地面之间没有过渡。一条石脚
## 把墙体压进地里，同时挡住墙根那条最容易看出来是平贴图的接缝。
static func plinth(parent: Node3D, node_name: String, x: float, y: float,
		sx: float, sz: float, mat: String = "brick_dark") -> void:
	box(parent, node_name, x, y, 0.0, sx + 0.12, 0.55, sz + 0.12, mat, false)
