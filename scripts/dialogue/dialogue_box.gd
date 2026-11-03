extends CanvasLayer
## 对话框 UI：底部横条 + 说话人名 + RichTextLabel 正文 + 继续箭头。
##
## 只负责「显示一行字」和「吃掉确认输入」，不知道剧本、不知道触发器，
## 推进一律委托给 Dialogue.advance()。逐字显示用 _process 累加
## visible_characters（不用 Tween —— 行间会被打断）。

## 每秒显示的字数
const CHARS_PER_SEC := 30.0
## 说话人配色表，下一版填充，例如 {"A": Color(1.0, 0.8, 0.4)}。本期为空。
const SPEAKER_COLORS := {}

var _revealed := 0.0
var _total := 0
var _typing := false

@onready var _name_label: Label = $Panel/NameLabel
@onready var _text_label: RichTextLabel = $Panel/Margin/TextLabel
@onready var _arrow: Label = $Panel/Arrow


func _ready() -> void:
	visible = false


func _process(delta: float) -> void:
	if not _typing:
		return
	_revealed = minf(_revealed + CHARS_PER_SEC * delta, float(_total))
	_text_label.visible_characters = int(_revealed)
	if _revealed >= float(_total):
		_typing = false
		_arrow.visible = true


## 显示一行。who 为空时隐藏名字（旁白）。
func show_line(who: String, text: String) -> void:
	visible = true
	_name_label.text = who
	_name_label.visible = who != ""
	# 预留：按说话人取配色
	if SPEAKER_COLORS.has(who):
		_name_label.add_theme_color_override("font_color", SPEAKER_COLORS[who])
	_text_label.text = text
	_total = text.length()
	_revealed = 0.0
	_text_label.visible_characters = 0
	_arrow.visible = false
	_typing = _total > 0


## 跳过逐字动画，整行立刻显示。
func reveal_all() -> void:
	_revealed = float(_total)
	_text_label.visible_characters = _total
	_typing = false
	_arrow.visible = true


func is_typing() -> bool:
	return _typing


func close() -> void:
	visible = false
	_typing = false


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	var mb := event as InputEventMouseButton
	var confirm := event.is_action_pressed("ui_accept") \
		or (mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT)
	if not confirm:
		return
	# 吃掉输入，防止空格同时触发跳跃等底层逻辑
	get_viewport().set_input_as_handled()
	if _typing:
		reveal_all()
	else:
		Dialogue.advance()
