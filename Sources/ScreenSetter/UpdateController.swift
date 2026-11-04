import Foundation
import Observation
import Sparkle

/// Wraps Sparkle's updater. Previews and offscreen renders never start it, so
/// they make no network requests. Sparkle asks people on the second launch
/// whether to check automatically; Settings can change that later.
@MainActor
@Observable
final class UpdateController: NSObject, SPUUpdaterDelegate {
    @ObservationIgnored private var controller: SPUStandardUpdaterController?

    /// When Sparkle last finished checking, from this or an earlier launch.
    private(set) var lastCheckDate: Date?
    /// The version found by the last check, if it is newer than this one.
    private(set) var availableVersion: String?
    private(set) var checksAutomaticallyValue = false

    init(enabled: Bool) {
        super.init()
        guard enabled else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
        lastCheckDate = controller?.updater.lastUpdateCheckDate
        checksAutomaticallyValue = controller?.updater.automaticallyChecksForUpdates ?? false
    }

    var canCheckForUpdates: Bool { controller?.updater.canCheckForUpdates ?? false }

    var checksAutomatically: Bool {
        get { checksAutomaticallyValue }
        set {
            controller?.updater.automaticallyChecksForUpdates = newValue
            checksAutomaticallyValue = controller?.updater.automaticallyChecksForUpdates ?? false
        }
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    // MARK: SPUUpdaterDelegate (Sparkle calls these on the main thread)

    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = item.displayVersionString
        MainActor.assumeIsolated { availableVersion = version }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        MainActor.assumeIsolated { availableVersion = nil }
    }

    nonisolated func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        MainActor.assumeIsolated {
            lastCheckDate = updater.lastUpdateCheckDate
            checksAutomaticallyValue = updater.automaticallyChecksForUpdates
        }
    }
}
