import SwiftUI
import Observation

@Observable final class ThemeStore {
    private static let key = "solarcast.appTheme"

    var current: AppTheme {
        didSet {
            UserDefaults.standard.set(current.rawValue, forKey: Self.key)
            AppLogger.shared.info("Settings changed: theme -> \(current.rawValue)")
            applyToWindow()
        }
    }

    var renderID: UUID = UUID()

    /// Cached resolved scheme — updated after UIKit propagation
    private var resolvedSystemScheme: ColorScheme = .dark

    init() {
        current = AppTheme(rawValue: UserDefaults.standard.string(forKey: Self.key) ?? "") ?? .system
        // Read initial system appearance
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = scene.windows.first {
            resolvedSystemScheme = window.traitCollection.userInterfaceStyle == .dark ? .dark : .light
        }
    }

    var colorScheme: ColorScheme {
        switch current {
        case .dark:   return .dark
        case .light:  return .light
        case .system: return resolvedSystemScheme
        }
    }

    func applyToWindow() {
        let style: UIUserInterfaceStyle
        switch current {
        case .system: style = .unspecified
        case .dark:   style = .dark
        case .light:  style = .light
        }
        DispatchQueue.main.async {
            // 1. Set .unspecified on window + all presented VCs
            for scene in UIApplication.shared.connectedScenes {
                guard let ws = scene as? UIWindowScene else { continue }
                for window in ws.windows {
                    window.overrideUserInterfaceStyle = style
                    var vc = window.rootViewController
                    while let v = vc {
                        v.overrideUserInterfaceStyle = style
                        vc = v.presentedViewController
                    }
                }
            }
            // 2. Wait one frame for UIKit to resolve the trait
            DispatchQueue.main.async {
                // 3. NOW read the resolved appearance
                if self.current == .system {
                    if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let window = scene.windows.first {
                        self.resolvedSystemScheme = window.traitCollection.userInterfaceStyle == .dark ? .dark : .light
                    }
                }
                // 3b. Selected-segment fill: .systemBlue in dark mode; nil
                // (UISegmentedControl's own built-in default) in light mode,
                // per direct instruction — light mode should NOT get a
                // custom override, it should look exactly as it would with
                // no appearance customization at all.
                UISegmentedControl.appearance().selectedSegmentTintColor =
                    self.colorScheme == .dark ? .systemBlue : nil
                // 4. Bump renderID to force SwiftUI re-render with correct colorScheme
                self.renderID = UUID()
            }
        }
    }

    func applyOnLaunch() {
        applyToWindow()
    }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case system, dark, light
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .system: return "System"
        case .dark:   return "Dark"
        case .light:  return "Light"
        }
    }
}
