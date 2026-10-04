# 会说话的西小电：技术架构与语音规格

版本：v1.0 · 对应 [产品方案](PROJECT_PLAN.md) · Godot 4.6.1

本文规定模块职责、语音状态机、数据契约和设备验收约束。标有“初值”的参数必须放入配置资源；调整时同时更新验收记录。Godot 桌面版核心原型已落地并启动无脚本/场景错误；任何手机上的录音、画面或性能仍未验收。

当前原型另已接入扁平化竖屏 HUD、程序化渐变背景、右上角 BGM/SFX 设置、项目内生成的循环低 bit BGM，以及身体/脚部触摸笑声。“玩耍”是点击/按键跳跃的横向无尽跑酷，可收集电星和能量电池并记录本地最佳分数。角色待机与跳跃双臂自然下垂，倾听会侧头并抬手靠近耳边；这些是 `CharacterPresenter` 逐帧驱动骨骼的过渡表现，不代表正式动画资产已经制作。

## 1. 技术决策

| 决策 | 首版选择 | 原因 / 放行条件 |
|---|---|---|
| 游戏脚本 | 类型标注的 GDScript | 与现有 Godot 项目和移动导出流程一致 |
| 画面 | 3D 角色与简单房间 + 2D UI | 聚焦角色表现，控制资源规模 |
| 渲染 | Android 优先验证 Compatibility；iOS 由早期样包冻结路径 | 根据真实设备覆盖和质量选择 |
| 收音与检测 | AudioStreamMicrophone + AudioEffectCapture + 本地声级检测 | 能访问连续样本，支持句首缓冲和可控句尾 |
| 复述 | PCM 音频 + AudioStreamPlayer.pitch_scale | 基础方案开销较小，变调与加速产生滑稽感 |
| 内容配置 | 自定义 Resource / .tres | 数值、动作映射、物品定义与代码分离 |
| 保存 | user:// 下带版本和备份的结构化数据 | 离线启动与恢复，便于迁移 |
| 平台差异 | PlatformService 统一权限和生命周期 | Android 与 iOS 不共用未经确认的权限实现 |
| 服务端 | 核心功能无依赖 | 离线体验、启动时延和资源成本可控 |

引擎与导出模板锁定同一完整版本。升级到其他 4.6 补丁或更高版本应独立记录，并重跑资源导入、音频和最低设备检查，不能在实现某个玩法任务时顺带升级。

## 2. 场景与目录

以下为目标拆分结构，不与当前原型的简化目录一一对应。当前已运行的入口是 `Scenes/Main.tscn`，代码位于 `Scripts/`；拆分模块时应保留已实现的语音、角色、存档和小游戏行为。

~~~text
会说话的西小电/
  project.godot
  Assests/                         # 保留当前真实拼写
    Model/xxd2.gltf                  # 当前角色；88 根骨骼，贴图材质已在 Godot 预览核对
    Model/xxd2_*.png                 # glTF 导出的材质贴图；腰带贴图导入上限 2048
    Model/XXD.glb                    # 先前候选，保留参考
    Model/xixiaodian2.fbx           # 旧静态模型，对照/源资源
    Model/xixiaodian_mobile.glb     # 可选的后续优化派生模型
    Characters/xixiaodian/          # 面部、材质、装饰等派生资源
    Audio/
    UI/
  scenes/
    app/app.tscn
    home/home_world.tscn
    character/xixiaodian.tscn
    ui/home_ui.tscn
    ui/settings_panel.tscn
    minigames/catch_stars.tscn
  scripts/
    app/
    voice/
    character/
    pet/
    economy/
    platform/
    save/
    ui/
  data/
    voice_config.tres
    balance_config.tres
    animation_map.tres
    items/
    tasks/
  audio/default_bus_layout.tres
  tests/                           # 仅加入有价值的状态/数据/集成测试
  export_presets.cfg                # 发行配置；签名凭据不写入
~~~

工作区的 docs 与 source_art 位于 Godot 项目根目录之外。导出选择主场景及其依赖；不把源文件、测试录音、文档和未引用的长音轨全部加入发行包。

