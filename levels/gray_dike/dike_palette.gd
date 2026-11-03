extends RefCounted
## 灰堤 · 材质表。
##
## 为什么单独一层：建筑配方里每面墙、每根栏杆都要材质。直接 new
## StandardMaterial3D 会造出几百个实例 —— 同色但不同实例，渲染器没法合批，
## 一个上千盒子的关卡会变成上千次绘制。这里按色号缓存，全场景只有二十来个材质。
##
## 定色的依据是「暮色 + 工业城」：饱和度一律压低，只有灯头和窗户给自发光。
## 白天色一旦放进来，暮色演出时整条街会显得又脏又亮。
##
## tex / uv 的意义：tex 是程序化纹理的键（见 dike_texture.gd），uv 是「一张贴图
## 代表多少米」。用 triplanar 按世界坐标投影，所以 20 m 的墙和 4 m 的窗台贴上去
## 砖块一样大 —— 换成普通 UV 的话，每改一次建筑尺寸就得重算一次纹理密度。

const TEX := preload("res://levels/gray_dike/dike_texture.gd")


## color 用 HTML 写法；rough 是粗糙度；emit 给了自发光强度（0 = 不发光）；
## tex 是纹理键；uv 是贴图物理边长（米）；nrm 是法线强度。
const _SPEC := {
	# ---- 地面与铺装
	"ground": {"color": "#4a453b", "rough": 0.96, "tex": "dirt", "uv": 4.0},
	"platform": {"color": "#6b6356", "rough": 0.88, "tex": "pave", "uv": 2.2},
	"stone": {"color": "#635a4c", "rough": 0.84, "tex": "pave", "uv": 2.4},
	"road": {"color": "#5a5246", "rough": 0.86, "tex": "pave", "uv": 2.6},
	"curb": {"color": "#5d5649", "rough": 0.90, "tex": "pave", "uv": 1.6},
	"coal": {"color": "#26231f", "rough": 1.0, "tex": "dirt", "uv": 1.4},
	# 路面补丁：修过的地方比周围深或浅一档。两个色号就够了 ——
	# 再多会把地面变成补丁毯。
	"patch_dark": {"color": "#4e4739", "rough": 0.92, "tex": "pave", "uv": 1.7},
	"patch_light": {"color": "#7c7364", "rough": 0.90, "tex": "pave", "uv": 1.5},

	# ---- 墙体。三个色族：A 暖赭、B 冷灰、C 砖红。每族再给两个深浅，
	# 一堵街上相邻的两栋不会是同一个颜色 —— 这是「一条街」和「一堵墙」的区别。
	"wall_a": {"color": "#b5a189", "rough": 0.90, "tex": "plaster", "uv": 2.0},
	"wall_a2": {"color": "#a08a72", "rough": 0.90, "tex": "plaster", "uv": 2.0},
	"wall_a3": {"color": "#c0ab8c", "rough": 0.90, "tex": "plaster", "uv": 1.7},
	"wall_b": {"color": "#8e8475", "rough": 0.90, "tex": "plaster", "uv": 2.0},
	"wall_b2": {"color": "#7a7264", "rough": 0.90, "tex": "plaster", "uv": 2.0},
	"wall_b3": {"color": "#9b8f7a", "rough": 0.90, "tex": "plaster", "uv": 2.4},
	"plaster": {"color": "#c4b9a3", "rough": 0.94, "tex": "plaster", "uv": 2.0},
	"brick": {"color": "#9c7259", "rough": 0.92, "tex": "brick", "uv": 1.0},
	"brick_dark": {"color": "#6a5749", "rough": 0.92, "tex": "brick", "uv": 1.0},

	# ---- 木石构件
	"timber": {"color": "#6b5340", "rough": 0.88, "tex": "plaster", "uv": 0.9},
	# 窗套比墙亮一档就够了。第一版给到 #d3c7ad，在 16° 的斜阳下直接冲成
	# 纯白 —— 一整面墙只剩一块白斑，窗框反而把窗吃掉了。
	"trim": {"color": "#a99d86", "rough": 0.84},
	"trim_dark": {"color": "#4f4338", "rough": 0.86},  # 深色木压条
	"foliage": {"color": "#313d27", "rough": 0.94, "tex": "dirt", "uv": 1.5},

	# ---- 布篷。两色交替拼出条纹 —— 单色篷在暮色里就是一块黑三角。
	"awning_a": {"color": "#8d4a3c", "rough": 0.94, "tex": "plaster", "uv": 1.0},
	"awning_b": {"color": "#cbbfa5", "rough": 0.94, "tex": "plaster", "uv": 1.0},

	# ---- 金属
	"roof": {"color": "#5c534a", "rough": 0.72, "tex": "tile", "uv": 2.0},
	"roof_tin": {"color": "#615349", "rough": 0.60, "tex": "metal", "uv": 2.0},
	"roof_slate": {"color": "#4d5257", "rough": 0.66, "tex": "tile", "uv": 1.7},
	"metal": {"color": "#4a473f", "rough": 0.55, "tex": "metal", "uv": 1.6},
	"rail": {"color": "#8a8478", "rough": 0.40},
	"brass": {"color": "#9d7f42", "rough": 0.58},

	# ---- 发光的四处。emit_color 和 albedo 分开写：窗户白天是暗玻璃，
	# 暮色时是暖黄的室内光；两者共用一个色号的话，窗框会跟着一起发亮。
	#
	# emit 从 0.72 压到 0.30：0.72 在 FILMIC + glow 之下会把整块玻璃推成
	# 纯白 —— 一片没有一个像素有细节的白纸，就是第一版「窗户像便利贴」的
	# 真正原因，不是形状。0.30 刚好让玻璃成为画面里最亮的一档，但还留着
	# 层次，窗格的黑线才看得见。
	"window": {"color": "#4a3b23", "rough": 0.30, "emit": 0.42,
		"emit_color": "#ff9d4a"},
	"window_dim": {"color": "#2e2a20", "rough": 0.34, "emit": 0.16,
		"emit_color": "#d98f52"},
	"glass": {"color": "#2b3038", "rough": 0.12, "metallic": 0.4},
	"lamp": {"color": "#ffd79a", "rough": 0.30, "emit": 2.2},
}

