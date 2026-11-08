import SalonCore
import SwiftUI

/// design/Main state 4: skeleton while a new work downloads. The wallpaper doesn't change until it's ready.
struct LoadingCard: View {
    var sourceName: String?
    var nextNumber: Int

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Theme.Palette.mat
                Rectangle()
                    .fill(Theme.Palette.fill)
                    .frame(width: 174, height: 192)
                    .overlay { ProgressView().controlSize(.small).accessibilityLabel("Loading") }
            }
            .frame(height: Theme.Layout.cardPlateHeight)

            VStack(alignment: .leading, spacing: Theme.Space.labelLines) {
                HStack {
                    Text(sourceName.map { "Fetching from \($0)" } ?? "Choosing a work")
                    Spacer()
                    Text("No. \(nextNumber)").monospacedDigit()
                }
                .labelCaps()
                VStack(alignment: .leading, spacing: 7) {
                    SkeletonBar(width: 132, height: 9)
                    SkeletonBar(width: 96, height: 9)
                }
                .padding(.vertical, 2)
                SkeletonBar(width: 250, height: 18)
                VStack(alignment: .leading, spacing: 7) {
                    SkeletonBar(width: 180, height: 9)
                    SkeletonBar(width: 150, height: 9)
                }
                Hairline().padding(.top, 4)
                Text("Your current wallpaper stays until the new work has fully downloaded.")
                    .font(Theme.Typeface.metadata)
                    .foregroundStyle(Theme.Palette.ink3)
                    .padding(.bottom, Theme.Space.labelLines + 2)
            }
            .padding(.horizontal, Theme.Space.card)
            .padding(.top, Theme.Space.row)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
    }
}

private struct SkeletonBar: View {
    var width: CGFloat
    var height: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 2).fill(Theme.Palette.fill).frame(width: width, height: height)
    }
}

/// design/Main state 5: a source failed. The wallpaper stays; Salon retries with backoff.
struct ErrorCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    var sourceName: String?
    var message: String
    var retryMinutes: Int?

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Theme.Palette.mat
                Rectangle()
                    .strokeBorder(Theme.Palette.rule, lineWidth: 1)
                    .frame(width: 120, height: 120)
                    .overlay {
                        Image(systemName: "photo.badge.exclamationmark")
                            .font(.system(size: 24, weight: .light))
                            .foregroundStyle(Theme.Palette.ink3)
                            .accessibilityHidden(true)
                    }
            }
            .frame(height: Theme.Layout.errorPlateHeight)

            VStack(alignment: .leading, spacing: 10) {
                Text("\(sourceName ?? "Museums") · not responding").labelCaps()
                Text("Couldn’t fetch a new work")
                    .font(Theme.Typeface.errorTitle)
                    .foregroundStyle(Theme.Palette.ink)
                Text(explanation)
                    .font(Theme.Typeface.body)
                    .lineSpacing(6)
                    .foregroundStyle(Theme.Palette.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Theme.Space.group) {
                    Button("Try Again") { model.tryAgain() }
                        .keyboardShortcut(.defaultAction)
                    Button("Use Another Museum") { model.useAnotherMuseum() }
                }
                .controlSize(.regular)
                .padding(.top, 6)
                Button("Check sources in Settings…") {
                    NSApp.activate(ignoringOtherApps: true)
                    openSettings()
                }
                .buttonStyle(.link)
                .font(Theme.Typeface.link)
                .padding(.top, 6)
                .padding(.bottom, Theme.Space.labelLines + 2)
            }
            .padding(.horizontal, Theme.Space.card)
            .padding(.top, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var explanation: String {
        let retry = retryMinutes.map { " Salon will try again in \($0) minute\($0 == 1 ? "" : "s")." } ?? ""
        return "\(message) Your wallpaper stays as it is.\(retry)"
    }
}