~~~text
App (Node，负责装配)
  PetModel                         # 唯一的角色数值写入者
  EconomyService                   # 货币/物品/奖励事务
  TaskService                      # 目标计数
  VoiceService
    MicInputPlayer
    VoicePlaybackPlayer
  InteractionDirector
  HomeView (Control)
    WorldDisplay (TextureRect)
    WorldViewport (SubViewport)
      HomeWorld (Node3D)
        Camera3D
        Lighting
        CharacterRoot
          VisualPivot
            ImportedCharacter
          AnimationTree
          CharacterPresenter
          FaceController
          Head/Body/FootHitAreas
    HomeUI
    ModalLayer
  MiniGameHost
~~~

采用单个 3D SubViewport 控制角色画面的内部渲染分辨率，并将纹理显示到 WorldDisplay；UI 保持正常显示分辨率。内部宽高比与实际显示矩形一致，短边按质量档位选择。不要重复创建多个房间渲染视口。

触摸坐标必须先去除显示矩形偏移，再按显示尺寸映射到 SubViewport 像素，最后用该视口 Camera3D 做射线查询。UI 消费的输入不能继续触发角色；只用简化的头/身体/脚碰撞区，不使用高面数原网格做触摸碰撞。

建议仅将 SettingsService、SaveService、PlatformService 设为 Autoload。其他模块随 App 场景创建和销毁，避免重进主场景后出现两个麦克风播放器或重复信号连接。

## 3. 模块职责和契约

~~~mermaid
flowchart TD
    UI[HomeUI：操作意图] --> D[InteractionDirector：行为仲裁]
    P[PlatformService：权限与生命周期] --> V[VoiceService：语音状态机]
    D --> V
    V --> C[CharacterPresenter：角色表现]
    D --> C
    D --> M[PetModel：数值]
    G[小游戏结果] --> E[EconomyService：奖励事务]
    M --> E
    V --> T[TaskService：有效互动事件]
    E --> S[SaveService：持久化]
    T --> E
    M --> UI
    V --> UI
~~~

| 模块 | 对外接口示意 | 唯一职责 |
|---|---|---|
| VoiceService | set_enabled(bool)、set_mode(AUTO/HOLD)、begin_hold()、end_hold()、cancel(reason) | 采集、分句、当前录音、播放状态；不直接改货币 |
| PlatformService | query_microphone_permission()、request_microphone_permission()、app_active_changed、audio_route_changed | 屏蔽系统差异；不能把发出请求当作授权完成 |
| InteractionDirector | request_action(action, payload) → accepted/action_id | 决定交互优先级、取消和队列上限 |
| CharacterPresenter | enter_pose(pose, token)、play_reaction(id, token) | 动画参数与角色视觉；不持有保存逻辑 |
| FaceController | set_speech_envelope(value)、set_expression(id) | 表情、眨眼、嘴部/发声部件 |
| PetModel | apply_care(action, transaction_id)、advance_active_time(dt)、reconcile_offline(now) | 状态与亲密度；独立于场景节点路径 |
| EconomyService | commit_reward(source, amount, transaction_id)、purchase(item_id, transaction_id) | 统一校验、去重、修改库存和保存 |
| TaskService | consume(event) | 用真实事件完成任务；无语义理解假设 |
| SaveService | load_latest_valid()、commit(snapshot) → success/error | 版本、校验、备份、迁移 |
| HomeUI | 发送 intent，订阅 snapshot/state | 显示状态与错误；不直接修改角色或存档 |

所有重要事件带 session_id 或 transaction_id。模块拥有自己产生的数据，接收者把事件视为不可变快照。传输小型数据结构，不跨模块传任意场景 Node 引用。

~~~text
VoiceClip
  session_id: int
  sample_rate_hz: int
  pcm16_mono: PackedByteArray
  source_duration_sec: float
  envelope: PackedFloat32Array
  envelope_hop_sec: float
  active_voice_ms: int
  peak_dbfs: float

voice_state_changed(session_id, state, reason)
input_level_changed(rms_dbfs, threshold_dbfs)     # UI 限频到约 10Hz
utterance_ready(session_id, clip)
playback_finished(session_id, natural_end)
voice_interaction_completed(session_id)         # 有效录音且自然播放完才发
action_committed(transaction_id, action, delta)
mini_game_completed(run_id, score, active_duration, input_count)
~~~

