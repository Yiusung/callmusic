# CallMusicPlayer - 来电音乐播放器

## 项目说明

本项目是一个 **仅供个人测试使用** 的 iOS 应用，功能：
- 来电接通后自动在通话音频流中混入所选音乐，**通话双方均可听到**
- 支持暂停/继续、进度拖拽、麦克风静音、单曲循环
- 支持 MP3 / M4A / WAV / AIFF / CAF / 语音备忘录（.m4a）等格式

---

## 技术原理

```
用户音乐文件
     │
     ▼
AVAudioPlayerNode
     │
     ▼
AVAudioUnitTimePitch（变速保持音调，可选）
     │
     ▼
AVAudioEngine.mainMixerNode
     │
     ▼  AVAudioSession.mode = .voiceChat
     │  （激活 VoiceProcessingIO AudioUnit）
     ▼
通话音频路径 ← 系统电话音频栈
     │
     ▼
对方听到音乐
```

**关键：** `AVAudioSession.mode = .voiceChat` 会激活苹果的 `kAudioUnitSubType_VoiceProcessingIO`，这是系统通话所使用的底层 AudioUnit。当我们的 AVAudioEngine 在此模式下运行时，其输出自然路由到通话音频流中，使对方能听到。

**麦克风静音：** 在 `inputNode` 上安装 tap，当静音开关打开时将缓冲数据清零，替代真实麦克风输入。

---

## 项目结构

```
CallMusicPlayer/
├── CallMusicPlayer.xcodeproj/
│   └── project.pbxproj
└── CallMusicPlayer/
    ├── AppDelegate.swift           ← App 入口，初始化音频会话
    ├── SceneDelegate.swift         ← 窗口管理
    ├── ViewController.swift        ← 主界面 UI
    ├── AudioMixEngine.swift        ← 核心混音引擎（单例）
    ├── CallObserverDelegate.swift  ← 来电状态监听（CXCallObserver）
    ├── Info.plist                  ← 权限声明 + 后台模式
    └── CallMusicPlayer.entitlements
```

---

## 安装步骤（Mac + Xcode）

### 前提条件
- Mac 电脑，已安装 **Xcode 15+**
- Apple ID（免费即可，无需付费开发者账号）
- iPhone iOS 15.0+，通过 USB 数据线连接 Mac

### 第一步：在 Mac 上打开项目

1. 将整个 `CallMusicPlayer/` 文件夹复制到 Mac
2. 双击 `CallMusicPlayer.xcodeproj` 用 Xcode 打开

### 第二步：配置签名

1. 在 Xcode 左侧导航栏点击项目根节点 **CallMusicPlayer**
2. 选择 **TARGETS → CallMusicPlayer → Signing & Capabilities**
3. **Team** 下拉选择你自己的 Apple ID（首次需要在 Xcode → Settings → Accounts 中添加）
4. **Bundle Identifier** 改为唯一值，如 `com.你的名字.callmusicplayer`

### 第三步：配置后台权限（重要！）

在 **Signing & Capabilities** 页面：
1. 点击左上角 **+ Capability**
2. 搜索并添加 **Background Modes**
3. 勾选：
   - ✅ **Audio, AirPlay, and Picture in Picture**
   - ✅ **Voice over IP**

### 第四步：安装到 iPhone

1. 连接 iPhone，在 Xcode 顶部 scheme 栏选择你的设备
2. 点击 **▶ Run（Command+R）**
3. 首次运行会提示在手机上信任开发者证书：
   - iPhone → **设置 → 通用 → VPN与设备管理**
   - 找到你的 Apple ID → **信任**

### 第五步：授权麦克风

首次打开 App，会弹出麦克风权限请求，点击**允许**。

---

## 使用方法

1. **打开 App**，点击 **「选择音乐文件」**，从文件 App 中选择音频文件
   - 支持本地存储的 MP3、M4A、语音备忘录等
   - 如果你的语音备忘录在 iCloud Drive 中，可以直接在文件 App → iCloud Drive → 语音备忘录 找到

2. **等待来电**，来电接通后 App 自动开始混音播放
   - 通话双方都能听到音乐
   - UI 显示「🎵 通话中·正在混音播放」

3. **通话中控制**：
   - **播放/暂停按钮**：暂停或继续音乐
   - **进度条**：拖动到任意位置
   - **🎤 麦克风静音按钮**（橙色激活）：静音后对方只听到音乐，听不到你说话
   - **🔁 单曲循环按钮**（绿色激活）：开启后音乐结束自动重头播放

4. **通话结束**：引擎自动停止，状态恢复待机

---

## 注意事项

| 项目 | 说明 |
|------|------|
| 适用范围 | 仅个人测试设备（Development 签名），**不可上架 App Store** |
| 电话类型 | 支持系统 PSTN 来电（运营商电话），不适用于微信/FaceTime（它们有自己的音频会话） |
| 主动拨出 | 本版本为来电自动触发，拨出也会触发 callConnected |
| 音质 | voiceChat 模式会启用 AEC（回声消除）和降噪，可能轻微影响音乐音质，这是系统限制 |
| iOS 版本 | 测试于 iOS 15-17，iOS 18 的行为待验证 |

---

## 常见问题

**Q: 对方听不到音乐**
- 确认 `AVAudioSession.mode = .voiceChat` 已生效（在通话接通 0.4 秒后设置）
- 确认后台模式已正确勾选
- 确认来电接通时 App 在前台或后台运行（不是被系统挂起）

**Q: 崩溃 / 引擎无法启动**
- 检查麦克风权限是否已授权
- 先杀进程重启 App

**Q: 语音备忘录找不到**
- 打开「文件」App → 「浏览」→「iCloud Drive」→「语音备忘录」
- 或直接在语音备忘录 App 中使用分享按钮 → 「拷贝到文件」

**Q: 免费 Apple ID 证书 7 天过期**
- 免费账号签名有效期 7 天，到期后重新连接 Mac 运行一次即可刷新
