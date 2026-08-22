import SwiftUI

enum AppRoute {
    case timer
    case history
    case settings
}

struct RootView: View {
    @State private var route: AppRoute = .timer

    var body: some View {
        switch route {
        case .timer:
            TimerView(
                onShowHistory: { route = .history },
                onShowSettings: { route = .settings }
            )
        case .history:
            HistoryView(onBack: { route = .timer })
        case .settings:
            SettingsView(onBack: { route = .timer })
        }
    }
}
