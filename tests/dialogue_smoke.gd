extends Node
## 对话系统冒烟测试（无头运行）。
##
## 覆盖两块：
##   1. 解析器 —— 内联字符串覆盖全部行规则（注释/指令/全半角冒号/旁白/空侧）
##   2. 状态机 —— 用真实剧本文件走完 start → line_shown ×2 → dialogue_finished
## 全部通过打印 SMOKE OK 并以退出码 0 结束。


var _fails := 0


func _check(name: String, cond: bool) -> void:
	print(("  PASS  " if cond else "  FAIL  ") + name)
	if not cond:
		_fails += 1


func _ready() -> void:
	_test_parser_inline()
	_test_parser_file()
	await _test_state_machine()
	if _fails == 0:
		print("SMOKE OK")
	else:
		print("SMOKE FAILED: %d 处断言未通过" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)


func _test_parser_inline() -> void:
	print("[解析器 - 内联文本]")
	var script := "A: 你好\n\n# 注释行\nB：全角冒号\n旁白行\n: 冒号前为空\n冒号后为空:\n@指令 以后再说\n尾行: 有第二个:冒号"
	var r := DialogueParser.parse(script)

	_check("行数 = 6（空行/注释/指令被跳过）", r.size() == 6)
	if r.size() != 6:
		return
	_check("半角冒号拆分 who=A", r[0]["who"] == "A" and r[0]["text"] == "你好")
	_check("全角冒号拆分 who=B", r[1]["who"] == "B" and r[1]["text"] == "全角冒号")
	_check("无冒号 → 旁白", r[2]["who"] == "" and r[2]["text"] == "旁白行")
	_check("冒号前为空 → 整行当旁白", r[3]["who"] == "" and r[3]["text"] == ": 冒号前为空")
	_check("冒号后为空 → 整行当旁白", r[4]["who"] == "" and r[4]["text"] == "冒号后为空:")
	_check("只按第一个冒号拆分", r[5]["who"] == "尾行" and r[5]["text"] == "有第二个:冒号")
	_check("line 记录源文件行号", r[0]["line"] == 1 and r[2]["line"] == 5)

	var empty := DialogueParser.parse("\n\n#只有注释\n")
	_check("全被跳过 → 空数组", empty.is_empty())


func _test_parser_file() -> void:
	print("[解析器 - 真实文件]")
	var r := DialogueParser.parse_file("res://dialogue/demo_01.txt")
	_check("demo_01.txt 解析出 2 行", r.size() == 2)
	if r.size() == 2:
		_check("第 0 行 = A / 你好", r[0]["who"] == "A" and r[0]["text"] == "你好")
		_check("第 1 行 = B / 收集星星", r[1]["who"] == "B" and r[1]["text"] == "你好，你的任务是收集星星")
	_check("不存在的文件 → 空数组", DialogueParser.parse_file("res://dialogue/不存在.txt").is_empty())


func _test_state_machine() -> void:
	print("[状态机 Dialogue]")
	var started := [false]
	var finished := [0]
	var shown: Array = []
	Dialogue.dialogue_started.connect(func() -> void: started[0] = true)
	Dialogue.dialogue_finished.connect(func() -> void: finished[0] += 1)
	Dialogue.line_shown.connect(func(who: String, text: String) -> void: shown.append([who, text]))

	_check("初始未激活", not Dialogue.is_active())
	Dialogue.advance()
	_check("未激活时 advance 直接 return（不崩溃）", not Dialogue.is_active() and shown.is_empty())

	Dialogue.start("res://dialogue/demo_01.txt")
	_check("start 后激活", Dialogue.is_active())
	_check("收到 dialogue_started", started[0])
	_check("立刻显示第 0 行 A/你好",
			shown.size() == 1 and shown[0][0] == "A" and shown[0][1] == "你好")

	Dialogue.advance()
	_check("第二行 = B/收集星星",
			shown.size() == 2 and shown[1][0] == "B" and shown[1][1] == "你好，你的任务是收集星星")
	_check("第二行后仍激活", Dialogue.is_active())

	Dialogue.advance()
	_check("收到 dialogue_finished", finished[0] == 1)
	_check("结束后未激活", not Dialogue.is_active())

	Dialogue.advance()
	_check("结束后 advance 不再发任何信号", shown.size() == 2 and finished[0] == 1)

	var started2 := [false]
	Dialogue.dialogue_started.connect(func() -> void: started2[0] = true)
	Dialogue.start("res://dialogue/不存在.txt")
	_check("空剧本不进对话状态", not Dialogue.is_active() and not started2[0])
