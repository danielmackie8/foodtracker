import SwiftUI
import UIKit
import CoreText

/// "Sage Graphite" design tokens. Every colour has a light and a dark value.
enum Theme {
    static let background = dynamic(0xF6F3EE, 0x101613)
    static let card = dynamic(0xFBF9F5, 0x19211D)
    static let border = dynamic(0xE7E1D6, 0x28322D)
    static let text = dynamic(0x1E2A23, 0xE8EDE9)
    static let muted = dynamic(0x5F6A63, 0x9AA69F)
    static let track = dynamic(0xE7E1D6, 0x2A3530)

    static let accent = dynamic(0x2F5D46, 0x7DBB97)   // also protein
    static let carbs = dynamic(0xB9823A, 0xDDA55E)
    static let fat = dynamic(0x94658A, 0xC495B9)
    static let over = dynamic(0xB9823A, 0xDDA55E)
    /// Text and icons drawn on top of `accent` (buttons, the + tab).
    static let onAccent = dynamic(0xFFFFFF, 0x0F1A14)

    static let softAccent = dynamic(0x9DB5A6, 0x3F6B53) // past-day bars
    static let chip = dynamic(0xEFEAE1, 0x232D28)       // unselected toggles
    static let field = dynamic(0xFFFFFF, 0x222B26)      // text fields, chips
    static let dashed = dynamic(0xDCD4C6, 0x3A463F)
    static let disabledCTA = dynamic(0xA9B8AE, 0x3A4A41)
    static let toast = dynamic(0x1E2A23, 0x2E3A34)
    static let switchOn = Color(hex: 0x34A853)

    static let cardRadius: CGFloat = 22
    static let pagePadding: CGFloat = 16
    static let gap: CGFloat = 12
    static let minTouch: CGFloat = 44
    static let tabBarHeight: CGFloat = 50   // + home-indicator safe area ≈ 84 pt

    static func dynamicUIColor(_ light: UInt32, _ dark: UInt32) -> UIColor {
        UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) }
    }

    private static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: dynamicUIColor(light, dark))
    }
}

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

// MARK: - Manrope

enum Manrope {
    private static let files = ["Manrope-Regular", "Manrope-Medium", "Manrope-SemiBold", "Manrope-Bold", "Manrope-ExtraBold"]

    /// Registers the bundled static Manrope instances (no Info.plist UIAppFonts entry needed).
    static func register() {
        for name in files {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        configureUIKitAppearance()
    }

    static func postScriptName(_ weight: Font.Weight) -> String {
        switch weight {
        case .ultraLight, .thin, .light, .regular: return "Manrope-Regular"
        case .medium: return "Manrope-Medium"
        case .semibold: return "Manrope-SemiBold"
        case .bold: return "Manrope-Bold"
        default: return "Manrope-ExtraBold" // heavy, black
        }
    }

    static func uiFont(_ size: CGFloat, _ weight: Font.Weight) -> UIFont {
        UIFont(name: postScriptName(weight), size: size) ?? .systemFont(ofSize: size, weight: weight.uiWeight)
    }

    private static func configureUIKitAppearance() {
        let nav = UINavigationBarAppearance()
        nav.configureWithTransparentBackground()
        nav.backgroundColor = Theme.dynamicUIColor(0xF6F3EE, 0x101613)
        nav.titleTextAttributes = [.font: uiFont(17, .bold), .foregroundColor: Theme.dynamicUIColor(0x1E2A23, 0xE8EDE9)]
        nav.largeTitleTextAttributes = [.font: uiFont(30, .bold), .foregroundColor: Theme.dynamicUIColor(0x1E2A23, 0xE8EDE9)]
        let button = UIBarButtonItemAppearance()
        button.normal.titleTextAttributes = [.font: uiFont(16, .semibold), .foregroundColor: Theme.dynamicUIColor(0x2F5D46, 0x7DBB97)]
        nav.buttonAppearance = button
        nav.backButtonAppearance = button
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
        UINavigationBar.appearance().tintColor = Theme.dynamicUIColor(0x2F5D46, 0x7DBB97)
    }
}

private extension Font.Weight {
    var uiWeight: UIFont.Weight {
        switch self {
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        case .black: return .black
        default: return .regular
        }
    }
}

extension Font {
    /// Manrope at a fixed weight, scaling with Dynamic Type relative to `textStyle`.
    static func manrope(_ size: CGFloat, _ weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        if UIFont(name: Manrope.postScriptName(weight), size: size) != nil {
            return .custom(Manrope.postScriptName(weight), size: size, relativeTo: style)
        }
        return .system(size: size, weight: weight)
    }
}

// MARK: - Reusable modifiers

struct CardStyle: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View { modifier(CardStyle(padding: padding)) }

    /// Large numeric display: bold with tight tracking.
    func bigNumber(_ size: CGFloat, weight: Font.Weight = .heavy) -> some View {
        font(.manrope(size, weight, relativeTo: .largeTitle))
            .tracking(-size * 0.03)
            .monospacedDigit()
    }
}

/// Plain button style with a subtle press state, used for tappable cards and rows.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

struct CircleIconButtonStyle: ButtonStyle {
    var filled = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(filled ? Theme.onAccent : Theme.text)
            .frame(width: Theme.minTouch, height: Theme.minTouch)
            .background(filled ? Theme.accent : Theme.card, in: Circle())
            .overlay(Circle().strokeBorder(filled ? Color.clear : Theme.border, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var enabled = true
    var color: Color = Theme.accent
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.manrope(16, .bold))
            .foregroundStyle(Theme.onAccent)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(enabled ? color : Theme.disabledCTA, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

extension Theme {
    static let danger = Color(uiColor: Theme.dynamicUIColor(0xB3261E, 0xFF7B70))
}
