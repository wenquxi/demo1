# 项目长期记忆 — F:/demo1/dev

## 环境与工具链（已验证可用）

- **Godot 引擎**：`F:\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe`
  - 版本：`4.7.2.stable.steam.ed1daf0bf`（Steam 版，tools 构建，含编辑器）
  - 引擎目录内还有 `editor_data/`，Steam 版依赖 `steam_api64.dll`
- **验证命令**（写文件后必跑，确认无语法/资源错误）：
  ```bash
  cd "F:/demo1/dev" && "/f/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe" --headless --path "F:/demo1/dev" --import
  ```
  退出码 0 且无 ERROR/SCRIPT ERROR 行 = 通过。
- 其它可用参数：`--check-only <script.gd>` 单脚本语法检查；`--headless --quit-after N` 跑主场景 N 帧。
- **`--script res://xxx.gd` 模式不会自动加载主场景**，测试脚本需自己 `load()` + `root.add_child()`。
- 测试脚本里 `extends SceneTree` + `_physics_process()` 返回 bool（true 即退出）；
  **初始化必须放在第一帧物理帧**，`_initialize()` 阶段 root 未入树，读 `global_position` 会报
  `!is_inside_tree()`。`Input.action_press()/action_release()` 可在无头模式模拟按键。
- **要在测试里访问 autoload，不能用 `--script`**（该模式下 SceneTree 被自定义 MainLoop
  替换，autoload 不注册，`Game` 为 null）。改用 **场景方式启动**：
  `godot --headless <项目> res://_tmp_runner.tscn`，autoload 正常加载。
- `extends Node` 的 `_physics_process` 必须返回 `void`；返回 `bool` 只有 `MainLoop`/`SceneTree` 才行。
- 浮点绝对值是 `absf()`（没有 `absh()`）。
- Tween 把 `scale` 缩到 `Vector3.ZERO` → 变换矩阵奇异，Jolt 每帧告警；缩到 `Vector3.ONE * 0.01`。
- 无副作用物理探针：`test_move(from, motion, KinematicCollision3D)` —— 不移动刚体就能拿到
  碰撞法线与 `get_travel()`。做「先预检再提交」的逻辑时优先用它，别用 `move_and_collide` 试探。
- 手写 `.tscn` 需要 Transform3D 时，不要手算旋转矩阵，用临时脚本调 `Basis.from_euler()`
  让引擎输出 12 个浮点数（列主序：basis.x 三分量, basis.y, basis.z, origin）。

## 工程配置现状

- 项目名 `dev`，`config/features = ("4.7", "Forward Plus")`
- 渲染驱动（Windows）：`d3d12`
- 3D 物理引擎：`Jolt Physics`（非默认 Godot Physics）
- 窗口拉伸：`canvas_items` + `expand`
- 主场景：`res://scenes/main.tscn`
- 已有内容：3D 第三人称原型（角色控制器 + 上台阶 + 收集/通关/存成绩的游戏循环 + HUD）
- **Autoload**：`Game` → `res://scripts/game.gd`（收集进度、计时、最佳成绩持久化到
  `user://progress.cfg`）。只通过信号对外广播，不引用场景节点。
- 存档路径 `Game.save_path` 可改；改了之后调 `Game.reload_best()` 重新读盘。

## 代码约定

- 注释与 HUD 文案一律用中文；GDScript 用 typed 写法（`var x: float`、显式参数类型）。
- 可调参数放 `@export` 并按 `@export_group` 分组，命名用 snake_case。
- 跳跃/手感类参数用「物理上可感知的量」表达（高度、秒数），在 `_ready()` 里反推重力，
  不要直接暴露重力数值。
- 关卡原型件优先用 `CSGBox3D` + `use_collision = true`，省掉 mesh/shape 成对定义；
  需要正式关卡时再替换为 StaticBody3D + 独立资源。
- 已知限制：CharacterBody3D 无自动上台阶，已在 `player.gd` 中自行实现 step-up
  （见 `_try_step_up` / `_probe_step_landing`）。**改动碰撞体半径或台阶尺寸时务必回归测试**：
  台阶深度接近碰撞半径时可行前推区间会窄到几厘米，容易静默失效。
- 单向数据流：收集物 → `Game`（发信号）→ HUD 订阅刷新。不要让 HUD 反向调用游戏逻辑。

## 协作分工（2026-10-16 约定）

- 用户计划让本 agent 与 DeepSeek / Cursor 协同开发同一工程，**本 agent 负责地图设计**。
- 建议边界：地图产物（关卡数据、生成出的场景、构建与校验脚本）归本 agent，拟放 `levels/`；
  玩法代码（`player.gd` / `game.gd` / `hud.gd` 等）归对方，共享契约只读、双向不越界。
- **冲突源**：引擎会在导入时回写 `.tscn`/`.gd` 的 `uid`，两个 agent 同时写场景必然产生
  uid 漂移与引用失效。所以地图应由**数据生成**而非手写 `.tscn`。
- **地图与角色的硬耦合**（必须写进契约）：台阶深度 0.45m 对胶囊半径 0.4m 只剩 6cm 余量；
  跳高 1.5m、水平 5.0 m/s 决定最大跨距。**任一方改角色尺寸/跳跃参数，另一方地图都要回归**。

