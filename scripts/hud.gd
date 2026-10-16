extends CanvasLayer
## HUD：只订阅 Game 的信号来刷新显示，不反向驱动游戏状态，保证单向数据流。

const HINT_TEMPLATE := """上台阶能力：%s      T 切换
WASD / 方向键  移动        鼠标  视角        左键  重新锁定
空格  跳跃        Shift  冲刺        Esc  释放鼠标        R  重新开始"""

var _player = null

@onready var _info: Label = $Info
@onready var _hint: Label = $Hint
@onready var _banner: Label = $Banner


func _ready() -> void:
	Game.collected_changed.connect(_on_collected_changed)
	Game.run_started.connect(_on_run_started)
	Game.run_finished.connect(_on_run_finished)
	_banner.hide()
	_refresh()


func _process(_delta: float) -> void:
	_refresh()


func _on_run_started(_total: int) -> void:
	_banner.hide()


func _on_collected_changed(_collected: int, _total: int) -> void:
	_refresh()


func _on_run_finished(elapsed: float, best: float, is_new_best: bool) -> void:
	var lines := ["全部收集完成！", "用时 %s" % _format(elapsed)]
	lines.append("新纪录！" if is_new_best else "最佳 %s" % _format(best))
	lines.append("按 R 重新开始")
	_banner.text = "\n".join(lines)
	_banner.show()


func _refresh() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")

	var state := "开"
	if _player != null:
		# 用 Object.get() 读取，避免静态类型分析抱怨未知成员
		if _player.get("step_up_enabled") == false:
			state = "关"
	_hint.text = HINT_TEMPLATE % state

	_info.text = "收集 %d / %d        用时 %s        最佳 %s" % [
		Game.collected,
		Game.total,
		_format(Game.elapsed),
		_format_or_dash(Game.best_time()),
	]


func _format(seconds: float) -> String:
	var minutes := int(seconds) / 60
	return "%d:%05.2f" % [minutes, seconds - float(minutes * 60)]


func _format_or_dash(seconds: float) -> String:
	return "—" if seconds <= 0.0 else _format(seconds)
