import SalonCore
import SwiftUI

/// A menu-bar app (LSUIElement): the popover is the main UI; History and Settings
/// open as windows on demand.
@main
struct SalonApp: App {
    @State private var model: AppModel

    init() {
        #if DEBUG
        if let output = ScreenshotMode.outputDirectory {
            let model = ScreenshotMode.model(for: output)
            _model = State(initialValue: model)
            DispatchQueue.main.async { ScreenshotMode.run(model, into: output) }
            return
        }
        #endif
        let model = AppModel()
        _model = State(initialValue: model)
        // Start scheduling at launch, not when the popover first opens.
        DispatchQueue.main.async { model.start() }
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environment(model)
        } label: {
            Image("MenuBarIcon")
                .accessibilityLabel("Salon")
        }
        .menuBarExtraStyle(.window)

        Window("Collection", id: CollectionWindow.id) {
            CollectionWindow()
                .environment(model)
        }
        .defaultSize(width: 1100, height: 720)
        .windowToolbarStyle(.unified)

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}
