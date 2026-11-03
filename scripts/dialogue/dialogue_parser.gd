class_name DialogueParser
extends RefCounted
## 剧本解析器：纯静态函数，文本 → 行数组。
##
## 无状态、不发信号、不认识 UI；文件读不到返回 []，由上层决定怎么处理。
## 行规则：
##   空行 / # 开头        → 跳过
##   @ 开头               → 剧本指令，本版不实现，跳过不报错
##   含 : 或 ：           → 第一个冒号前 = 说话人，后 = 正文
##   冒号任一侧为空       → 整行当旁白
##   无冒号               → 旁白，who = ""


## 返回 Array[Dictionary]，每项 {"who": String, "text": String, "line": int}。
## line 是该行在源文件中的行号（从 1 起，含被跳过的行），供报错定位用。
static func parse(text: String) -> Array:
	var lines: Array = []
	var raw := text.split("\n")
	for i: int in raw.size():
		var line := raw[i].strip_edges()
		if line.is_empty() or line.begins_with("#") or line.begins_with("@"):
			continue

		var who := ""
		var body := line
		# 取两种冒号中先出现的一个作为分隔符
		var sep := line.find(":")
		var sep_full := line.find("：")
		if sep_full != -1 and (sep == -1 or sep_full < sep):
			sep = sep_full
		if sep != -1:
			var left := line.substr(0, sep).strip_edges()
			var right := line.substr(sep + 1).strip_edges()
			# 任一侧为空 → 整行当旁白，不拆分
			if left != "" and right != "":
				who = left
				body = right
		lines.append({"who": who, "text": body, "line": i + 1})
	return lines


## 从文件读剧本；读不到返回空数组并警告，不抛异常。
static func parse_file(path: String) -> Array:
	if not FileAccess.file_exists(path):
		push_warning("DialogueParser: 找不到剧本文件 %s" % path)
		return []
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("DialogueParser: 打不开剧本文件 %s（错误码 %d）" % [path, FileAccess.get_open_error()])
		return []
	return parse(file.get_as_text())
