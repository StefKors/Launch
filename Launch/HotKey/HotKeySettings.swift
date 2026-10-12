import Foundation
import Observation

/// The user's chosen shortcut, kept in `UserDefaults`.
@Observable
final class HotKeySettings {
    private(set) var shortcut: GlobalHotKey.Shortcut
    /// True while the recorder is waiting for a key; the live shortcut is
    /// released meanwhile, or pressing it would open the launcher instead.
    private(set) var isRecording = false
    /// The system refused the last registration (another app holds it).
    var registrationFailed = false

    @ObservationIgnored var onChange: () -> Void = {}

    private static let key = "globalShortcut"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode(GlobalHotKey.Shortcut.self, from: data) {
            shortcut = saved
        } else {
            shortcut = .commandSpace
        }
    }

    func setShortcut(_ new: GlobalHotKey.Shortcut) {
        shortcut = new
        UserDefaults.standard.set(try? JSONEncoder().encode(new), forKey: Self.key)
        onChange()
    }

    func setRecording(_ recording: Bool) {
        guard isRecording != recording else { return }
        isRecording = recording
        onChange()
    }
}
