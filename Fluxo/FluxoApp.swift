import SwiftUI

@main
struct FluxoApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}

enum AppTab: Hashable { case home, calendar, movements, reports, settings }

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @State private var tab: AppTab = .home

    var body: some View {
        TabView(selection: $tab) {
            Tab("Inicio", systemImage: "square.grid.2x2", value: AppTab.home) {
                HomeView(tab: $tab)
            }
            Tab("Calendario", systemImage: "calendar", value: AppTab.calendar) {
                CalendarScreen()
            }
            Tab("Movimientos", systemImage: "list.bullet.rectangle", value: AppTab.movements) {
                TransactionsScreen()
            }
            Tab("Informes", systemImage: "chart.pie", value: AppTab.reports) {
                ReportsScreen()
            }
            Tab("Ajustes", systemImage: "ellipsis", value: AppTab.settings) {
                SettingsScreen()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .onOpenURL { url in
            // Por si el banco vuelve a la app por fuera de la ventana de login
            if url.scheme == "fluxo", let code = BankAuthFlow.code(from: url) {
                PendingBank.shared.receive(code: code, model: model)
            }
        }
        .task {
            if model.data.bank != nil, BankKeys.isConfigured,
               (model.data.lastSync ?? .distantPast) < Date().addingTimeInterval(-6 * 3600) {
                await model.sync()
            }
        }
        .alert(model.message ?? "", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("OK", role: .cancel) {}
        }
    }
}
