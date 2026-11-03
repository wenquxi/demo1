extends RefCounted
## 灰堤 · 程序化纹理。
##
## 为什么不用贴图文件：工程约定「全程序化、不引外部素材」。而且这些纹理要按
## triplanar 世界尺度平铺 —— 换一张图的物理尺寸就得重算所有 UV 缩放，写死
## 「一张图代表几米」比维护一堆 .import 文件省事。
##
## 为什么是 256：2 m 见方一张图 = 一个像素 8 mm。1.7 m 眼高、3 m 外看完全够，
## 而生成成本是 512 的四分之一。远景靠 mipmap + 法线撑，不靠分辨率。
##
## 每张图出两样：albedo（灰度）和 normal。
## 法线由高度图求导得到 —— 砖缝、瓦楞、石缝会真的产生凹凸。这是「盒子变房子」
## 性价比最高的一步：只改 albedo 颜色，再怎么调都是一块色板。
##
## 明度压在 0.55…1.0，中值约 0.80。纹理是乘在 albedo_color 上的，中值不到 1
## 会让所有墙面整体暗一档 —— 暮色正好要这个，所以不去校正回 1.0。

const SIZE := 256

## key -> {"albedo": ImageTexture, "normal": ImageTexture}
static var _cache: Dictionary = {}


static func get_tex(key: String) -> Dictionary:
	if _cache.has(key):
		return _cache[key]
	var pat: Dictionary
	match key:
		"brick":
			pat = _brick()
		"tile":
			pat = _tile()
		"pave":
			pat = _pave()
		"metal":
			pat = _metal()
		"dirt":
			pat = _dirt()
		_:
			pat = _plaster()
	var r := _bake(pat["h"], pat["t"], float(pat.get("nrm", 2.0)))
	_cache[key] = r
	return r


# ---------------------------------------------------------------- 公共零件

## 整数哈希 → 0…1。不用 RandomNumberGenerator：这里要的是「同坐标永远同值」，
## 每次重建关卡都得画出同一堵墙，否则截图没法比对。
static func _hash(x: int, y: int, s: int) -> float:
	var n := (x & 1023) * 374761393 + (y & 1023) * 668265263 + s * 1442695041
	n = n ^ (n >> 13)
	n = (n * 1274126177) & 0x7FFFFFFF
	n = n ^ (n >> 16)
	return float(n & 0xFFFFF) / 1048575.0


## 周期性的低频噪声，直接写进 hgt/tint，省掉一层函数返回。
## cells **必须整除 SIZE**：步长是整数除法，除不尽的话最后一行/列会算出
## 超出网格的格点索引（cells=12 时 y=255 落到第 144 格，而表只有 144 项），
## 直接报 PackedFloat32Array 越界。4 / 8 / 16 / 32 都是安全的。
static func _lowfreq(hgt: PackedFloat32Array, tint: PackedFloat32Array,
		cells: int, amp: float, weight_tint: float, s: int) -> void:
	var step := SIZE / cells
	# 先算一张 cells×cells 的格点表，再双线性放大 —— 比每像素重算哈希快得多
	var g := PackedFloat32Array()
	g.resize(cells * cells)
	for gy in cells:
		for gx in cells:
			g[gy * cells + gx] = _hash(gx, gy, s)
	for y in SIZE:
		var fy := float(y) / float(step)
		var y0 := int(fy)
		var ty := fy - y0
		ty = ty * ty * (3.0 - 2.0 * ty)
		var y1 := (y0 + 1) % cells
		var r0 := y0 * cells
		var r1 := y1 * cells
		for x in SIZE:
			var fx := float(x) / float(step)
			var x0 := int(fx)
			var tx := fx - x0
			tx = tx * tx * (3.0 - 2.0 * tx)
			var x1 := (x0 + 1) % cells
			var a := g[r0 + x0]
			var b := g[r0 + x1]
			var c := g[r1 + x0]
			var d := g[r1 + x1]
			var v := lerpf(lerpf(a, b, tx), lerpf(c, d, tx), ty)
			var i := y * SIZE + x
			hgt[i] += (v - 0.5) * amp
			tint[i] += (v - 0.5) * weight_tint


## 细颗粒。每像素一次哈希，看起来像灰泥里的砂粒。
static func _grain(hgt: PackedFloat32Array, tint: PackedFloat32Array,
		amp: float, weight_tint: float, s: int) -> void:
	for y in SIZE:
		for x in SIZE:
			var v := _hash(x, y, s) - 0.5
			var i := y * SIZE + x
			hgt[i] += v * amp
			tint[i] += v * weight_tint


static func _blank() -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(SIZE * SIZE)
	return a


# ---------------------------------------------------------------- 图案

