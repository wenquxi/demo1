# 确定项 01 —— 对话 Demo 任务书

**目标**：走进某个坐标 → 弹出两行文字 → 空格推进 → 关闭 → 恢复操作。跑通就行，简陋优先。

剧本内容就这两行：

```
A: 你好
B: 你好，你的任务是收集星星
```

---

## 1. 新建这些文件

| 文件 | 职责 |
|---|---|
| `dialogue/demo_01.txt` | 剧本，就是上面两行。UTF-8 |
| `scripts/dialogue/dialogue_parser.gd` | 纯静态函数：文本 → 行为数组 |
| `scripts/dialogue/dialogue.gd` | 状态机，注册为 autoload `Dialogue` |
| `scripts/dialogue/dialogue_box.gd` + `scenes/dialogue/dialogue_box.tscn` | 对话框 UI |
| `scripts/dialogue/trigger_zone.gd` + `scenes/dialogue/trigger_zone.tscn` | 坐标触发 |
| `tests/dialogue_smoke.gd` + `.tscn` | 无头冒烟测试 |

分工原则：**解析器不认识 UI，UI 不认识触发器，触发器不认识解析器**，全靠 `Dialogue` 串。

---

## 2. 解析器 `DialogueParser`

```gdscript
class_name DialogueParser
extends RefCounted

## 返回 Array[Dictionary]，每项 {"who": String, "text": String, "line": int}
static func parse(text: String) -> Array
static func parse_file(path: String) -> Array
```

按行解析：

| 情况 | 处理 |
|---|---|
| 空行 / 以 `#` 开头 | 跳过 |
| 含 `:` 或 `：` | 第一个冒号前 = 说话人，后 = 正文。任一侧为空 → 整行当旁白 |
| 无冒号 | 旁白，`who = ""` |

无状态、不发信号、不报 UI。文件读不到返回 `[]`。

---

## 3. 状态机 `Dialogue`（autoload）

```gdscript
extends Node

signal dialogue_started
signal line_shown(who: String, text: String)
signal dialogue_finished

func start(path: String) -> void
func advance() -> void
func is_active() -> bool
```

| 时机 | 行为 |
|---|---|
| `start()` | 解析 → 游标归零 → 显示对话框 → emit `dialogue_started` → 立刻显示第 0 行 |
| `start()` 拿到空数组 | 警告，不进对话状态，不留半个对话框 |
| `advance()` | 游标 +1；有行就 emit `line_shown`；没有就 emit `dialogue_finished` 并关框 |
| `advance()` 未激活时 | 直接 return（否则空格会把界面打穿） |

`_ready()` 里自己 `load()` 并 `add_child()` 对话框场景。
**对话框不放进 `main.tscn`**——这样不用改关卡场景，避免和另一边抢 `.tscn`。

---

## 4. 对话框 `DialogueBox`

结构：

```
DialogueBox (CanvasLayer, layer=10)
├── Backdrop (ColorRect)     全屏，黑 35%，mouse_filter = IGNORE
└── Panel (Panel)            底部横条：左 0.05 右 0.95 下 0.94 上 0.74
	├── NameLabel (Label)
	├── Margin (MarginContainer) → TextLabel (RichTextLabel)
	└── Arrow (Label, "▼")
```

- 底板内联 `StyleBoxFlat`：`#0b0f14`、不透明度 0.88、圆角 6、边框 2px `#3d5566`。
- `NameLabel` 22 号 `#ffd479`；`TextLabel` 20 号白，`bbcode_enabled = true`，`autowrap_mode = WORD_SMART`。
- `TextLabel` 用 `RichTextLabel` 而不是 `Label`，下一版能直接写 `[color]`。
- 逐字显示：每秒 30 字，`visible_characters = int(_revealed)`，在 `_process` 里累加。
  **不要用 Tween**——行间会被打断。
- `Arrow` 只在 `not is_typing()` 时可见。

接口：

```gdscript
func show_line(who: String, text: String) -> void
func reveal_all() -> void
func is_typing() -> bool
func close() -> void
```

输入（`_unhandled_input`，必须 `set_input_as_handled()` 吃掉）：

| 输入 | 行为 |
|---|---|
| `ui_accept`（空格 / 回车，内置动作） | 正在逐字 → 全显；否则 → `Dialogue.advance()` |
| 鼠标左键 | 同上 |

