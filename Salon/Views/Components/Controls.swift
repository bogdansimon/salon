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

// MARK: Tooltips

extension EnvironmentValues {
    /// True inside the menu-bar popover. macOS doesn't show tooltips there, and the
    /// workarounds broke the links' pointing hand, so the card has none.
    @Entry var showsTooltips = true
    /// True inside the menu-bar popover, where only a pushed NSCursor shows the hand.
    @Entry var inMenuBarPopover = false
}

extension View {
    /// A tooltip in windows (Collection, Settings); in the card, only a VoiceOver hint.
    func hoverTip(_ text: String) -> some View {
        modifier(HoverTip(text: text))
    }
}

private struct HoverTip: ViewModifier {
    var text: String
    @Environment(\.showsTooltips) private var showsTooltips

    func body(content: Content) -> some View {
        if showsTooltips {
            content.help(text)
        } else {
            content.accessibilityHint(text)
        }
    }
}
