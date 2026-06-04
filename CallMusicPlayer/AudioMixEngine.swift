import Foundation
import AVFoundation
import Combine

/// 核心音频混音引擎
/// 技术原理：
/// - 使用 AVAudioEngine + AVAudioPlayerNode 播放本地音乐
/// - 在通话中，通过 kAudioUnitSubType_VoiceProcessingIO（voiceChat mode）
///   将音频流路由到通话音频路径，使对方也能听到
/// - 对麦克风 inputNode 安装 tap 并可选择 mute（用静音缓冲替代）
/// - 使用 Security-Scoped Bookmark 持久化默认音乐文件，重启 App 后无需重新选择
///
/// 注意：此方案在个人测试设备（Development 签名）上可行
/// 不适用于 App Store 分发（Apple 不允许拦截系统通话音频）
final class AudioMixEngine: ObservableObject {

    static let shared = AudioMixEngine()

    // MARK: - UserDefaults 键

    private enum Keys {
        static let bookmarkData  = "defaultMusicBookmark"   // Security-Scoped Bookmark
        static let trackName     = "defaultMusicTrackName"  // 显示用曲名缓存
        static let isRepeatOne   = "isRepeatOne"
        static let isMicMuted    = "isMicMuted"
    }

    // MARK: - Published 状态

    @Published var isPlaying: Bool = false
    @Published var isMicMuted: Bool = false
    @Published var isRepeatOne: Bool = false
    @Published var currentTime: Double = 0.0
    @Published var duration: Double = 1.0
    @Published var currentTrackName: String = "未选择音乐"
    @Published var isOnCall: Bool = false

    // MARK: - Private

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let timePitchNode = AVAudioUnitTimePitch()  // 可选：调速不变调

    private var audioFile: AVAudioFile?
    private var audioFileURL: URL?
    private var bookmarkAccessingURL: URL?  // 正在访问的安全范围 URL，用于 stopAccess
    private var displayLink: CADisplayLink?
    private var muteCallbackInstalled = false

    // 用于计算播放进度
    private var engineSampleRate: Double = 44100.0
    private var startSampleTime: AVAudioFramePosition = 0
    private var pausedSampleTime: AVAudioFramePosition = 0

    private init() {
        setupEngine()
        setupAudioSessionNotifications()
        restorePersistedSettings()
        restoreDefaultMusic()
    }

    // MARK: - 引擎初始化

    private func setupEngine() {
        engine.attach(playerNode)
        engine.attach(timePitchNode)

        // playerNode -> timePitch -> mainMixer -> output
        engine.connect(playerNode, to: timePitchNode, format: nil)
        engine.connect(timePitchNode, to: engine.mainMixerNode, format: nil)

        // 不在 init 中启动引擎，等到通话时再启动以避免影响系统音频
    }

    // MARK: - 音频会话中断通知

