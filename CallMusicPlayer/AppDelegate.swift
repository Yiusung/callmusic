import UIKit
import CallKit
import AVFoundation

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

        // 配置音频会话 - 使用 VoIP 模式以支持通话中混音
        configureAudioSession()

        // 注册来电通知（仅对 VoIP 推送有效，PSTN 来电由 CallKit 系统接管）
        CXCallObserver.shared.setDelegate(CallObserverDelegate.shared, queue: .main)

        return true
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            // playAndRecord 允许同时录音（麦克风）和播放
            // allowBluetooth / allowBluetoothA2DP 支持蓝牙耳机
            try session.setCategory(
                .playAndRecord,
                mode: .voiceChat,          // voiceChat 模式：启用 VoiceProcessingIO，降噪 + 回声消除
                options: [.allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker]
            )
            try session.setActive(true)
        } catch {
            print("[AppDelegate] 音频会话配置失败: \(error)")
        }
    }

    // MARK: - UISceneSession Lifecycle
    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
}
