import SwiftUI
import UIKit

/// Applies the design tokens to the UIKit-backed chrome SwiftUI uses (navigation bars, tab bars,
/// segmented pickers, lists). Called once at launch.
enum NoahAppearance {
    static func apply() {
        let text = UIColor(NoahColor.text)
        let secondary = UIColor(NoahColor.textSecondary)
        let accent = UIColor(NoahColor.accent)

        func font(_ name: String, _ size: CGFloat, _ style: UIFont.TextStyle) -> UIFont {
            let base = UIFont(name: name, size: size) ?? .preferredFont(forTextStyle: style)
            return UIFontMetrics(forTextStyle: style).scaledFont(for: base)
        }

        // Navigation bar
        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = UIColor(NoahColor.ground)
        nav.shadowColor = .clear
        nav.titleTextAttributes = [.foregroundColor: text, .font: font(NoahFontFamily.bodySemibold, 17, .headline)]
        nav.largeTitleTextAttributes = [.foregroundColor: text, .font: font(NoahFontFamily.display, 34, .largeTitle)]
        let buttonAppearance = UIBarButtonItemAppearance()
        buttonAppearance.normal.titleTextAttributes = [.foregroundColor: accent, .font: font(NoahFontFamily.body, 17, .body)]
        nav.buttonAppearance = buttonAppearance
        nav.doneButtonAppearance = buttonAppearance
        nav.backButtonAppearance = buttonAppearance
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
        UINavigationBar.appearance().tintColor = accent

        // Tab bar
        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = UIColor(NoahColor.surfaceDeep)
        tab.shadowColor = UIColor(NoahColor.divider)
        for item in [tab.stackedLayoutAppearance, tab.inlineLayoutAppearance, tab.compactInlineLayoutAppearance] {
            item.normal.iconColor = secondary
            item.normal.titleTextAttributes = [.foregroundColor: secondary, .font: font(NoahFontFamily.body, 11, .caption2)]
            item.selected.iconColor = accent
            item.selected.titleTextAttributes = [.foregroundColor: accent, .font: font(NoahFontFamily.bodySemibold, 11, .caption2)]
        }
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab

        // Segmented control
        let segmented = UISegmentedControl.appearance()
        segmented.selectedSegmentTintColor = accent
        segmented.backgroundColor = UIColor(NoahColor.surface)
        segmented.setTitleTextAttributes([.foregroundColor: UIColor(NoahColor.onAccent), .font: font(NoahFontFamily.bodySemibold, 15, .subheadline)], for: .selected)
        segmented.setTitleTextAttributes([.foregroundColor: text, .font: font(NoahFontFamily.body, 15, .subheadline)], for: .normal)

        // Lists / forms
        UITableView.appearance().backgroundColor = .clear
        UISwitch.appearance().onTintColor = accent
        UIPageControl.appearance().currentPageIndicatorTintColor = accent
        UIPageControl.appearance().pageIndicatorTintColor = UIColor(NoahColor.border)
        UITextField.appearance().tintColor = accent
        UITextView.appearance().tintColor = accent
    }
}

// MARK: - Screen scaffolding

