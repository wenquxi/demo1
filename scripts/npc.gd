extends Node3D
## NPC：站在原地可交谈的角色。
##
## 对话触发分两级：
##   第一次  —— 由场景里的 TriggerZone 坐标触发（one_shot），本节点不参与
##   后续    —— 玩家走近后按 F，由本节点调 Dialogue.start()
## 本节点不知道剧本怎么解析、不知道 UI 长什么样，只负责「在范围内 + 按 F」
## 这个输入事件，其余全交给 Dialogue 枢纽。

@export_group("交互")
## 按多少米内可以按 F 交谈
@export var interact_radius := 2.2
## 要播放的剧本文件
@export_file("*.txt") var dialogue_path := "res://dialogue/demo_01.txt"

var _player_near := false

@onready var _hint: Label3D = $Hint


func _physics_process(_delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player")
	_player_near = player != null \
		and global_position.distance_to(player.global_position) <= interact_radius
	# 交谈提示只在「走近且没在对话中」时显示
	_hint.visible = _player_near and not Dialogue.is_active()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact"):
		return
	# 不在附近、或正在对话中时，F 不做任何事
	if not _player_near or Dialogue.is_active():
		return
	get_viewport().set_input_as_handled()
	Dialogue.start(dialogue_path)