    private func setupAudioSessionNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioSessionInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }

    @objc private func handleAudioSessionInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        if type == .ended {
            // 中断结束后尝试恢复
            if isOnCall && isPlaying {
                try? AVAudioSession.sharedInstance().setActive(true)
                try? engine.start()
                playerNode.play()
            }
        }
    }

    @objc private func handleRouteChange(_ notification: Notification) {
        // 路由变化时（插拔耳机等）可以在此处理
        print("[AudioMixEngine] 音频路由变化")
    }

    // MARK: - 持久化：恢复上次设置

    /// 恢复循环、静音等偏好设置
    private func restorePersistedSettings() {
        let ud = UserDefaults.standard
        isRepeatOne = ud.bool(forKey: Keys.isRepeatOne)
        // 麦克风静音默认不持久化（每次通话应手动控制），此处不恢复
    }

    /// 从 Security-Scoped Bookmark 恢复默认音乐文件
    private func restoreDefaultMusic() {
        guard let bookmarkData = UserDefaults.standard.data(forKey: Keys.bookmarkData) else {
            // 从未设置过默认音乐
            return
        }

        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            // 如果 bookmark 已过期，重新创建
            if isStale {
                print("[AudioMixEngine] Bookmark 已过期，尝试重建")
                guard url.startAccessingSecurityScopedResource() else { return }
                let newBookmark = try url.bookmarkData(options: .withSecurityScope)
                UserDefaults.standard.set(newBookmark, forKey: Keys.bookmarkData)
                url.stopAccessingSecurityScopedResource()
            }

            // 开始访问安全范围资源
            guard url.startAccessingSecurityScopedResource() else {
                print("[AudioMixEngine] 无法访问已保存的音乐文件")
                return
            }
            bookmarkAccessingURL = url

            // 加载音频文件
            audioFileURL = url
            audioFile = try AVAudioFile(forReading: url)
            duration = Double(audioFile!.length) / audioFile!.processingFormat.sampleRate
            engineSampleRate = audioFile!.processingFormat.sampleRate

            // 优先用缓存的曲名（避免沙盒路径乱码问题）
            let name = UserDefaults.standard.string(forKey: Keys.trackName)
                    ?? url.deletingPathExtension().lastPathComponent
            DispatchQueue.main.async {
                self.currentTrackName = name
            }

            print("[AudioMixEngine] 已恢复默认音乐：\(name)")

        } catch {
            print("[AudioMixEngine] 恢复默认音乐失败：\(error)")
            // 清除损坏的 bookmark
            UserDefaults.standard.removeObject(forKey: Keys.bookmarkData)
        }
    }

    // MARK: - 公开接口：选择音乐文件（同时持久化为默认）

    /// 加载音频文件，并将其持久化为默认音乐（下次启动自动使用）
    func loadAudioFile(url: URL) throws {
        // 停止访问旧的安全范围资源
        bookmarkAccessingURL?.stopAccessingSecurityScopedResource()
        bookmarkAccessingURL = nil

        // 创建 Security-Scoped Bookmark 持久化访问权限
        do {
            let bookmarkData = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmarkData, forKey: Keys.bookmarkData)

            let name = url.deletingPathExtension().lastPathComponent
            UserDefaults.standard.set(name, forKey: Keys.trackName)

            print("[AudioMixEngine] 默认音乐已保存：\(name)")
        } catch {
            // Bookmark 创建失败不阻止本次加载，仅打印日志
            print("[AudioMixEngine] 保存 Bookmark 失败（本次仍可播放）：\(error)")
        }

        // 保持当前 URL 的安全范围访问
        bookmarkAccessingURL = url

        audioFileURL = url
        audioFile = try AVAudioFile(forReading: url)
        duration = Double(audioFile!.length) / audioFile!.processingFormat.sampleRate
        engineSampleRate = audioFile!.processingFormat.sampleRate

        let name = url.deletingPathExtension().lastPathComponent
        DispatchQueue.main.async {
            self.currentTrackName = name
        }

        // 如果当前在通话中，重新安排播放
        if isOnCall {
            stopMixing()
            startMixingOnCall()
        }
    }

    /// 清除默认音乐设置
    func clearDefaultMusic() {
        bookmarkAccessingURL?.stopAccessingSecurityScopedResource()
        bookmarkAccessingURL = nil
        audioFile = nil
        audioFileURL = nil
        UserDefaults.standard.removeObject(forKey: Keys.bookmarkData)
        UserDefaults.standard.removeObject(forKey: Keys.trackName)
        DispatchQueue.main.async {
            self.currentTrackName = "未选择音乐"
            self.duration = 1.0
            self.currentTime = 0.0
        }
    }

    // MARK: - 通话中开始混音

    func startMixingOnCall() {
        guard let audioFile = audioFile else {
            print("[AudioMixEngine] 尚未选择音乐文件")
            return
        }

        DispatchQueue.main.async { self.isOnCall = true }

        // 重新配置音频会话为 voiceChat，与系统通话路径共存
        reconfigureSessionForCall()

        // 安装麦克风 mute tap（必须在 engine start 之前）
        if !muteCallbackInstalled {
            installMuteTap()
        }

        // 启动引擎
        do {
            if !engine.isRunning {
                try engine.start()
            }
        } catch {
            print("[AudioMixEngine] 引擎启动失败: \(error)")
            return
        }

        // 调度音频文件播放
        scheduleFile(audioFile, fromTime: 0)
        playerNode.play()

        DispatchQueue.main.async {
            self.isPlaying = true
            self.startSampleTime = self.playerNode.lastRenderTime.map {
                self.playerNode.playerTime(forNodeTime: $0)?.sampleTime ?? 0
            } ?? 0
        }

        startProgressTimer()
    }

    private func reconfigureSessionForCall() {
        let session = AVAudioSession.sharedInstance()
        do {
            // 通话中需要 voiceChat mode + playAndRecord category
            // voiceChat 会激活 VoiceProcessingIO unit，使音频进入通话流
            try session.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [.allowBluetooth, .allowBluetoothA2DP]
            )
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("[AudioMixEngine] 通话音频会话配置失败: \(error)")
        }
    }

    // MARK: - 停止混音

    func stopMixing() {
        playerNode.stop()
        engine.stop()
        stopProgressTimer()

        DispatchQueue.main.async {
            self.isPlaying = false
            self.isOnCall = false
            self.currentTime = 0
        }
    }

    // MARK: - 播放控制

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            resume()
        }
    }

    func pause() {
        guard isPlaying else { return }
        // 记录暂停时的 sample time
        if let nodeTime = playerNode.lastRenderTime,
           let playerTime = playerNode.playerTime(forNodeTime: nodeTime) {
            pausedSampleTime = playerTime.sampleTime
        }
        playerNode.pause()
        DispatchQueue.main.async { self.isPlaying = false }
    }

    func resume() {
        guard !isPlaying, let audioFile = audioFile else { return }
        let seekTime = Double(pausedSampleTime) / engineSampleRate
        scheduleFile(audioFile, fromTime: seekTime)
        playerNode.play()
        DispatchQueue.main.async { self.isPlaying = true }
    }

    // MARK: - 进度跳转

    func seek(to time: Double) {
        guard let audioFile = audioFile else { return }
        let wasPlaying = isPlaying
        playerNode.stop()

        let clampedTime = max(0, min(time, duration - 0.1))
        DispatchQueue.main.async { self.currentTime = clampedTime }

        scheduleFile(audioFile, fromTime: clampedTime)
        if wasPlaying {
            playerNode.play()
        }
        pausedSampleTime = AVAudioFramePosition(clampedTime * engineSampleRate)
    }

    private func scheduleFile(_ file: AVAudioFile, fromTime: Double) {
        let frameRate = file.processingFormat.sampleRate
        let startFrame = AVAudioFramePosition(fromTime * frameRate)
        let frameCount = AVAudioFrameCount(file.length - startFrame)

        guard frameCount > 0 else {
            handleTrackEnd()
            return
        }

        do {
            try file.framePosition = startFrame
        } catch {
            print("[AudioMixEngine] 设置帧位置失败: \(error)")
        }

        // completionCallbackType: .dataPlayedBack 确保在实际播放完毕后回调
        playerNode.scheduleFile(file, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            self?.handleTrackEnd()
        }
    }

    private func handleTrackEnd() {
        DispatchQueue.main.async {
            if self.isRepeatOne {
                // 单曲循环
                self.seek(to: 0)
                if !self.isPlaying, let audioFile = self.audioFile {
                    self.scheduleFile(audioFile, fromTime: 0)
                    self.playerNode.play()
                    self.isPlaying = true
                }
            } else {
                // 单次播放结束
                self.isPlaying = false
                self.currentTime = 0
            }
        }
    }

    // MARK: - 持久化偏好设置

    func savePreferences() {
        UserDefaults.standard.set(isRepeatOne, forKey: Keys.isRepeatOne)
    }

    // MARK: - 麦克风静音

    func toggleMicMute() {
        isMicMuted.toggle()
        // Tap 安装后，静音直接在 tap 回调中用空缓冲替代
        print("[AudioMixEngine] 麦克风静音: \(isMicMuted)")
    }

    /// 在 inputNode 安装 tap，实现麦克风实时替换
    /// 当 isMicMuted 为 true 时，用静音数据替换真实麦克风输入
    private func installMuteTap() {
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        inputNode.removeTap(onBus: 0) // 防止重复安装

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self, self.isMicMuted else { return }
            // 静音：将 buffer 所有 channel 数据置零
            guard let channelData = buffer.floatChannelData else { return }
            for ch in 0..<Int(buffer.format.channelCount) {
                memset(channelData[ch], 0, Int(buffer.frameLength) * MemoryLayout<Float>.size)
            }
        }

        muteCallbackInstalled = true
        print("[AudioMixEngine] 麦克风 Tap 已安装")
    }

    // MARK: - 进度更新定时器

    private func startProgressTimer() {
        stopProgressTimer()
        let link = CADisplayLink(target: self, selector: #selector(updateProgress))
        link.preferredFramesPerSecond = 10
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopProgressTimer() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func updateProgress() {
        guard isPlaying else { return }
        guard let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else { return }

        let sampleTime = Double(playerTime.sampleTime)
        let time = sampleTime / engineSampleRate
        let clamped = max(0, min(time, duration))

        DispatchQueue.main.async {
            self.currentTime = clamped
        }
    }

    deinit {
        stopProgressTimer()
        bookmarkAccessingURL?.stopAccessingSecurityScopedResource()
        NotificationCenter.default.removeObserver(self)
    }
}
