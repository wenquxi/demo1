extends Node
## 对话状态机（注册为 autoload「Dialogue」）。
##
## 全系统的唯一枢纽：解析器不认识 UI，UI 不认识触发器，触发器不认识解析器，
## 三者全靠这里发出的信号协作。对话框由本节点在 _ready() 里自行加载，
## 不放进关卡场景 —— 改对话不用碰 main.tscn。

signal dialogue_started
signal line_shown(who: String, text: String)
signal dialogue_finished

var _lines: Array = []
var _cursor := 0
var _active := false
var _box: CanvasLayer


func _ready() -> void:
	var scene: PackedScene = load("res://scenes/dialogue/dialogue_box.tscn")
	if scene != null:
		_box = scene.instantiate()
		add_child(_box)
	else:
		push_warning("Dialogue: 加载对话框场景失败，语音内容仍走信号，只是没有画面")


## 从剧本文件开始一段对话。空剧本只警告，不进对话状态、不留半个对话框。
func start(path: String) -> void:
	_lines = DialogueParser.parse_file(path)
	if _lines.is_empty():
		push_warning("Dialogue: 剧本为空或读取失败，忽略本次 start：%s" % path)
		return
	_cursor = 0
	_active = true
	if _box != null:
		_box.visible = true
	dialogue_started.emit()
	# 立刻显示第 0 行，不让玩家面对一个空框按空格
	_show_current()


## 推进一行；越界即结束并关框。未激活时直接 return（否则空格会把界面打穿）。
func advance() -> void:
	if not _active:
		return
	_cursor += 1
	if _cursor < _lines.size():
		_show_current()
	else:
		_active = false
		if _box != null:
			_box.close()
		dialogue_finished.emit()


func is_active() -> bool:
	return _active


func _show_current() -> void:
	var entry: Dictionary = _lines[_cursor]
	var who: String = entry["who"]
	var text: String = entry["text"]
	if _box != null:
		_box.show_line(who, text)
	line_shown.emit(who, text)
