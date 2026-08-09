import SwiftUI

@main
struct NovaStationPinballApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .statusBarHidden(true)
        }
    }
}
