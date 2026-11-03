import Foundation
import Sparkle

/// Wraps Sparkle's updater. Previews and offscreen renders never start it, so
/// they make no network requests. Sparkle asks people on the second launch
/// whether to check automatically; Settings can change that later.
@MainActor
final class UpdateController {
    private let controller: SPUStandardUpdaterController?

    init(enabled: Bool) {
        controller = enabled
            ? SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
            : nil
    }

    var canCheckForUpdates: Bool { controller?.updater.canCheckForUpdates ?? false }

    var checksAutomatically: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}
