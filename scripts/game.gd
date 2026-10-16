extends Node
## 全局游戏状态单例（Autoload 名为 Game）。
##
## 职责边界：只管「一局游戏的状态」——收集进度、计时、通关判定、最佳成绩。
## 不引用任何场景节点，只通过信号对外广播，所以 HUD、关卡、收集物之间互不依赖。

## 收集数量变化时发出
signal collected_changed(collected: int, total: int)
## 本局开始时发出
signal run_started(total: int)
## 全部收集完成时发出（elapsed 为用时，best 为最佳成绩，is_new_best 表示是否破纪录）
signal run_finished(elapsed: float, best: float, is_new_best: bool)

## 存档路径。用 user:// 而非 res://，导出后才有写入权限；测试时可临时改写。
var save_path := "user://progress.cfg"

var total := 0
var collected := 0
var elapsed := 0.0

var _running := false
var _best := 0.0


func _ready() -> void:
	_best = _load_best()


func _process(delta: float) -> void:
	if _running:
		elapsed += delta


## 开始新的一局，由关卡根节点在统计完收集物数量后调用
func begin_run(collectible_count: int) -> void:
	total = collectible_count
	collected = 0
	elapsed = 0.0
	_running = true
	run_started.emit(total)
	collected_changed.emit(collected, total)


## 停止计时并清空本局进度（重开前调用，避免重载间隙继续计时）
func reset_run() -> void:
	_running = false
	collected = 0
	elapsed = 0.0
	collected_changed.emit(collected, total)


## 收集到一个，由 collectible.gd 调用
func collect() -> void:
	if not _running or collected >= total:
		return
	collected += 1
	collected_changed.emit(collected, total)
	if collected >= total:
		_finish()


func best_time() -> float:
	return _best


## 从磁盘重新读取最佳成绩。换过 save_path、或外部改动过存档后调用。
func reload_best() -> void:
	_best = _load_best()


func is_finished() -> bool:
	return not _running and total > 0 and collected >= total


func _finish() -> void:
	_running = false
	var is_new_best := _best <= 0.0 or elapsed < _best
	if is_new_best:
		_best = elapsed
		_store_best(elapsed)
	run_finished.emit(elapsed, _best, is_new_best)


func _load_best() -> float:
	var cfg := ConfigFile.new()
	if cfg.load(save_path) != OK:
		return 0.0
	return float(cfg.get_value("record", "best_time", 0.0))


func _store_best(seconds: float) -> void:
	var cfg := ConfigFile.new()
	# 先读回已有内容再写，避免覆盖同文件里将来可能加的其它字段
	cfg.load(save_path)
	cfg.set_value("record", "best_time", seconds)
	cfg.save(save_path)