用内置 `ui_accept`，**不要新增 InputMap 动作**，省掉改 `project.godot` 的 `[input]` 段。

---

## 5. 触发器 `TriggerZone`

```gdscript
extends Node3D

@export var radius := 2.0
@export_file("*.txt") var dialogue_path := "res://dialogue/demo_01.txt"
@export var one_shot := true
```

`_physics_process` 里每帧五个判断，任一不满足就 return：

1. `one_shot and _fired` → 已触发过
2. `Dialogue.is_active()` → 正在对话
3. `get_tree().get_first_node_in_group("player")` 为 null
4. `global_position.distance_to(player.global_position) > radius`
5. 都过了 → `_fired = true` → `Dialogue.start(dialogue_path)`

**确定项：用距离判定，不要 `Area3D` + 碰撞层。**
不需要配 layer/mask，不会因为设错而静默失效，测试里改坐标就能验。

场景只有 `Node3D` + 一个可选的线框球（编辑器里看范围用），**不要 CollisionShape3D**。

---

## 6. 改这三个地方

### 6.1 `project.godot` —— 加一行

```
[autoload]
Game="*res://scripts/game.gd"
Dialogue="*res://scripts/dialogue/dialogue.gd"
```

### 6.2 `scripts/player.gd` —— 冻结输入，只改两处

`_physics_process()` 开头：

```gdscript
	# 对话进行中：清空操作意图，但保留重力与贴地
	if Dialogue.is_active():
		velocity.x = 0.0
		velocity.z = 0.0
		if not is_on_floor():
			velocity.y -= (_rise_gravity if velocity.y > 0.0 else _fall_gravity) * delta
		move_and_slide()
		return
```

`_unhandled_input()` 开头：

```gdscript
	if Dialogue.is_active():
		return
```

**不要**改成 `set_physics_process(false)`——角色会卡在半空，结束后也不贴地。

### 6.3 `scenes/main.tscn` —— 加一个 `TriggerZone` 实例

| 属性 | 值 |
|---|---|
| 位置 | `(0, 0, -3)` |
| `radius` | `1.8` |
| `dialogue_path` | `res://dialogue/demo_01.txt` |
| `one_shot` | `true` |

`main.tscn` 是和另一边共用的文件：**只新增这一个节点**，不重排、不格式化、单独提交。

---

## 7. 本期不做

选项分支 / flag / 立绘 / 表情 / 镜头切换 / 淡入淡出 / 音效 / 语音 /
历史记录 / 自动播放 / 存档 / 打字机速度可调 / 对话时 NPC 看向玩家 /
Area3D 触发 / 碰撞检测。

这些留到下一版。**一行都不要提前写**——加一处就多一处要返工。

---

## 8. 验收

- [ ] `--headless --import` 退出码 0，无 `ERROR` / `SCRIPT ERROR`
- [ ] `tests/dialogue_smoke` 输出 `SMOKE OK`，退出码 0
- [ ] 走进 `(0,0,-3)` 半径 1.8：对话框弹出，显示 `A` / `你好`
- [ ] 空格 → `B` / `你好，你的任务是收集星星`
- [ ] 再空格 → 对话框关闭
- [ ] 关闭后立刻能移动
- [ ] 走开再走回，不重复触发
- [ ] 对话中按 WASD / 跳，角色不动
- [ ] 中文正常显示，无方块、无溢出
- [ ] `git status` 里只有第 1、6 节列出的文件

冒烟测试要点：连 `line_shown`，`start()` 后断言两行的 `who` / `text` 完全正确，
再 `advance()` 两次断言收到 `dialogue_finished`。
用内联字符串测解析器，用真实文件测 `start()`，两者都要覆盖。

---

## 9. 给下一版留的位置（只留结构，不写代码）

| 预留 | 现在怎么留 |
|---|---|
| 选项分支 | `advance()` 单独成函数，别写死在 `_process` |
| 立绘 | `Panel` 用容器布局，左右今后能塞图 |
| 说话人配色 | `DialogueBox` 里放 `const SPEAKER_COLORS := {}`，本期为空 |
| 剧本指令 | 解析器遇到 `@` 开头的未知行**跳过不报错** |
| 多段对话 | `start(path)` 已经参数化，将来不用改签名 |