限制：每次只有一个 VoiceService、一个当前录音和一个复述播放器；等待动作队列最多一个可替换的低优先级动作。场景切换、await 返回、定时器回调均要检查所属 token 是否仍然有效。

## 4. 声音总线与采样

推荐总线从左到右排列：

~~~text
0 Master
1 Music        → Master
2 SFX          → Master
3 VoiceOut     → Master
4 MicSilence   → Master，静音
5 MicCapture   → MicSilence，AudioEffectCapture 放在此处
~~~

MicInputPlayer 的 stream 为 AudioStreamMicrophone，bus 为 MicCapture。Capture 所在总线负责采样，后级 MicSilence 阻断实时扩音；必须用设备验证“能读到有效样本，扬声器不直接播麦克风”。不得把 MicInputPlayer 留在 Master。启动自检总线名称与效果器存在性，失败则关闭语音并报告可恢复错误。

设置 audio/driver/enable_input。AudioEffectCapture 的缓冲时长初值 0.5 秒，在效果初始化前设置。持续读取 get_frames_available()/get_buffer()，并观察 get_discarded_frames() 的增量；环形缓冲装满造成的丢帧不能被当成正常静音。官方接口返回的是立体声、32 位浮点 PCM 原始帧，需要应用自己构造可播放资源。[AudioEffectCapture](https://docs.godotengine.org/en/4.6/classes/class_audioeffectcapture.html)

采样约定：

1. 声音总线样本按 AudioServer 实际混音采样率解释，启动时记录该值；目标配置 48kHz，但代码不能假定手机永远返回 48kHz。
2. 左右声道均值转单声道；读到反常路由/声道行为时记入设备报告。
3. 算法分析帧以 20ms 为初值：frame_samples = round(sample_rate × 0.020)。一渲染帧内可以消费多个分析帧。
4. 前置缓存采用固定容量环形数组；整段录音采用有最大容量的 Packed 数组/字节缓冲，不为每个采样点分配对象。
5. 转 PCM16 时先限制到 [-1,1]，按有符号 16 位小端编码；AudioStreamWAV 设置正确采样率、FORMAT_16_BITS、stereo=false。
6. 更改 WAV 的采样率字段会改变解释速度，不能作为正规的重采样。首版直接使用总线采样率，避免增加无必要的重采样环节。
7. 完成/取消/切后台时释放会话缓冲；切换音频路由或采样率时取消当前片段并重新初始化。

输入缓存与发声检测必须按采样数量计算时长，不能依靠渲染帧数计算“连续 120ms”。

## 5. 语音状态机

AUTO/HOLD 是交互模式，不是另一套重复实现。二者共用录音、播放、清理和生命周期。

| 状态 | 进入时操作 | 有效转移 |
|---|---|---|
| DISABLED | 关闭麦克风流、停止播放、清理录音 | 用户启用 → REQUESTING_PERMISSION / CALIBRATING |
| REQUESTING_PERMISSION | 发一次平台授权请求；UI 说明正在等待 | 已授权且前台 → CALIBRATING；拒绝 → DISABLED |
| CALIBRATING | 输入启动；估计环境声，丢弃校准音频 | 校准完成 → ARMED；错误 → ERROR |
| ARMED | 保持短前置缓存，AUTO 运行起听检测，HOLD 等按下 | 检测成立或手动按下 → LISTENING |
| LISTENING | 锁定 session_id；追加连续音频；请求倾听姿态 | 静音截止/松开/长度上限 → PROCESSING |
| PROCESSING | 暂停新触发，裁剪、淡化、生成音频与包络 | 有效片段 → REPEATING；无效短片段 → COOLDOWN |
| REPEATING | VoiceOut 播放；身体与面部表现；麦克风帧被读走丢弃 | 自然结束 → COOLDOWN；手动取消 → COOLDOWN/DISABLED |
| COOLDOWN | 保持检测关闭，等待输出尾音，再清掉预录缓存 | 可收音 → ARMED；路由变化 → CALIBRATING |
| SUSPENDED | 释放输入、停止回放、使旧回调失效 | 前台且仍有启用意图 → 重新检查权限并校准 |
| ERROR | 停止本次会话，展示简短可恢复状态 | 用户重试/有效路由恢复 → 检查权限；关闭 → DISABLED |

任意状态收到关闭、失去权限、销毁场景时均有明确退出路径。所有取消都增加会话代号，使旧处理任务/旧动画回调无法开始播放。

HOLD 模式中，麦克风已由玩家开启后保留短缓存，按下立即显示倾听并记录；松开追加最多约 100ms 尾音，然后整理回放。授权弹窗期间已经松开的手指不算新录音，授权后提示重新按住。自动起听/静音截止逻辑在 HOLD 中关闭，长度上限和取消规则仍有效。

### 5.1 初始检测参数

| 配置名 | 初值 | 说明 |
|---|---|---|
| analysis_frame_ms | 20 | 音量和时长统计粒度 |
| calibration_ms | 1200 | 提醒玩家暂时安静；估计噪声底 |
| pre_roll_ms | 250 | 防止句首缺失 |
| onset_hold_ms | 120 | 连续过门槛才建立自动录音 |
| min_active_voice_ms | 200 | 有效过阈值帧的累计时长 |
| end_silence_ms | 800 | 低于关门阈值后的连续等待 |
| retained_tail_ms | 150 | 播放前保留的自然尾音 |
| max_clip_ms | 12000 | 包括前置缓存的总采集上限 |
| cooldown_ms | 450 | 内置扬声器初值，结合输出延迟调整 |
| default_pitch_scale | 1.30 | 高音且稍快；调试范围约 1.20–1.40 |
| fade_ms | 5–10 | 减少边界爆音 |

声级：

~~~text
rms = sqrt(mean(sample * sample))
level_dbfs = 20 * log10(max(rms, 0.000001))

N = 校准期间较低声级帧的稳健估计（例如 20% 分位数）
T_on  = clamp(N + 12dB + sensitivity_offset, -45dBFS, -24dBFS)
T_off = T_on - 6dB
~~~

sensitivity_offset 的高灵敏方向应降低阈值，界面与代码要一致。噪声估计只在 ARMED、无自身音效且低声级时缓慢更新；进入录音后冻结，避免把用户持续讲话当成环境声。若背景持续很响或反复触发，明确建议手动模式，不反复播放噪声。

这些阈值是待调参的起点。它们不是跨设备通用的人声识别算法，也不是音频声压级的物理测量。后续若加入更复杂的本地 VAD，仍需重新验证 CPU、语言/距离覆盖与自我声音抑制。

### 5.2 每一段录音的处理顺序

1. 在 ARMED 持续消费 Capture，建立带绝对采样序号的前置缓存。
2. 起听成立时，从唯一的连续采样区间复制前置音频，再从下一个采样追加新帧；不得把触发帧既放在前置缓冲又追加一遍。
3. 记录最后一个有效活动采样的位置和累计活动时长。音量在 T_on/T_off 间使用迟滞，避免状态抖动。
4. 句尾安静达到设定时长后结束检测，裁剪回最后活动位置后约 150ms；不能把全部 800ms 等待再原样播放一次。
5. 丢弃只有短碰撞声或接近全静音的片段；回到可用状态，不发任务/亲密奖励。
6. 对有效音频做边缘淡入淡出和有限增益。禁止把很小的噪声峰值无限放大；增益上限以 +6dB 为初值，输出峰值目标不超过约 -1dBFS。
7. 构造 PCM 与时间对齐的音量包络，进入 REPEATING；播放结束后统一清理。

PROCESSING 的低端机目标是 P95 ≤150ms。尽量在录音过程中增量计算包络/编码；如果最终处理过重，可分批处理或把纯数据计算移到工作线程。线程只处理私有音频数据；AudioServer、播放器和场景节点的操作留在主线程。

每次处理必须验证 session_id。若处理过程中用户切后台，计算结果只能被丢弃，不能在用户回到桌面后继续发声。

### 5.3 防止录到游戏自身声音

使用半双工交互：倾听与角色复述轮流进行。

自动模式处于 ARMED/LISTENING 时，Music 淡出并暂停。角色叫声、庆祝音效和复述先通过统一的音频占用管理暂停起听；播放结束与冷却后再恢复。轻量 UI 点击音也必须经过同一路由规则，不能绕开检测门。

REPEATING/COOLDOWN 中继续消费仍在输入的帧并丢弃，不累积任何“下一句”。冷却结束时清空检测状态和前置缓存，从新输入开始。应用后台、关麦或离开互动页面时则停止麦克风流，释放输入资源。

冷却需要考虑 AudioServer 的输出延迟估计和扬声器尾音，蓝牙设备单独验证。不能把“未检测声音”写成“麦克风物理关闭”；UI 显示“正在模仿”等实际行为状态。

## 6. 变调、口型与动画仲裁

本节的 AnimationTree / FaceController 约束面向正式动画接入。当前原型还没有动画片段或 blend shape，使用 `CharacterPresenter.gd` 直接平滑骨骼姿势；正式动画替换时应保留下方的优先级与仲裁原则，并取消重复写同一骨骼的程序姿势。

基础复述方案只在 VoicePlaybackPlayer 上设置 pitch_scale，Music/SFX 不跟着变调。1.30 倍会同时提升音高与语速；完成事件来自实际播放结束，而不是固定等待“原录音秒数”。AudioStreamPlayer.stop() 不会发自然 finished 信号，手动停止必须显式走取消路径。[播放器行为](https://docs.godotengine.org/en/4.6/classes/class_audiostreamplayer.html)

若要保持语速，在独立 VoiceOut 总线上验证 AudioEffectPitchShift，播放器 pitch_scale 保持 1.0。FFT/oversampling 会影响效果、延迟和 CPU，必须作为后续质量实验；不能把两种变调同时叠加当作默认。[AudioEffectPitchShift](https://docs.godotengine.org/en/4.6/classes/class_audioeffectpitchshift.html)

每 10–20ms 生成一个音量包络值，播放时由 AudioClock 返回对应的源音频位置。AudioClock 封装混音块间隔、输出延迟和变速；get_playback_position 已代表流内播放位置，不能再不加判断地乘一次速度。用 1.0/1.3 倍的有节奏样本核对时轴。官方时序方法以混音和输出延迟进行补偿，可作为实现依据。[音画同步说明](https://docs.godotengine.org/en/4.6/tutorials/audio/sync_with_audio.html)

包络驱动嘴部形变、下颌或已选定的发声面部组件，增加约 40ms attack / 100ms release 的平滑。声音为零时回到中性值。首版是音量驱动表现，不宣称做到了音素口型匹配。

动画职责：

- AnimationTree 作为全身姿态唯一写入通道；外部通过参数/状态转换驱动，不同时从其他模块随意 AnimationPlayer.play()。
- FaceController 管理脸部单独通道；全身动画的轨道/过滤器不能同时覆盖同一嘴部属性。
- 导入动作通过 animation_map.tres 映射逻辑标识，避免代码依赖 FBX 导入后偶然产生的名称。
- 缺必需动作时开发构建明确报错并记录，正式 P0/P1 不能悄悄用 RESET 代替完成状态。

优先级从高到低：系统暂停/失权 → 用户关闭或取消 → 录音/复述 → 正在结算的照顾动作 → 触摸反馈 → 随机待机。

录音/复述期间底部导航仍可取消当前互动并打开目标界面；普通摸头不截断语音，最多记住一个待执行轻反馈。关闭麦克风立刻取消。吃东西等短动作有明确可中断边界，不能因为等待某动画信号永久锁定角色。

## 7. 权限、前后台与设备变化

### 7.1 Android

导出预设声明 RECORD_AUDIO；运行时通过 PlatformService 请求 android.permission.RECORD_AUDIO，并处理 on_request_permissions_result 等异步结果。request_permission 返回 false 可能表示尚未授权而请求仍在进行，不能立即当成最终拒绝。权限结果以实际授权状态为准。[Godot OS 权限接口](https://docs.godotengine.org/en/4.6/classes/class_os.html#class-os-method-request-permission)

区分未请求、已授权、已拒绝/需系统设置恢复；拒绝后进入可玩的静音状态，用户再次主动开启时才提示。恢复前台重新检查权限，处理系统撤销和麦克风被其他应用占用。

Android 导出工具链按引擎文档安装并记录版本，官方当前 4.6 指南推荐 JDK 17。准备 ARM64 release 包；额外 ABI 仅在有目标设备与测试预算时加入。minSdk 与商店要求的 targetSdk 分别处理，在发行时核对目标渠道要求。[Android 导出](https://docs.godotengine.org/en/4.6/tutorials/export/exporting_for_android.html)

### 7.2 iOS

配置麦克风用途说明和本地化说明；音频会话选择支持录音与播放的类别。原生授权、扬声器/耳机路由、中断与恢复必须用 iPhone 样包验证，不直接照搬 Android 的 OS.request_permissions()。[iOS 录音设置](https://docs.godotengine.org/en/4.6/tutorials/audio/recording_with_microphone.html) · [iOS 导出属性](https://docs.godotengine.org/en/4.6/classes/class_editorexportplatformios.html)

优先验证引擎已有能力。若不能满足权限状态查询、音频路由或中断回调，PlatformService 下补一个最小原生插件，游戏层接口不变。是否需要插件是早期样包的输出结论，不预先承诺“完全无需原生代码”。

iOS 导出与签名需要 macOS/Xcode 环境；当前 Windows 工作区的成功运行不构成 iOS 验收。[iOS 导出要求](https://docs.godotengine.org/en/4.6/tutorials/export/exporting_for_ios.html)

### 7.3 生命周期统一规则

| 情况 | 立即处理 | 恢复方式 |
|---|---|---|
| 应用进入后台/锁屏 | 停止输入与播放，清理录音，保存已提交状态 | 检查权限及音频设备，重新校准 |
| 系统来电或音频焦点中断 | 取消会话，停止角色发声 | 只在前台且仍有启用意图时恢复 |
| 切换耳机/蓝牙/采样率 | 当前片段作废，释放旧缓冲 | 更新路由后重建采集 |
| 关闭设置中的语音 | 清掉当前与前置录音 | 再次主动启用才开始 |
| 进入小游戏/休息 | 语音 SUSPENDED | 退出/唤醒后按当前设置恢复 |
| 授权弹窗引起焦点变化 | 保留“等待授权”语义但不录音 | 焦点与权限都满足后进入校准 |
| 杀进程/系统回收 | 不依赖退出回调完成最后一笔交易 | 从最近有效持久化状态恢复 |

首次安装麦克风关闭。可以保存偏好的 AUTO/HOLD 模式与灵敏度，但“正在录音”不写入存档。冷启动由玩家主动开启；同一次前后台切换可在明显状态提示下恢复此前已开启的模式。

## 8. 状态、经济和保存

余额、物品拥有状态、任务奖励、亲密经验通过同一份快照提交。UI 动画只是反馈，不能由播放到 eat/happy 的某一帧来决定是否真正扣款或发钱。

App 维护单一串行事务队列；所有提交基于最近成功的 revision。PetModel 和 EconomyService 分别计算其负责字段的候选变化，再合并为同一提交；成功后一起发布，失败则一起保持旧值。不得让不同模块各自异步保存过期的整份快照，覆盖另一笔已经成功的操作。

事务流程：

~~~text
接收操作与唯一 transaction_id
→ 验证当前状态、冷却、余额、重复凭据
→ 在内存副本中计算所有变化
→ 保存新 revision
→ 成功后发布新快照并播放反馈
→ 失败则保留旧状态并允许明确重试
~~~

小型 JSON 结构示意：

~~~json
{
  "schema_version": 1,
  "revision": 17,
  "last_accounted_unix": 1790000000,
  "pet": {
    "hunger": 80.0,
    "energy": 75.0,
    "mood": 90.0,
    "friendship_xp": 84,
    "resting": false
  },
  "wallet": {"stars": 35},
  "owned_item_ids": ["starter_badge"],
  "equipped": {"badge": "starter_badge"},
  "daily": {
    "day_key": "2026-09-29",
    "task_progress": {},
    "claimed_reward_ids": [],
    "voice_xp_count": 2,
    "care_xp_count": 1,
    "minigame_xp_count": 1
  },
  "recent_transaction_ids": [],
  "settings": {
    "voice_mode": "auto",
    "sensitivity": 0.0,
    "voice_pitch": 1.3,
    "quality": "auto",
    "music_volume": 0.5,
    "sfx_volume": 0.7
  }
}
~~~

示例时间字段仅表示结构。亲密等级由经验计算，避免保存两个可能不一致的真值。物品和任务使用稳定 ID，禁止以中文显示名或数组下标作为长期存档标识。

保存策略：同目录临时文件写入 → flush/关闭 → 校验内容 → 安全替换正式文件并保留上一个有效备份。启动时校验正式、临时和备份文件，按可恢复规则选择最高有效 revision。异常中断下替换不一定是一次完整原子事务，必须测试各个中间状态；校验和用于发现损坏，不当作防作弊机制。

保存触发为奖励/购买/解锁事务、照顾状态提交、设置改变、前后台切换；时间衰减可每 30–60 秒合并写入。失败时不能只弹“保存成功”然后继续花掉未落盘的货币。

活跃时间用单调时钟累计，系统 UTC 仅用于跨启动/后台的时间差。每次从活跃转非活跃记录结算基准，恢复时只结算尚未计入的区间：

~~~text
offline_seconds = clamp(now_unix - last_accounted_unix, 0, 8 * 3600)
last_accounted_unix = max(last_accounted_unix, now_unix)
~~~

遇到时钟倒退不给负衰减、负休息或重复每日奖励；待时钟追平前暂停基于墙钟的新结算，活跃交互照常。每日奖励 ID 包含任务日和任务 ID；更改时区/系统时间不能反复领奖。离线游戏无法彻底防止用户改文件，首版重点是正确恢复和避免程序性重复结算。

## 9. 性能实现规则

角色与场景预算以产品方案为准。固定镜头下优先降低材质切换、透明覆盖面积和分辨率，结合减面控制动画/蒙皮开销。

纹理按设备与导出预设验证合适的 GPU 压缩；Android 基础档以 ES3 设备可用的格式为基线，ASTC 作为经过设备验证的选择。3D 贴图配置 mipmap，UI 小字和图标独立处理清晰度。不能仅把 4K 文件重新压成更小 PNG 就算完成内存优化。

每帧避免载入资源、重新连接信号和创建大数组。语音包络与 UI 音量条分开更新：样本分析按 20ms，UI 约 10Hz，角色视觉按绘制帧。照顾数值按低频/经过时间更新，不逐帧写存档。

48kHz、12 秒录音若暂存完整浮点立体声约 4.4MiB，PCM16 单声道约 1.1MiB；内存预算还须计算复制、环形缓存和播放器资源。尽早转单声道、复用缓冲，所有采样率下都有字节上限；不能随着多次录音积累旧 Clip。

质量档位只调整分辨率、特效、纹理/模型选择与帧率。渲染器是发行配置决策，不提供未经验证的运行中热切换。自动降档需要连续慢帧窗口与冷却，避免每帧升降导致抖动。优先保持 30FPS；60FPS 只在对应机型持续运行仍稳定时开放。

## 10. 错误处理与可观测性

开发面板包括：voice_state、session_id、采样率、RMS/阈值、录音时长、Capture 丢帧增量、当前姿态、帧时间、资源内存、保存 revision。调试开关与正式 UI 分离。

日志使用稳定事件码，例如 VOICE_NO_INPUT、VOICE_OVERFLOW、VOICE_PERMISSION_DENIED、VOICE_ROUTE_CHANGED、SAVE_CORRUPT、SAVE_WRITE_FAILED、ASSET_ANIMATION_MISSING。只记录状态与汇总指标，默认不落盘音频与个人语音内容。

| 故障 | 用户看到什么 | 程序行为 |
|---|---|---|
| 无麦克风权限 | “可以先摸摸我、陪我玩”及开启入口 | 安全退回静音玩法 |
| 输入暂不可用 | “暂时没收到声音，试试重新开启麦克风” | 有限次数重试，不忙循环 |
| 环境连续过响 | “这里有点吵，试试按住说话” | 保留手动模式，停止自动噪声循环 |
| 缓冲丢帧 | 简短提示该次没有听清 | 丢弃损坏片段、重置状态，不播放断裂音频 |
| 保存失败 | 明确提示重试 | 不确认购买/奖励已成功 |
| 动画或贴图缺失 | 开发构建可定位报告 | 阻止对应里程碑验收 |

本文的实现验收、故障注入和设备矩阵以 [开发任务与验收](IMPLEMENTATION_PLAN.md) 为准。