## 灰泥墙。所有墙共用这一张，靠 albedo_color 上色 —— 一张图服务十来个色号，
## 灰堤的墙才不是「一个颜色刷到底」。
static func _plaster() -> Dictionary:
	var h := _blank()
	var t := _blank()
	# 大块斑驳：年久失修的墙面色差来自这里，不是来自砂粒。权重给得很重 ——
	# 一张均匀的灰泥贴图在 3 m 外和纯色没有区别，那还不如不贴。
	_lowfreq(h, t, 4, 0.12, 0.62, 11)
	_lowfreq(h, t, 8, 0.07, 0.36, 23)
	_grain(h, t, 0.06, 0.22, 37)
	# 竖向雨痕：从上往下会有一条条比周围暗的水渍。
	# 只在 tint 上做，不动高度 —— 水渍不改变表面形状，只改变脏的程度。
	for x in SIZE:
		var streak := _hash(x, 0, 51) * 0.7 + _hash(x, 1, 57) * 0.3
		if streak < 0.55:
			continue
		var dark := (streak - 0.55) * 0.30
		for y in SIZE:
			# 起点随机、向下逐渐变淡，模拟雨水越流越薄
			var top := int(_hash(x, 2, 61) * float(SIZE))
			var run := (y - top + SIZE) % SIZE
			var fade := clampf(1.0 - float(run) / float(SIZE), 0.0, 1.0)
			var i := y * SIZE + x
			t[i] -= dark * fade * 0.9
			h[i] -= dark * fade * 0.08
	return {"h": h, "t": t, "nrm": 3.0}


## 砖墙。一张图 1 m 见方：16 行 × 6.25 cm（标准砖 6.5 cm 加灰缝），
## 4 块 × 25 cm。错缝半块。
##
## 灰浆是凹进去但发白的 —— 所以高度给低、明度给高。只压高度的话，
## 砖墙在暮色下会读成一块有纹理的深色板，看不出是砖。
static func _brick() -> Dictionary:
	var h := _blank()
	var t := _blank()
	var row_h := 16
	var brick_w := 64
	for y in SIZE:
		var row := y / row_h
		var yy := y % row_h
		var off := (brick_w / 2) if (row % 2) == 1 else 0
		for x in SIZE:
			var shifted := (x + off) % SIZE
			var xx := shifted % brick_w
			var col := shifted / brick_w
			var i := y * SIZE + x
			var bid := _hash(col, row, 7)
			if yy < 2 or xx < 2:
				h[i] = 0.18 + _hash(x, y, 9) * 0.06
				t[i] = 0.92 + _hash(x, y, 13) * 0.08
			else:
				# 砖面中间略鼓：边缘比中心低 4 mm，斜光下就是一条软边
				var edge := minf(float(xx - 2), float(brick_w - 2 - xx))
				var edge_y := minf(float(yy - 2), float(row_h - 2 - yy))
				var bulge := clampf(minf(edge, edge_y) / 4.0, 0.0, 1.0) * 0.10
				h[i] = 0.46 + bid * 0.18 + bulge + _hash(x, y, 17) * 0.05
				t[i] = 0.34 + bid * 0.34 + _hash(x, y, 19) * 0.08
	return {"h": h, "t": t, "nrm": 3.2}


## 石板瓦屋顶。一张图 2 m：8 皮 × 25 cm，每皮 8 片。
## 搭接边的暗线是屋顶最重要的读法 —— 没有它，斜面就是两块铁板。
static func _tile() -> Dictionary:
	var h := _blank()
	var t := _blank()
	var row_h := 32
	var tile_w := 32
	for y in SIZE:
		var row := y / row_h
		var yy := y % row_h
		for x in SIZE:
			var col := x / tile_w
			var xx := x % tile_w
			var i := y * SIZE + x
			var tid := _hash(col, row, 29)
			var seam := 0.0
			if xx < 2:
				seam = 1.0
			# 下缘：这一片压住下一片，接缝处比自己低
			var lap := 0.0
			if yy > row_h - 5:
				lap = float(yy - (row_h - 5)) / 5.0
			h[i] = 0.62 + tid * 0.16 - seam * 0.30 - lap * 0.26 \
				+ _hash(x, y, 31) * 0.04
			t[i] = 0.40 + tid * 0.30 - lap * 0.16 + _hash(x, y, 41) * 0.06
	return {"h": h, "t": t, "nrm": 3.6}