extension View {
    /// Fills the whole screen (behind safe areas too) with an opaque ground colour.
    func noahScreenBackground(_ color: Color = NoahColor.ground) -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(color.ignoresSafeArea())
    }

    /// For screens pushed onto a NavigationStack: opaque full-bleed background plus a soft shade
    /// just outside the leading edge. The shade is off-screen at rest and only visible while the
    /// screen slides in, so the edge stays readable on dark-on-dark.
    func noahPushedScreen() -> some View {
        noahScreenBackground()
            .overlay(alignment: .leading) {
                LinearGradient(colors: [.clear, NoahColor.pushEdgeShade], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 18)
                    .offset(x: -18)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
    }

    /// Hides a screen while another one is pushed on top of it, so its text can't peek out next to
    /// the incoming screen during the slide (both share the same ground colour). `ownDepth` is this
    /// screen's position in the stack (root = 0), `stackDepth` the current number of pushed screens.
    func hidesWhileCovered(ownDepth: Int, stackDepth: Int) -> some View {
        modifier(HidesWhileCovered(ownDepth: ownDepth, stackDepth: stackDepth))
    }

    /// Limits content to a readable width (iPad) and centres it.
    func noahReadableWidth() -> some View {
        frame(maxWidth: NoahSize.readableWidth).frame(maxWidth: .infinity)
    }

    /// Styling for SwiftUI `Form`/`List` so they match the design system.
    func noahFormStyle() -> some View {
        scrollContentBackground(.hidden)
            .noahScreenBackground()
            .font(NoahFont.bodyText)
            .foregroundColor(NoahColor.text)
            .tint(NoahColor.accent)
    }

    /// Row styling inside a `Form`/`List`.
    func noahRowBackground() -> some View {
        listRowBackground(NoahColor.surface)
            .listRowSeparatorTint(NoahColor.divider)
    }
}

struct HidesWhileCovered: ViewModifier {
    let ownDepth: Int
    let stackDepth: Int

    @State private var hidden = false
    @State private var lastDepth: Int?
    @State private var revealTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .opacity(hidden ? 0 : 1)
            // Only the content fades: the ground stays, so the navigation container's own
            // (black) backdrop never shows next to the incoming screen.
            .background(NoahColor.ground.ignoresSafeArea())
            .onAppear { lastDepth = stackDepth }
            .onChange(of: stackDepth) { newDepth in
                let oldDepth = lastDepth ?? ownDepth
                lastDepth = newDepth
                if oldDepth <= ownDepth, newDepth > ownDepth {
                    // Something was pushed on top of us: fade out for the slide, then restore
                    // (we are fully covered by then, and visible again for a swipe back).
                    withAnimation(.easeOut(duration: 0.08)) { hidden = true }
                    revealTask?.cancel()
                    revealTask = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 700_000_000)
                        if !Task.isCancelled { hidden = false }
                    }
                } else if newDepth <= ownDepth, hidden {
                    revealTask?.cancel()
                    withAnimation(.easeOut(duration: 0.15)) { hidden = false }
                }
            }
    }
}

/// A vertically scrolling screen with the standard margins and readable width.
struct NoahScrollScreen<Content: View>: View {
    var spacing: CGFloat = NoahSpacing.l
    var background: Color = NoahColor.ground
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: spacing) {
                content()
            }
            .padding(.horizontal, NoahSpacing.screen)
            .padding(.vertical, NoahSpacing.m)
            .noahReadableWidth()
        }
        .noahScreenBackground(background)
    }
}

// MARK: - Dynamic Type helpers

/// HStack that becomes a VStack at accessibility text sizes, so icons never squeeze words apart.
struct AdaptiveStack<Content: View>: View {
    var horizontalAlignment: HorizontalAlignment = .leading
    var verticalAlignment: VerticalAlignment = .top
    var spacing: CGFloat = NoahSpacing.s
    @ViewBuilder var content: () -> Content

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: horizontalAlignment, spacing: spacing))
            : AnyLayout(HStackLayout(alignment: verticalAlignment, spacing: spacing))
        layout { content() }
    }
}

extension View {
    /// Display titles are already large; past this size single long Dutch words
    /// ("Levensverhaal") would break mid-word. Body text keeps scaling.
    func noahTitleScaling() -> some View {
        dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    /// For segmented pickers and other compact chrome that cannot wrap.
    func noahCompactControlScaling() -> some View {
        dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    /// Same for the older person's (even larger) titles.
    func noahElderTitleScaling() -> some View {
        dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    /// Whole older-person screens built on the 22 pt elder type (sign-up, settings): beyond
    /// accessibility size 2 long Dutch words ("telefoonnummer", "Bijvoorbeeld") break mid-word on a
    /// phone. Text stays far larger than the system default.
    func noahElderScreenScaling() -> some View {
        dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }
}
