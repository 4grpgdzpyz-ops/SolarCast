import SwiftUI
extension Color {
    init(hex: String) {
        let c = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var rgb: UInt64 = 0
        Scanner(string: c).scanHexInt64(&rgb)
        self.init(red: Double((rgb >> 16) & 0xFF) / 255,
                  green: Double((rgb >> 8) & 0xFF) / 255,
                  blue: Double(rgb & 0xFF) / 255)
    }
    static let scAccent       = Color(hex: "#0EA5E9")
    static let scGreen        = Color(hex: "#10B981")
    static let scOrange       = Color(hex: "#F59E0B")
    static let scRed          = Color(hex: "#EF4444")
    static let scBackground   = Color(uiColor: .init(dynamicProvider: { t in
        t.userInterfaceStyle == .dark ? UIColor(hex: "#0F172A") : UIColor(hex: "#F1F5F9") }))
    static let scCard         = Color(uiColor: .init(dynamicProvider: { t in
        t.userInterfaceStyle == .dark ? UIColor(hex: "#1E293B") : UIColor(hex: "#FFFFFF") }))
    static let scBorder       = Color(uiColor: .init(dynamicProvider: { t in
        t.userInterfaceStyle == .dark ? UIColor(hex: "#334155") : UIColor(hex: "#E2E8F0") }))
    static let scText         = Color(uiColor: .init(dynamicProvider: { t in
        t.userInterfaceStyle == .dark ? UIColor(hex: "#F1F5F9") : UIColor(hex: "#0F172A") }))
    static let scMuted        = Color(uiColor: .init(dynamicProvider: { t in
        t.userInterfaceStyle == .dark ? UIColor(hex: "#64748B") : UIColor(hex: "#94A3B8") }))
    static let scSurfaceMuted = Color(uiColor: .init(dynamicProvider: { t in
        t.userInterfaceStyle == .dark ? UIColor(hex: "#0F172A") : UIColor(hex: "#F1F5F9") }))
    static let scGridLine     = Color(uiColor: .init(dynamicProvider: { t in
        t.userInterfaceStyle == .dark ? UIColor(hex: "#1E3A5F") : UIColor(hex: "#E2E8F0") }))
    /// Sunrise glyph on the chart's X axis.
    static let scAmber        = Color(uiColor: .init(dynamicProvider: { t in
        t.userInterfaceStyle == .dark ? UIColor(hex: "#FBBF24") : UIColor(hex: "#F59E0B") }))
    /// Sunset glyph on the chart's X axis.
    static let scMoon         = Color(uiColor: .init(dynamicProvider: { t in
        t.userInterfaceStyle == .dark ? UIColor(hex: "#FDE68A") : UIColor(hex: "#EAB308") }))
}
extension UIColor {
    convenience init(hex: String) {
        let c = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var rgb: UInt64 = 0
        Scanner(string: c).scanHexInt64(&rgb)
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255,
                  green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255,
                  alpha: 1)
    }
}