## 石板铺装。一张图 2.4 m：4×4 块，每块 60 cm，**错缝半块**。
##
## 错缝不是细节，是必须：等分网格平铺之后，所有的缝会连成一条贯穿全场的
## 直线 —— 整片广场读成一张无限延伸的方格纸，这是「廉价」最直接的来源。
## 错开半块之后，任何一条缝最多只延续 4 块石头就断掉。
##
## 缝必须比石头**暗**。第一版把缝做成亮灰浆，结果广场是一张白色瓷砖 ——
## 砖砌体的灰浆是外露的白灰，所以亮；铺地石的缝里是积土和阴影，永远比
## 石面暗。两种「缝」用同一套写法，广场就废了。
static func _pave() -> Dictionary:
	var h := _blank()
	var t := _blank()
	var cell := 64
	for y in SIZE:
		var row := y / cell
		var yy := y % cell
		var xoff := (cell / 2) if (row % 2) == 1 else 0
		for x in SIZE:
			var sx := (x + xoff) % SIZE
			var col := sx / cell
			var xx := sx % cell
			var i := y * SIZE + x
			var sid := _hash(col, row, 43)
			var e := mini(mini(xx, cell - 1 - xx), mini(yy, cell - 1 - yy))
			if e < 2:
				# 缝：又深又脏。这里不给噪声，让缝是一条干净的暗线，
				# 不然远处会噪成一片沙。
				h[i] = 0.06
				t[i] = 0.16
			else:
				# 石面从缝边往里微微隆起，像磨圆的边 —— 斜光下是一条软过渡，
				# 比硬切的方块有体积。
				var crown := clampf(float(e - 2) / 9.0, 0.0, 1.0) * 0.12
				h[i] = 0.44 + sid * 0.24 + crown + _hash(x, y, 59) * 0.06
				t[i] = 0.30 + sid * 0.38 + _hash(x, y, 67) * 0.10
	return {"h": h, "t": t, "nrm": 2.6}


## 波纹铁皮。一张图 2 m，波长 12.5 cm。
## 站台雨棚、天桥、仓库顶全是这个 —— 工业城最便宜的立面语言。
static func _metal() -> Dictionary:
	var h := _blank()
	var t := _blank()
	var period := 16.0
	for y in SIZE:
		for x in SIZE:
			var i := y * SIZE + x
			var ph := float(x % int(period)) / period
			var wave := sin(ph * TAU)
			h[i] = 0.5 + wave * 0.30
			t[i] = 0.45 + wave * 0.22 + _hash(x, y, 71) * 0.06
	return {"h": h, "t": t, "nrm": 2.6}


## 夯土掺炉渣。地面、煤场、场外泥地。
static func _dirt() -> Dictionary:
	var h := _blank()
	var t := _blank()
	_lowfreq(h, t, 8, 0.16, 0.40, 73)
	_lowfreq(h, t, 32, 0.06, 0.22, 79)
	_grain(h, t, 0.10, 0.30, 83)
	return {"h": h, "t": t, "nrm": 1.8}


# ---------------------------------------------------------------- 烘焙

## 高度图 + 色调图 → albedo + normal 两张图。
##
## 法线取 (-∂h/∂u, -∂h/∂v, 1)：Godot 的切线空间沿用 OpenGL 约定，+G 指向 UV
## 的 +v，而图像 y 增大正是 +v。两个分量都取负，凹缝才是凹的；签名反了的话
## 砖墙会整片鼓成气垫，比没有法线更难看。
static func _bake(hgt: PackedFloat32Array, tint: PackedFloat32Array,
		strength: float) -> Dictionary:
	var n := SIZE * SIZE
	var alb := PackedByteArray()
	alb.resize(n * 4)
	var nrm := PackedByteArray()
	nrm.resize(n * 4)
	for y in SIZE:
		var r0 := ((y - 1 + SIZE) % SIZE) * SIZE
		var r1 := y * SIZE
		var r2 := ((y + 1) % SIZE) * SIZE
		var o := r1 * 4
		for x in SIZE:
			var xm := (x - 1 + SIZE) % SIZE
			var xp := (x + 1) % SIZE
			var i := r1 + x
			var v := clampf(0.56 + (hgt[i] * 0.64 + tint[i] * 0.36) * 0.46, 0.0, 1.0)
			var c := int(v * 255.0)
			alb[o] = c
			alb[o + 1] = c
			alb[o + 2] = c
			alb[o + 3] = 255
			var nx := -(hgt[r1 + xp] - hgt[r1 + xm]) * strength
			var ny := -(hgt[r2 + x] - hgt[r0 + x]) * strength
			var l := sqrt(nx * nx + ny * ny + 1.0)
			nrm[o] = int((nx / l * 0.5 + 0.5) * 255.0)
			nrm[o + 1] = int((ny / l * 0.5 + 0.5) * 255.0)
			nrm[o + 2] = int((1.0 / l * 0.5 + 0.5) * 255.0)
			nrm[o + 3] = 255
			o += 4

	var ai := Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RGBA8, alb)
	ai.generate_mipmaps()
	var ni := Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RGBA8, nrm)
	ni.generate_mipmaps()
	return {"albedo": ImageTexture.create_from_image(ai),
		"normal": ImageTexture.create_from_image(ni)}
