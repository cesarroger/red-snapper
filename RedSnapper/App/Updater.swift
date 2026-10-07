import AppKit
import Sparkle

/// Sparkle auto-updates. The feed URL and public signing key live in Info.plist.
final class Updater: NSObject, SPUStandardUserDriverDelegate {
    private lazy var controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil,
                                                               userDriverDelegate: self)

    func start() { _ = controller }

    func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }

    var automaticallyChecks: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    // MARK: - SPUStandardUserDriverDelegate

    /// A menu bar app is never frontmost, so a scheduled update alert would open behind other
    /// windows. Opting in to "gentle reminders" lets us bring it forward ourselves.
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem,
                                                   state: SPUUserUpdateState) {
        if handleShowingUpdate && !state.userInitiated {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
