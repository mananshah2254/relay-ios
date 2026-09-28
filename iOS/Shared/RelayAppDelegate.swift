import UIKit

final class RelayAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        guard identifier == ShareUploadCoordinator.sessionIdentifier else {
            completionHandler()
            return
        }
        ShareUploadCoordinator.shared.reconnect(completion: completionHandler)
    }
}
