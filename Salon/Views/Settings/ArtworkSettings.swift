import SalonCore
import SwiftUI

struct ArtworkSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Selection") {
                SettingRow(title: "Include", help: "Paintings only, unless you add more.") {
                    HStack(spacing: Theme.Space.row) {
                        ForEach(ObjectType.allCases, id: \.self) { type in
                            Toggle(type.displayName, isOn: typeBinding(type)).toggleStyle(.checkbox)
                        }
                    }
                }
                Toggle(isOn: $model.settings.highlightsOnly) {
                    Text("Highlights only")
                    Text("Only a museum’s best-known works. The Rijksmuseum doesn’t mark these, so it ignores this setting.")
                }
            }

            Section("Framing") {
                SettingRow(title: "Show", help: fitHelp) {
                    Picker("", selection: $model.settings.workFit) {
                        ForEach(WorkFit.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
                Group {
                    SettingRow(title: "Background", help: backgroundHelp) {
                        Picker("", selection: matKind) {
                            Text("Auto").tag(MatKind.auto)
                            Text("Neutral").tag(MatKind.neutral)
                            Text("Custom").tag(MatKind.custom)
                        }
                        .labelsHidden()
                        .pickerStyle(.radioGroup)
                        .horizontalRadioGroupLayout()
                    }
                    if case .custom = model.settings.matStyle {
                        ColorPicker("Custom background", selection: customColor, supportsOpacity: false)
                    }
                    SettingRow(title: "Margin") {
                        Picker("", selection: $model.settings.matMargin) {
                            ForEach(MatMargin.allCases, id: \.self) { Text($0.displayName).tag($0) }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .fixedSize()
                    }
                    Toggle(isOn: $model.settings.avoidMenuBar) {
                        Text("Keep clear of the menu bar")
                        Text("Otherwise the menu bar sits over the top of the work.")
                    }
                    Toggle(isOn: $model.settings.avoidDock) {
                        Text("Keep clear of the Dock")
                        Text("Otherwise the Dock sits over the bottom of the work. Best left off if the Dock hides automatically.")
                    }
                }
                .disabled(fills)
                .opacity(fills ? 0.45 : 1)
                MatPreview()
            }
        }
        .settingsForm()
    }

    /// "Fill screen": the mat options don't apply (a too-small work uses the default mat).
    private var fills: Bool { model.settings.workFit == .fill }

    private var fitHelp: String {
        switch model.settings.workFit {
        case .whole: "The whole work on a background, never cropped."
        case .auto: "Fills the screen when that crops 12% or less; otherwise the whole work on a background."
        case .fill: "Fills the screen, cropping the edges. A work too small to fill it sharply goes on the default background."
        }
    }

    private var backgroundHelp: String {
        let what = "The area around the painting. "
        switch model.settings.matStyle {
        case .auto: return what + "A quiet tone picked from the painting’s edges: dark for dark works, light for light ones."
        case .neutral: return what + "Dark grey in Dark mode, warm off-white in Light mode."
        case .custom: return what + "One colour of your choice for every work."
        }
    }

    private func typeBinding(_ type: ObjectType) -> Binding<Bool> {
        Binding {
            model.settings.objectTypes.contains(type)
        } set: { on in
            var types = model.settings.objectTypes
            if on { types.insert(type) } else { types.remove(type) }
            if !types.isEmpty { model.settings.objectTypes = types } // at least one stays selected
        }
    }

    enum MatKind: Hashable { case auto, neutral, custom }

    private var matKind: Binding<MatKind> {
        Binding {
            switch model.settings.matStyle {
            case .auto: .auto
            case .neutral: .neutral
            case .custom: .custom
            }
        } set: { kind in
            switch kind {
            case .auto: model.settings.matStyle = .auto
            case .neutral: model.settings.matStyle = .neutral
            case .custom:
                if case .custom = model.settings.matStyle { return }
                model.settings.matStyle = .custom(PaletteRules.neutralLight)
            }
        }
    }

    private var customColor: Binding<Color> {
        Binding {
            if case .custom(let rgb) = model.settings.matStyle { return Color(nsColor: NSColor(rgb: rgb)) }
            return Color(nsColor: NSColor(rgb: PaletteRules.neutralLight))
        } set: { color in
            guard let srgb = NSColor(color).usingColorSpace(.sRGB) else { return }
            model.settings.matStyle = .custom(SRGBColor(red: srgb.redComponent, green: srgb.greenComponent, blue: srgb.blueComponent))
        }
    }
}

/// A small live render of the current work with the current mat settings.
struct MatPreview: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @State private var preview: NSImage?

    private static let size = PixelSize(width: 480, height: 300) // 16:10

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.group) {
            Group {
                if let preview {
                    Image(nsImage: preview).resizable().aspectRatio(16 / 10, contentMode: .fit)
                } else {
                    Rectangle().fill(Theme.Palette.fill).aspectRatio(16 / 10, contentMode: .fit)
                }
            }
            .frame(maxWidth: 360)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.field))
            .accessibilityLabel("Wallpaper preview")
            if let entry = model.current {
                Text("Preview · \(entry.artwork.title)").labelCaps()
            }
        }
        .frame(maxWidth: .infinity)
        .task(id: renderKey) { await render() }
    }

    private var renderKey: String {
        "\(model.current?.id.uuidString ?? "")|\(model.settings.matStyle)|\(model.settings.matMargin)|\(model.settings.avoidDock)|\(model.settings.avoidMenuBar)|\(model.settings.workFit)|\(colorScheme)"
    }

    private func render() async {
        guard let entry = model.current, let file = model.imageFile(for: entry) else { preview = nil; return }
        let settings = model.settings, palette = entry.palette ?? .fallback, dark = colorScheme == .dark, size = Self.size
        let image = await Task.detached(priority: .userInitiated) { () -> CGImage? in
            guard let source = ImageInspector.image(at: file, maxPixelSize: 900) else { return nil }
            return WallpaperService.preview(of: source, size: size, palette: palette, settings: settings, dark: dark)
        }.value
        preview = image.map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
    }
}
