extends Node3D
## 坐标触发器：玩家走进 radius 范围就调 Dialogue.start()。
##
## 确定项：用距离判定，不用 Area3D + 碰撞层 —— 不需要配 layer/mask，
## 不会因为设错而静默失效，测试里改坐标就能验。
## 只发一次 start，不知道剧本内容、不知道解析器。

@export var radius := 2.0
@export_file("*.txt") var dialogue_path := "res://dialogue/demo_01.txt"
@export var one_shot := true

var _fired := false


func _ready() -> void:
	# 范围指示球只给编辑器里看尺寸用，运行时隐藏
	var hint := get_node_or_null("RangeHint")
	if hint != null:
		hint.visible = false


func _physics_process(_delta: float) -> void:
	if one_shot and _fired:
		return
	if Dialogue.is_active():
		return
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	if global_position.distance_to(player.global_position) > radius:
		return
	_fired = true
	Dialogue.start(dialogue_path)
