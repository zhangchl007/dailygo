import SwiftUI

@main
struct DailyGoApp: App {
    @StateObject private var model = NativeHabitModel()

    var body: some Scene {
        WindowGroup {
            TodayView(model: model)
        }
    }
}