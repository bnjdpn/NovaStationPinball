import SwiftUI

@main
struct NovaStationPinballApp: App {
    @State private var model: AppModel

    init() {
        // Grandfathering must read the 1.0 usage signals BEFORE any service of
        // this launch writes to UserDefaults. Stored-property default values
        // are evaluated before an initializer body, so `model` is built here,
        // after the check, and never as an inline default.
        LegacyEntitlement.migrateIfNeeded()
        _model = State(initialValue: AppModel())
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .statusBarHidden(true)
        }
    }
}
