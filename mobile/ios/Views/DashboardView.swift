import SwiftUI

public struct DashboardView: View {
    @ObservedObject var viewModel: HabitViewModel
    @State private var newHabitTitle: String = ""

    public init(viewModel: HabitViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationView {
            VStack {
                // Streak & Shield Header Banner
                HStack {
                    VStack(alignment: .leading) {
                        Text("DailyGo 运动打卡")
                            .font(.title2)
                            .bold()
                        Text("Local-First 离线零延迟 · 汗水防作弊")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal)

                // Habit List
                List {
                    ForEach(viewModel.habits, id: \.id) { habit in
                        let streak = viewModel.streakSummaries[habit.id]
                        HabitRowView(habit: habit, streak: streak) {
                            // Check in trigger
                            HealthKitService.shared.fetchRecentWorkoutSnapshot(
                                startDate: Date().addingTimeInterval(-3600),
                                endDate: Date()
                            ) { snapshot in
                                DispatchQueue.main.async {
                                    viewModel.checkIn(habitId: habit.id, sensorData: snapshot)
                                }
                            }
                        }
                    }
                }
                .listStyle(PlainListStyle())

                // Quick Add Habit Field
                HStack {
                    TextField("新增习惯 (例如: 晨跑 5km)", text: $newHabitTitle)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    Button(action: {
                        guard !newHabitTitle.isEmpty else { return }
                        viewModel.addHabit(title: newHabitTitle, targetSteps: 5000)
                        newHabitTitle = ""
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                    }
                }
                .padding()
            }
            .navigationTitle("今日打卡")
        }
    }
}

struct HabitRowView: View {
    let habit: HabitFfi
    let streak: StreakSummaryFfi?
    let onCheckIn: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(habit.title)
                    .font(.headline)
                HStack(spacing: 8) {
                    Label("\(streak?.currentStreak ?? 0) 天连胜", systemImage: "flame.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                    Label("护盾: \(streak?.shieldsRemaining ?? 0)", systemImage: "shield.fill")
                        .foregroundColor(.blue)
                        .font(.caption)
                }
            }
            Spacer()
            Button(action: onCheckIn) {
                Text(streak?.isCheckedInToday == true ? "已完成" : "打卡")
                    .bold()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(streak?.isCheckedInToday == true ? Color.green : Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .disabled(streak?.isCheckedInToday == true)
        }
        .padding(.vertical, 4)
    }
}
