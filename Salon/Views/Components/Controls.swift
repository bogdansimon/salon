import SalonCore
import SwiftUI

/// The card's toolbar buttons: label buttons ("Next", "Save") and icon buttons.
struct ToolbarButtonStyle: ButtonStyle {
    var tint: Color = Theme.Palette.ink

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typeface.body)
            .foregroundStyle(tint)
            .padding(.horizontal, Theme.Space.labelLines)
            .frame(minWidth: Theme.Layout.toolbarButton, minHeight: Theme.Layout.toolbarButton)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.button)
                    .fill(Theme.Palette.ink.opacity(configuration.isPressed ? 0.10 : 0))
            }
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.button))
            .modifier(HoverHighlight())
    }
}

private struct HoverHighlight: ViewModifier {
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.button).fill(Theme.Palette.ink.opacity(hovering ? 0.06 : 0))
            }
            .onHover { hovering = $0 }
    }
}

/// Healthy / Degraded / Failing, with shape as well as colour (filled dot, half dot, crossed ring).
struct HealthBadge: View {
    var status: SourceHealth.Status
    var enabled = true

    var body: some View {
        HStack(spacing: Theme.Space.iconLabel + 2) {
            symbol
            Text(label).font(Theme.Typeface.metadata)
        }
        .foregroundStyle(color)
        .accessibilityElement(children: .combine)
    }

    private var label: String {
        guard enabled else { return "Off" }
        switch status {
        case .healthy: return "Healthy"
        case .degraded: return "Degraded"
        case .failing: return "Failing"
        case .unknown: return "Not checked"
        }
    }

    private var color: Color {
        guard enabled else { return Theme.Palette.ink3 }
        switch status {
        case .healthy: return Theme.Palette.healthOK
        case .degraded: return Theme.Palette.healthWarn
        case .failing: return Theme.Palette.healthBad
        case .unknown: return Theme.Palette.ink3
        }
    }

    @ViewBuilder private var symbol: some View {
        switch (enabled, status) {
        case (false, _), (true, .unknown): Image(systemName: "circle").imageScale(.small)
        case (true, .healthy): Image(systemName: "circle.fill").imageScale(.small)
        case (true, .degraded): Image(systemName: "circle.lefthalf.filled").imageScale(.small)
        case (true, .failing): Image(systemName: "xmark.circle").imageScale(.small)
        }
    }
}

/// "8 November" (today), "Hung 7 November", "Hung 7 November 2025" (an earlier year).
enum DateText {
    static func hung(_ date: Date, now: Date = Date()) -> String {
        let day = dayMonth(date, now: now)
        return Calendar.current.isDate(date, inSameDayAs: now) ? day : "Hung \(day)"
    }

    static func kept(_ date: Date, now: Date = Date()) -> String {
        "Saved on " + dayMonth(date, now: now)
    }

    /// "today, 09:00", "tomorrow, 09:00" or "Wednesday 2 December, 09:00".
    static func nextChange(_ date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDate(date, inSameDayAs: now) { return "today, \(time)" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return "tomorrow, \(time)"
        }
        return date.formatted(.dateTime.weekday(.wide).day().month(.wide)) + ", " + time
    }

    /// The year only when it isn't this year's.
    private static func dayMonth(_ date: Date, now: Date) -> String {
        let sameYear = Calendar.current.isDate(date, equalTo: now, toGranularity: .year)
        return sameYear ? date.formatted(.dateTime.day().month(.wide)) : date.formatted(.dateTime.day().month(.wide).year())
    }

    static func lastFetch(_ date: Date?) -> String {
        guard let date else { return "never fetched" }
        let time = date.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDateInToday(date) { return "Last fetch today, \(time)" }
        if Calendar.current.isDateInYesterday(date) { return "Last fetch yesterday, \(time)" }
        return "Last fetch " + date.formatted(.dateTime.day().month(.wide)) + ", \(time)"
    }
}

// MARK: Hover tips

extension EnvironmentValues {
    /// True inside the menu-bar popover, where macOS doesn't show `.help` tooltips
    /// (they only appear in regular windows), so the card draws its own.
    @Entry var drawsHoverTips = false
}

enum HoverTipPlacement {
    /// Above the control, lined up with its leading or trailing edge so it stays on screen.
    case above(HorizontalAlignment)
    /// Over the bottom of the control (for the image at the top of the card).
    case insideBottom
}

extension View {
    /// A tooltip: native `.help` in windows, a drawn one in the popover.
    func hoverTip(_ text: String, _ placement: HoverTipPlacement = .above(.leading)) -> some View {
        modifier(HoverTip(text: text, placement: placement))
    }
}

private struct HoverTip: ViewModifier {
    var text: String
    var placement: HoverTipPlacement
    @Environment(\.drawsHoverTips) private var drawn
    @State private var showing = false
    @State private var pending: Task<Void, Never>?

    func body(content: Content) -> some View {
        if drawn {
            content
                .onHover { hovering in
                    pending?.cancel()
                    guard hovering else { showing = false; return }
                    pending = Task {
                        try? await Task.sleep(for: .milliseconds(700)) // about the system tooltip delay
                        if !Task.isCancelled { showing = true }
                    }
                }
                .simultaneousGesture(TapGesture().onEnded { pending?.cancel(); showing = false })
                .overlay(alignment: .top) {
                    if showing, case .above(let horizontal) = placement {
                        // A zero-height strip along the control's top edge; the tip hangs
                        // from it upwards, so it never covers the control.
                        Color.clear
                            .frame(maxWidth: .infinity, maxHeight: 0)
                            .overlay(alignment: Alignment(horizontal: horizontal, vertical: .bottom)) {
                                tip.padding(.bottom, 6)
                            }
                            .transition(.opacity)
                    }
                }
                .overlay(alignment: .bottom) {
                    if showing, case .insideBottom = placement {
                        tip.padding(.bottom, 8).transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: 0.12), value: showing)
                .accessibilityHint(text)
        } else {
            content.help(text)
        }
    }

    private var tip: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(Theme.Palette.ink)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.Palette.rule, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.25), radius: 4, y: 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
