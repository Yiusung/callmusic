import UIKit
import AVFoundation
import UniformTypeIdentifiers

class ViewController: UIViewController {

    // MARK: - Engine
    private let engine = AudioMixEngine.shared
    private var cancellables: [Any] = []

    // MARK: - UI Elements

    private lazy var trackNameLabel: UILabel = {
        let l = UILabel()
        l.text = "未选择音乐"
        l.font = .systemFont(ofSize: 17, weight: .semibold)
        l.textAlignment = .center
        l.textColor = .label
        l.numberOfLines = 2
        return l
    }()

    private lazy var callStatusLabel: UILabel = {
        let l = UILabel()
        l.text = "待机中"
        l.font = .systemFont(ofSize: 13)
        l.textAlignment = .center
        l.textColor = .secondaryLabel
        return l
    }()

    // 音乐封面（占位）
    private lazy var artworkView: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor.systemIndigo.withAlphaComponent(0.15)
        v.layer.cornerRadius = 16
        let img = UIImageView(image: UIImage(systemName: "music.note"))
        img.tintColor = .systemIndigo
        img.contentMode = .scaleAspectFit
        img.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(img)
        NSLayoutConstraint.activate([
            img.centerXAnchor.constraint(equalTo: v.centerXAnchor),
            img.centerYAnchor.constraint(equalTo: v.centerYAnchor),
            img.widthAnchor.constraint(equalToConstant: 80),
            img.heightAnchor.constraint(equalToConstant: 80)
        ])
        return v
    }()

    // 进度条
    private lazy var progressSlider: UISlider = {
        let s = UISlider()
        s.minimumValue = 0
        s.maximumValue = 1
        s.addTarget(self, action: #selector(sliderTouchBegan), for: .touchDown)
        s.addTarget(self, action: #selector(sliderValueChanged), for: .valueChanged)
        s.addTarget(self, action: #selector(sliderTouchEnded), for: [.touchUpInside, .touchUpOutside])
        return s
    }()

    private lazy var currentTimeLabel: UILabel = makeTimeLabel()
    private lazy var durationLabel: UILabel   = makeTimeLabel()

    private func makeTimeLabel() -> UILabel {
        let l = UILabel()
        l.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        l.textColor = .secondaryLabel
        l.text = "0:00"
        return l
    }

    // 控制按钮
    private lazy var playPauseButton: UIButton = {
        let b = UIButton(type: .system)
        b.setImage(UIImage(systemName: "play.circle.fill"), for: .normal)
        b.tintColor = .systemIndigo
        b.contentVerticalAlignment = .fill
        b.contentHorizontalAlignment = .fill
        b.addTarget(self, action: #selector(playPauseTapped), for: .touchUpInside)
        return b
    }()

    private lazy var micMuteButton: UIButton = makeToggleButton(
        iconOff: "mic.fill",
        iconOn:  "mic.slash.fill",
        color:   .systemOrange,
        action:  #selector(micMuteTapped)
    )

    private lazy var repeatButton: UIButton = makeToggleButton(
        iconOff: "repeat",
        iconOn:  "repeat.1",
        color:   .systemGreen,
        action:  #selector(repeatTapped)
    )

    private func makeToggleButton(iconOff: String, iconOn: String,
                                   color: UIColor, action: Selector) -> UIButton {
        let b = UIButton(type: .system)
        b.setImage(UIImage(systemName: iconOff), for: .normal)
        b.setImage(UIImage(systemName: iconOn),  for: .selected)
        b.tintColor = .systemGray
        b.selectedTintColor = color  // 这里用扩展属性
        b.addTarget(self, action: action, for: .touchUpInside)
        return b
    }

    private lazy var selectMusicButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = "选择默认音乐"
        config.image = UIImage(systemName: "folder.badge.plus")
        config.imagePadding = 8
        config.baseBackgroundColor = .systemIndigo
        config.cornerStyle = .large
        let b = UIButton(configuration: config)
        b.addTarget(self, action: #selector(selectMusicTapped), for: .touchUpInside)
        return b
    }()

    private lazy var clearMusicButton: UIButton = {
        var config = UIButton.Configuration.tinted()
        config.title = "清除默认"
        config.image = UIImage(systemName: "trash")
        config.imagePadding = 6
        config.baseBackgroundColor = .systemRed
        config.baseForegroundColor = .systemRed
        config.cornerStyle = .large
        let b = UIButton(configuration: config)
        b.addTarget(self, action: #selector(clearMusicTapped), for: .touchUpInside)
        return b
    }()

    // 提示卡片
    private lazy var hintCard: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor.systemYellow.withAlphaComponent(0.15)
        v.layer.cornerRadius = 12
        v.layer.borderWidth = 1
        v.layer.borderColor = UIColor.systemYellow.withAlphaComponent(0.4).cgColor

        let icon = UIImageView(image: UIImage(systemName: "info.circle"))
        icon.tintColor = .systemOrange
        icon.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = "选择一次即为默认音乐，下次打开 App 无需重新选择。接到来电后自动播放，通话双方均可听到。"
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false

        v.addSubview(icon)
        v.addSubview(label)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 12),
            icon.topAnchor.constraint(equalTo: v.topAnchor, constant: 12),
            icon.widthAnchor.constraint(equalToConstant: 20),
            icon.heightAnchor.constraint(equalToConstant: 20),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -12),
            label.topAnchor.constraint(equalTo: v.topAnchor, constant: 12),
            label.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -12)
        ])
        return v
    }()

    private var isScrubbing = false

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "来电音乐播放器"
        view.backgroundColor = .systemBackground
        setupLayout()
        setupBindings()
        requestMicPermission()
    }

    // MARK: - 布局

    private func setupLayout() {
        [artworkView, trackNameLabel, callStatusLabel, progressSlider,
         currentTimeLabel, durationLabel, playPauseButton, micMuteButton,
         repeatButton, selectMusicButton, clearMusicButton, hintCard].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }

        NSLayoutConstraint.activate([
            // 封面
            artworkView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            artworkView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 32),
            artworkView.widthAnchor.constraint(equalToConstant: 180),
            artworkView.heightAnchor.constraint(equalToConstant: 180),

            // 曲名
            trackNameLabel.topAnchor.constraint(equalTo: artworkView.bottomAnchor, constant: 20),
            trackNameLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            trackNameLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),

            // 通话状态
            callStatusLabel.topAnchor.constraint(equalTo: trackNameLabel.bottomAnchor, constant: 6),
            callStatusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            // 时间标签
            currentTimeLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            currentTimeLabel.topAnchor.constraint(equalTo: callStatusLabel.bottomAnchor, constant: 24),

            durationLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            durationLabel.centerYAnchor.constraint(equalTo: currentTimeLabel.centerYAnchor),

            // 进度条
            progressSlider.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            progressSlider.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            progressSlider.topAnchor.constraint(equalTo: currentTimeLabel.bottomAnchor, constant: 4),

            // 播放按钮（居中大按钮）
            playPauseButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            playPauseButton.topAnchor.constraint(equalTo: progressSlider.bottomAnchor, constant: 28),
            playPauseButton.widthAnchor.constraint(equalToConstant: 72),
            playPauseButton.heightAnchor.constraint(equalToConstant: 72),

            // 麦克风静音按钮（左侧）
            micMuteButton.trailingAnchor.constraint(equalTo: playPauseButton.leadingAnchor, constant: -36),
            micMuteButton.centerYAnchor.constraint(equalTo: playPauseButton.centerYAnchor),
            micMuteButton.widthAnchor.constraint(equalToConstant: 44),
            micMuteButton.heightAnchor.constraint(equalToConstant: 44),

            // 循环按钮（右侧）
            repeatButton.leadingAnchor.constraint(equalTo: playPauseButton.trailingAnchor, constant: 36),
            repeatButton.centerYAnchor.constraint(equalTo: playPauseButton.centerYAnchor),
            repeatButton.widthAnchor.constraint(equalToConstant: 44),
            repeatButton.heightAnchor.constraint(equalToConstant: 44),

            // 选择默认音乐（左按钮）
            selectMusicButton.trailingAnchor.constraint(equalTo: view.centerXAnchor, constant: -6),
            selectMusicButton.topAnchor.constraint(equalTo: playPauseButton.bottomAnchor, constant: 36),
            selectMusicButton.widthAnchor.constraint(equalToConstant: 160),
            selectMusicButton.heightAnchor.constraint(equalToConstant: 46),

            // 清除默认（右按钮）
            clearMusicButton.leadingAnchor.constraint(equalTo: view.centerXAnchor, constant: 6),
            clearMusicButton.centerYAnchor.constraint(equalTo: selectMusicButton.centerYAnchor),
            clearMusicButton.widthAnchor.constraint(equalToConstant: 100),
            clearMusicButton.heightAnchor.constraint(equalToConstant: 46),

            // 提示卡片
            hintCard.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            hintCard.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            hintCard.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20)
        ])
    }

    // MARK: - 数据绑定（KVO / Combine 替代：直接用 NotificationCenter + 轮询）

    private func setupBindings() {
        // 使用 Timer 轮询 engine 状态更新 UI（避免 Combine 依赖）
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.refreshUI()
        }

        // 通话事件
        NotificationCenter.default.addObserver(self, selector: #selector(onCallRinging),
                                                name: .callRinging, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onCallConnected),
                                                name: .callConnected, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onCallEnded),
                                                name: .callEnded, object: nil)
    }

    private func refreshUI() {
        let e = engine

        // 曲名
        trackNameLabel.text = e.currentTrackName

        // 播放/暂停图标
        let playIcon = e.isPlaying ? "pause.circle.fill" : "play.circle.fill"
        playPauseButton.setImage(UIImage(systemName: playIcon), for: .normal)

        // 麦克风静音
        micMuteButton.isSelected = e.isMicMuted
        micMuteButton.tintColor = e.isMicMuted ? .systemOrange : .systemGray

        // 循环
        repeatButton.isSelected = e.isRepeatOne
        repeatButton.tintColor = e.isRepeatOne ? .systemGreen : .systemGray

        // 进度（不在拖动时更新）
        if !isScrubbing {
            let ratio = e.duration > 0 ? Float(e.currentTime / e.duration) : 0
            progressSlider.setValue(ratio, animated: false)
        }

        // 时间标签
        currentTimeLabel.text = formatTime(e.currentTime)
        durationLabel.text    = formatTime(e.duration)
    }

    private func formatTime(_ t: Double) -> String {
        let s = Int(t)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    // MARK: - 通话通知处理

    @objc private func onCallRinging() {
        DispatchQueue.main.async {
            self.callStatusLabel.text = "📞 来电振铃中..."
            self.callStatusLabel.textColor = .systemOrange
        }
    }

    @objc private func onCallConnected() {
        DispatchQueue.main.async {
            self.callStatusLabel.text = "🎵 通话中·正在混音播放"
            self.callStatusLabel.textColor = .systemGreen
        }
    }

    @objc private func onCallEnded() {
        DispatchQueue.main.async {
            self.callStatusLabel.text = "通话结束"
            self.callStatusLabel.textColor = .secondaryLabel
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                self.callStatusLabel.text = "待机中"
            }
        }
    }

    // MARK: - 按钮动作

    @objc private func playPauseTapped() {
        engine.togglePlayPause()
    }

    @objc private func micMuteTapped() {
        engine.toggleMicMute()
    }

    @objc private func repeatTapped() {
        engine.isRepeatOne.toggle()
        engine.savePreferences()  // 循环偏好持久化
    }

    @objc private func selectMusicTapped() {
        var types: [UTType] = [.audio, .mp3]
        if let m4a = UTType("public.mpeg-4-audio") { types.append(m4a) }
        if let wav = UTType("com.microsoft.waveform-audio") { types.append(wav) }
        if let aiff = UTType("public.aiff-audio") { types.append(aiff) }
        if let caf = UTType("com.apple.coreaudio-format") { types.append(caf) }

        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }

    @objc private func clearMusicTapped() {
        let alert = UIAlertController(title: "清除默认音乐",
                                      message: "确定要清除已设置的默认音乐吗？下次来电将不会自动播放。",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "清除", style: .destructive) { [weak self] _ in
            self?.engine.clearDefaultMusic()
            self?.showToast("✅ 默认音乐已清除")
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, animated: true)
    }

    // MARK: - Slider

    @objc private func sliderTouchBegan() {
        isScrubbing = true
    }

    @objc private func sliderValueChanged() {
        let time = Double(progressSlider.value) * engine.duration
        currentTimeLabel.text = formatTime(time)
    }

    @objc private func sliderTouchEnded() {
        let time = Double(progressSlider.value) * engine.duration
        engine.seek(to: time)
        isScrubbing = false
    }

    // MARK: - 权限

    private func requestMicPermission() {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            if !granted {
                DispatchQueue.main.async {
                    let alert = UIAlertController(
                        title: "需要麦克风权限",
                        message: "请在设置中允许本应用访问麦克风，以便在通话中静音功能正常工作。",
                        preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "前往设置", style: .default) { _ in
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    })
                    alert.addAction(UIAlertAction(title: "忽略", style: .cancel))
                    self.present(alert, animated: true)
                }
            }
        }
    }
}

