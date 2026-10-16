extends Node3D
## 关卡根节点。
##
## 职责很窄：数出本关有多少收集物并把总量交给 Game，以及处理重开。
## 收集物自身只管「被碰到」，进度统计全在 Game 里，三者互不引用。


@onready var _collectibles: Node3D = $Collectibles


func _ready() -> void:
	# 收集物在自己的 _ready() 里入组，而子节点的 _ready() 先于父节点执行，
	# 所以这里统计时数量已经齐全。
	var count := 0
	for child in _collectibles.get_children():
		if child.is_in_group("collectible"):
			count += 1
	Game.begin_run(count)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart"):
		# 先停表，避免场景重载的这一帧还在累计时间
		Game.reset_run()
		get_tree().reload_current_scene()