static var _cache: Dictionary = {}


## 取材质。同一个 key 永远返回同一个实例。
static func get_mat(key: String) -> StandardMaterial3D:
	if _cache.has(key):
		return _cache[key]
	var spec: Dictionary = _SPEC.get(key, _SPEC["ground"])
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(String(spec["color"]))
	m.roughness = float(spec.get("rough", 0.9))
	m.metallic = float(spec.get("metallic", 0.0))

	# 纹理按世界坐标三向投影。sharpness 调到 8：默认值 1 会让转角的投影互相
	# 渗透 30 cm，墙角和地面交界处糊成一团；8 大约是一个砖宽的过渡。
	if spec.has("tex"):
		var t := TEX.get_tex(String(spec["tex"]))
		var uv := float(spec.get("uv", 2.0))
		m.uv1_triplanar = true
		m.uv1_scale = Vector3.ONE / uv
		m.uv1_triplanar_sharpness = 8.0
		m.albedo_texture = t["albedo"]
		m.normal_enabled = true
		m.normal_texture = t["normal"]
		m.normal_scale = 1.0 if not spec.has("nrm") else float(spec["nrm"])

	var emit := float(spec.get("emit", 0.0))
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = Color(String(spec.get("emit_color", spec["color"])))
		m.emission_energy_multiplier = emit
		# 灯头和亮着的窗户不该再被夕阳染一层橙 —— 它们本身就是光源
		if emit >= 2.0:
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_cache[key] = m
	return m


## 墙色轮值表。建筑配方里按索引取，保证相邻两栋不同色 —— 手写的话，
## 加一栋楼就要回头数一遍已经用了哪个。
const WALL_ROTATION := ["wall_a", "wall_b3", "wall_a2", "wall_b", "wall_a3",
	"wall_b2"]
const ROOF_ROTATION := ["roof", "roof_slate", "roof_tin", "roof", "roof_slate"]


static func wall_color(i: int) -> String:
	return WALL_ROTATION[i % WALL_ROTATION.size()]


static func roof_color(i: int) -> String:
	return ROOF_ROTATION[i % ROOF_ROTATION.size()]
