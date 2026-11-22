public enum PanelAppearance: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark

    public var id: Self { self }

    public var title: String {
        switch self {
        case .system: "Auto"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

public enum PanelTheme: String, CaseIterable, Identifiable, Sendable {
    case system, blue, purple, pink, red, orange, green, graphite

    public var id: Self { self }

    public var title: String {
        self == .system ? "System accent" : rawValue.capitalized
    }
}
