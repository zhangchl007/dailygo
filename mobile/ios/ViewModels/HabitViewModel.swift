import Foundation
import Combine

public class HabitViewModel: ObservableObject {
    @Published public var habits: [HabitFfi] = []
    @Published public var streakSummaries: [String: StreakSummaryFfi] = [:]
    @Published public var lastCheckIn: CheckInRecordFfi?
    @Published public var errorMessage: String?

    private var engine: DailyGoEngineFfi?

    public init() {
        initEngine()
    }

    private func initEngine() {
        do {
            let fileManager = FileManager.default
            let urls = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
            let dbUrl = urls[0].appendingPathComponent("dailygo_local.sqlite")
            self.engine = try createEngine(dbPath: dbUrl.path)
            loadHabits()
        } catch {
            self.errorMessage = "Engine initialization failed: \(error)"
        }
    }

    public func loadHabits() {
        guard let engine = engine else { return }
        do {
            self.habits = try engine.listActiveHabits()
            for habit in self.habits {
                let streak = try engine.getStreak(habitId: habit.id)
                self.streakSummaries[habit.id] = streak
            }
        } catch {
            self.errorMessage = "Failed to load habits: \(error)"
        }
    }

    public func addHabit(title: String, targetSteps: UInt32) {
        guard let engine = engine else { return }
        do {
            _ = try engine.createHabit(
                title: title,
                frequency: .daily,
                metric: .steps(target: targetSteps)
            )
            loadHabits()
        } catch {
            self.errorMessage = "Failed to create habit: \(error)"
        }
    }

    public func checkIn(habitId: String, sensorData: HealthSnapshotFfi?) {
        guard let engine = engine else { return }
        do {
            let offsetMinutes = Int32(TimeZone.current.secondsFromGMT() / 60)
            let result = try engine.checkIn(
                habitId: habitId,
                value: nil,
                sensorData: sensorData,
                tzOffsetMinutes: offsetMinutes
            )
            self.lastCheckIn = result
            loadHabits()
        } catch {
            self.errorMessage = "Check in failed: \(error)"
        }
    }
}
