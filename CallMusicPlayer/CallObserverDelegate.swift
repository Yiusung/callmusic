import Foundation
import CallKit

/// 监听系统来电状态（PSTN 真实电话）
final class CallObserverDelegate: NSObject, CXCallObserverDelegate {

    static let shared = CallObserverDelegate()

    private override init() {
        super.init()
    }

    // MARK: - CXCallObserverDelegate

    func callObserver(_ callObserver: CXCallObserver, callChanged call: CXCall) {
        let engine = AudioMixEngine.shared

        if !call.isOutgoing && !call.hasConnected && !call.hasEnded {
            // 来电振铃 - 等待接听
            print("[CallObserver] 来电振铃 UUID: \(call.uuid)")
            NotificationCenter.default.post(name: .callRinging, object: call)
        }

        if call.hasConnected && !call.hasEnded {
            // 通话已接通 - 立即开始播放音乐
            print("[CallObserver] 通话接通 UUID: \(call.uuid)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                // 短暂延迟确保 AVAudioSession 已被系统切换到通话模式
                engine.startMixingOnCall()
            }
            NotificationCenter.default.post(name: .callConnected, object: call)
        }

        if call.hasEnded {
            // 通话结束
            print("[CallObserver] 通话结束 UUID: \(call.uuid)")
            engine.stopMixing()
            NotificationCenter.default.post(name: .callEnded, object: call)
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let callRinging   = Notification.Name("CallMusicPlayer.callRinging")
    static let callConnected = Notification.Name("CallMusicPlayer.callConnected")
    static let callEnded     = Notification.Name("CallMusicPlayer.callEnded")
}

// MARK: - CXCallObserver 单例扩展

extension CXCallObserver {
    static let shared = CXCallObserver()
}
