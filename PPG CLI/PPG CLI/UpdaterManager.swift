import AppKit
import Sparkle

final class UpdaterManager {
    static let shared = UpdaterManager()

    let updaterController: SPUStandardUpdaterController

    private init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func wireMenuItem(_ menuItem: NSMenuItem) {
        menuItem.target = updaterController
        menuItem.action = #selector(SPUStandardUpdaterController.checkForUpdates(_:))
    }
}
