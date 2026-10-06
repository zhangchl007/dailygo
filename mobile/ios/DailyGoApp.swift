import SwiftUI

@main
struct DailyGoApp: App {
    @StateObject private var viewModel = HabitViewModel()

    var body: some Scene {
        WindowGroup {
            DashboardView(viewModel: viewModel)
        }
    }
}