// MARK: - UIDocumentPickerDelegate

extension ViewController: UIDocumentPickerDelegate {

    func documentPicker(_ controller: UIDocumentPickerViewController,
                        didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }

        // 必须先开启安全范围访问，才能创建 Bookmark（在 loadAudioFile 内部完成持久化）
        // 注意：Engine 的 loadAudioFile 会接管后续的 startAccess/stopAccess 生命周期
        let secured = url.startAccessingSecurityScopedResource()

        do {
            try engine.loadAudioFile(url: url)
            showToast("✅ 已设为默认：\(url.lastPathComponent)")
        } catch {
            showToast("❌ 无法加载音频：\(error.localizedDescription)")
        }

        // loadAudioFile 内部已通过 Bookmark 持久化访问权
        // 对于当前会话，engine 持有 bookmarkAccessingURL 负责 stopAccess
        // 此处只需停止本次直接访问（engine 通过 bookmark 重新 resolve 后会独立 startAccess）
        if secured { url.stopAccessingSecurityScopedResource() }
    }

    private func showToast(_ msg: String) {
        DispatchQueue.main.async {
            let label = UILabel()
            label.text = msg
            label.font = .systemFont(ofSize: 14)
            label.textColor = .white
            label.backgroundColor = UIColor.black.withAlphaComponent(0.75)
            label.textAlignment = .center
            label.numberOfLines = 2
            label.layer.cornerRadius = 10
            label.clipsToBounds = true
            label.translatesAutoresizingMaskIntoConstraints = false

            self.view.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
                label.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor, constant: -80),
                label.widthAnchor.constraint(lessThanOrEqualToConstant: 300),
                label.heightAnchor.constraint(greaterThanOrEqualToConstant: 40)
            ])

            label.alpha = 0
            UIView.animate(withDuration: 0.3) { label.alpha = 1 }
            UIView.animate(withDuration: 0.3, delay: 2.0) {
                label.alpha = 0
            } completion: { _ in label.removeFromSuperview() }
        }
    }
}
