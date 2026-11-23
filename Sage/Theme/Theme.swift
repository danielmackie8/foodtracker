import SwiftUI
import UIKit
import CoreText

/// "Sage Graphite" design tokens.
enum Theme {
    static let background = Color(hex: 0xF6F3EE)
    static let card = Color(hex: 0xFBF9F5)
    static let border = Color(hex: 0xE7E1D6)
    static let text = Color(hex: 0x1E2A23)
    static let muted = Color(hex: 0x5F6A63)
    static let track = Color(hex: 0xE7E1D6)

    static let accent = Color(hex: 0x2F5D46)   // also protein
    static let carbs = Color(hex: 0xB9823A)
    static let fat = Color(hex: 0x94658A)
    static let over = Color(hex: 0xB9823A)

    static let softAccent = Color(hex: 0x9DB5A6) // past-day bars
    static let chip = Color(hex: 0xEFEAE1)       // unselected toggles
    static let dashed = Color(hex: 0xDCD4C6)
    static let disabledCTA = Color(hex: 0xA9B8AE)
    static let switchOn = Color(hex: 0x34A853)

    static let cardRadius: CGFloat = 22
    static let pagePadding: CGFloat = 16
    static let gap: CGFloat = 12
    static let minTouch: CGFloat = 44
    static let tabBarHeight: CGFloat = 50   // + home-indicator safe area ≈ 84 pt
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
        nav.backgroundColor = UIColor(Theme.background)
        nav.titleTextAttributes = [.font: uiFont(17, .bold), .foregroundColor: UIColor(Theme.text)]
        nav.largeTitleTextAttributes = [.font: uiFont(30, .bold), .foregroundColor: UIColor(Theme.text)]
        let button = UIBarButtonItemAppearance()
        button.normal.titleTextAttributes = [.font: uiFont(16, .semibold), .foregroundColor: UIColor(Theme.accent)]
        nav.buttonAppearance = button
        nav.backButtonAppearance = button
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
        UINavigationBar.appearance().tintColor = UIColor(Theme.accent)
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
            .foregroundStyle(filled ? Color.white : Theme.text)
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
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(enabled ? color : Theme.disabledCTA, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

extension Theme {
    static let danger = Color(hex: 0xB3261E)
}
