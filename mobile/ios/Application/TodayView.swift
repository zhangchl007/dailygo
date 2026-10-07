import SwiftUI
import DailyGoDomain
import UserNotifications

@MainActor
final class NativeHabitModel: ObservableObject {
    @Published private(set) var habits: [NativeHabit] = []
    @Published private(set) var completed = Set<String>()
    @Published private(set) var completionRecords: [String: NativeEntry] = [:]
    @Published private(set) var streaks: [String: StreakSummary] = [:]
    @Published private(set) var recentDates: [String: Set<String>] = [:]
    @Published private(set) var asOfDays: [String: LocalDay] = [:]
    @Published private(set) var loading = true
    @Published private(set) var saving = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var asOf = Date()
    private var repository: NativeRepository?
    private var refreshing = false
    private let now: () -> Date
    private var storeName = "dailygo-native.store"

    init(now: (() -> Date)? = nil) {
        #if DEBUG
        if let value = ProcessInfo.processInfo.environment["DAILYGO_UI_TEST_STORE"], let identifier = UUID(uuidString: value) {
            storeName = "ui-\(identifier.uuidString).store"
            self.now = now ?? { Date(timeIntervalSince1970: 1_791_282_600) }
        } else { self.now = now ?? { Date() } }
        #else
        self.now = now ?? { Date() }
        #endif
    }

    func reload() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false; loading = false }
        do {
            if repository == nil {
                let storeName = storeName
                repository = try await Task.detached {
                    let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                        appropriateFor: nil, create: true)
                    return NativeRepository(modelContainer: try NativeStore.open(url: directory.appendingPathComponent(storeName)))
                }.value
            }
            try await refresh()
            errorMessage = nil
        } catch {
            errorMessage = "Could not load your data. Please retry."
        }
    }

    private func refresh() async throws {
        guard let repository else { throw NativeStorageError.invalidStore }
        let instant = now()
        let snapshot = try await repository.habits(ownerID: "guest")
        var complete = Set<String>()
        var summaries: [String: StreakSummary] = [:]
        var recent: [String: Set<String>] = [:]
        var datesByHabit: [String: LocalDay] = [:]
        var records: [String: NativeEntry] = [:]
        for habit in snapshot {
            let asOf = try CalendarPolicy.credit(now: instant, zoneID: habit.zoneID).date
            let entries = try await repository.entries(ownerID: "guest", habitID: habit.id, kind: .completion)
            let days = try entries.map { try LocalDay($0.creditedDate) }
            let summary = try StreakCalculator.calculate(schedule: habit.definition().schedule, dates: days, asOf: asOf)
            summaries[habit.id] = summary
            datesByHabit[habit.id] = asOf
            records[habit.id] = try await repository.completionRecordOn(ownerID: "guest", habitID: habit.id, date: asOf.description)
            if summary.isCheckedInToday { complete.insert(habit.id) }
            let history = try await repository.recentCompletions(ownerID: "guest", habitID: habit.id, through: asOf.description)
            recent[habit.id] = Set(history.map(\.creditedDate))
        }
        habits = snapshot
        completed = complete
        completionRecords = records
        streaks = summaries
        recentDates = recent
        asOfDays = datesByHabit
        asOf = instant
    }

    func perform(_ operation: @Sendable (NativeRepository) async throws -> Void) async -> Bool {
        guard !saving, let repository else { return false }
        saving = true
        errorMessage = nil
        defer { saving = false }
        do {
            try await operation(repository)
        } catch NativeStorageError.goalHasHistory {
            errorMessage = "Goals with recorded history cannot be changed yet."
        } catch NativeStorageError.scheduleHasHistory {
            errorMessage = "Schedules with recorded history cannot be changed yet."
            return false
        } catch {
            errorMessage = error is DomainError || error as? NativeStorageError == .invalidDefinition
                ? "Check the title, schedule, timezone and numeric value."
                : "Could not save your data. Please retry."
            return false
        }
        do { try await refresh() }
        catch { errorMessage = "Saved, but could not refresh your data. Please retry loading." }
        return true
    }

    func millis() -> Int64 { Int64(now().timeIntervalSince1970 * 1000) }
}

struct TodayView: View {
    @ObservedObject var model: NativeHabitModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var adding = false
    @State private var editing: NativeHabit?
    @State private var editingGoal: NativeHabit?
    @State private var recording: NativeHabit?
    @State private var deleting: NativeHabit?
    @State private var showArchived = false
    @State private var historyHabitID: String?
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    BrandHeader()
                    Text(model.asOf, format: .dateTime.weekday(.wide).month().day()).foregroundStyle(.secondary)
                    Toggle("Archived", isOn: $showArchived)
                }
                if model.loading { ProgressView() }
                if let error = model.errorMessage {
                    Section {
                        Text(LocalizedStringKey(error)).foregroundStyle(.red)
                        Button("Retry") { Task { await model.reload() } }.disabled(model.saving)
                    }
                }
                Section("Habits") {
                    let visible = model.habits.filter { $0.archived == showArchived }
                    if !model.loading && model.errorMessage == nil && visible.isEmpty { Text("No habits yet").foregroundStyle(.secondary) }
                    ForEach(visible, id: \.id) { habit in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(habit.title).font(.headline)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Menu {
                                    Button { editing = habit } label: { Label("Edit habit", systemImage: "pencil") }
                                    Button { editingGoal = habit } label: { Label("Edit goal", systemImage: "target") }
                                    Button {
                                        let command = NativeHabitArchiveCommand(ownerID: "guest", operationID: UUID().uuidString,
                                            habitID: habit.id, archived: !habit.archived, occurredAtMillis: model.millis())
                                        Task { _ = await model.perform { _ = try await $0.setHabitArchived(command) } }
                                    } label: { Label(habit.archived ? "Restore" : "Archive", systemImage: habit.archived ? "arrow.uturn.backward" : "archivebox") }
                                    Button(role: .destructive) { deleting = habit } label: { Label("Delete habit", systemImage: "trash") }
                                } label: {
                                    Label("Habit options", systemImage: "ellipsis")
                                        .frame(width: 44, height: 44)
                                        .contentShape(Rectangle())
                                }
                                .labelStyle(.iconOnly)
                                .buttonStyle(.borderless)
                                .disabled(model.saving)
                            }
                            Text("\(scheduleName(habit.scheduleKind)) · \(goalName(habit.goalKind))").font(.subheadline).foregroundStyle(.secondary)
                            if let streak = model.streaks[habit.id] {
                                Text("\(streak.current) \(streak.unit == .weeks ? "weeks" : "days") streak")
                                    .accessibilityLabel("Current streak: \(streak.current) \(streak.unit == .weeks ? "weeks" : "days")")
                            }
                            Button(historyHabitID == habit.id ? "Hide recent history" : "Show recent history") {
                                historyHabitID = historyHabitID == habit.id ? nil : habit.id
                            }
                            .buttonStyle(.borderless)
                            if historyHabitID == habit.id, let asOf = model.asOfDays[habit.id] {
                                NativeHistoryGrid(asOf: asOf, dates: model.recentDates[habit.id, default: []])
                            }
                            if !habit.archived {
                                Button {
                                    if habit.goalKind != "completion" { recording = habit }
                                    else {
                                        let id = UUID().uuidString
                                        let command = NativeEntryCommand(ownerID: "guest", operationID: id, recordID: id,
                                            habitID: habit.id, occurredAtMillis: model.millis(), value: nil, workoutStartedAtMillis: nil, asOfMillis: nil)
                                        Task { _ = await model.perform { _ = try await $0.complete(command) } }
                                    }
                                } label: {
                                    Label(model.completed.contains(habit.id) ? "Completed" : habit.goalKind == "completion" ? "Complete" : "Record progress",
                                        systemImage: model.completed.contains(habit.id) ? "checkmark.circle.fill" : "checkmark.circle")
                                }
                                .buttonStyle(.borderless)
                                .disabled(model.saving || model.completionRecords[habit.id] != nil)
                                if let entry = model.completionRecords[habit.id] {
                                    let isActive = model.completed.contains(habit.id)
                                    Button(isActive ? "Undo completion" : "Restore completion") {
                                        let command = NativeCompletionCorrectionCommand(ownerID: "guest", operationID: UUID().uuidString,
                                            recordID: entry.id, active: !isActive, occurredAtMillis: model.millis())
                                        Task { _ = await model.perform { _ = try await $0.correctCompletion(command) } }
                                    }
                                    .buttonStyle(.borderless)
                                    .disabled(model.saving)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                if model.habits.isEmpty && !model.loading {
                    Button { adding = true } label: { Label("Add habit", systemImage: "plus") }.disabled(model.saving)
                }
            }
            .listStyle(.plain)
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: { Label("Settings", systemImage: "gearshape") }
                        .accessibilityIdentifier("settings")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { adding = true } label: { Label("Add habit", systemImage: "plus") }.disabled(model.loading || model.saving)
                        .accessibilityIdentifier("add-habit")
                }
            }
        }
        .task { await model.reload() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await model.reload() } } }
        .sheet(isPresented: $adding) { NativeHabitEditor(model: model, existing: nil) }
        .sheet(item: $editing) { NativeHabitEditor(model: model, existing: $0) }
        .sheet(item: $editingGoal) { NativeHabitEditor(model: model, existing: $0, goalOnly: true) }
        .sheet(item: $recording) { NativeProgressEditor(model: model, habit: $0) }
        .sheet(isPresented: $showSettings) { NativeSettingsView() }
        .confirmationDialog("Delete habit and its history?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            if let habit = deleting {
                Button("Delete habit", role: .destructive) {
                    let command = NativeHabitDeleteCommand(ownerID: "guest", operationID: UUID().uuidString,
                        habitID: habit.id, occurredAtMillis: model.millis())
                    Task { _ = await model.perform { try await $0.deleteHabit(command) } }
                }
            }
        }
    }
}

private struct NativeSettingsView: View {
    @AppStorage("dailygo.reminders.enabled", store: NativeSettingsView.settingsStore) private var remindersEnabled = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var notificationsDenied = false
    @State private var updating = false
    @State private var schedulingFailed = false

    private static var settingsStore: UserDefaults {
        #if DEBUG
        if let value = ProcessInfo.processInfo.environment["DAILYGO_UI_TEST_STORE"], let identifier = UUID(uuidString: value),
           let store = UserDefaults(suiteName: "dailygo-ui-\(identifier.uuidString)") { return store }
        #endif
        return .standard
    }

    var body: some View {
        NavigationStack {
            Form {
                Toggle("Reminders", isOn: Binding(get: { remindersEnabled }, set: { requested in
                    Task { await applyReminder(requested) }
                }))
                .disabled(updating)
                .accessibilityIdentifier("reminder-toggle")
                if updating { ProgressView() }
                Text("Daily at 8:00 PM").foregroundStyle(.secondary)
                if notificationsDenied {
                    Text("Notifications are off. Enable them in system settings to use reminders.")
                        .foregroundStyle(.red)
                }
                if schedulingFailed {
                    Text("Could not schedule your reminder. Please retry.").foregroundStyle(.red)
                }
            }
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.disabled(updating) } }
        }
        .interactiveDismissDisabled(updating)
        .task { await updatePermissionState() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await updatePermissionState() } }
        }
    }

    private func updatePermissionState() async {
        guard !updating else { return }
        updating = true
        let center = UNUserNotificationCenter.current()
        let authorization: UNAuthorizationStatus = await withCheckedContinuation { continuation in
            center.getNotificationSettings { @Sendable settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
        notificationsDenied = authorization == .denied
        if authorization == .denied || authorization == .notDetermined {
            center.removePendingNotificationRequests(withIdentifiers: ["dailygo-reminder"])
            remindersEnabled = false
        }
        updating = false
        if remindersEnabled {
            await applyReminder(true)
        }
    }

    private func applyReminder(_ enabled: Bool) async {
        guard !updating else { return }
        updating = true
        schedulingFailed = false
        defer { updating = false }
        let center = UNUserNotificationCenter.current()
        guard enabled else {
            center.removePendingNotificationRequests(withIdentifiers: ["dailygo-reminder"])
            remindersEnabled = false
            return
        }
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            guard granted else {
                notificationsDenied = true
                center.removePendingNotificationRequests(withIdentifiers: ["dailygo-reminder"])
                remindersEnabled = false
                return
            }
            notificationsDenied = false
            let content = UNMutableNotificationContent()
            content.title = String(localized: "DailyGo reminder")
            content.body = String(localized: "Take a moment for today’s habits.")
            var time = DateComponents()
            time.hour = 20
            time.minute = 0
            let trigger = UNCalendarNotificationTrigger(dateMatching: time, repeats: true)
            try await center.add(UNNotificationRequest(identifier: "dailygo-reminder", content: content, trigger: trigger))
            remindersEnabled = true
        } catch {
            schedulingFailed = true
            center.removePendingNotificationRequests(withIdentifiers: ["dailygo-reminder"])
            remindersEnabled = false
        }
    }
}

extension NativeHabit: Identifiable {}

private func scheduleName(_ kind: String) -> String {
    switch kind { case "weekdays": "Weekdays"; case "weekly": "Weekly"; default: "Daily" }
}

private func goalName(_ kind: String) -> String {
    switch kind { case "steps": "Steps"; case "duration_minutes": "Minutes"; case "distance_meters": "Meters"; default: "Completion" }
}

private struct NativeHistoryGrid: View {
    let asOf: LocalDay
    let dates: Set<String>
    private let columns = Array(repeating: GridItem(.fixed(16), spacing: 4), count: 7)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(0..<35, id: \.self) { offset in
                let day = try? asOf.adding(days: offset - 34)
                RoundedRectangle(cornerRadius: 3)
                    .fill(day.map { dates.contains($0.description) ? Color.accentColor : Color.secondary.opacity(0.16) } ?? Color.clear)
                    .frame(width: 16, height: 16)
                    .accessibilityLabel(day?.description ?? "")
                    .accessibilityValue(day.map { dates.contains($0.description) ? Text("Completed") : Text("Not completed") } ?? Text("Not completed"))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Recent completion history")
        .accessibilityIdentifier("history-grid")
    }
}

private struct NativeHabitEditor: View {
    @ObservedObject var model: NativeHabitModel
    let existing: NativeHabit?
    let goalOnly: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var schedule: String
    @State private var weekly: Int
    @State private var goal: String
    @State private var target: String
    @State private var zone: String
    @State private var id: String
    @State private var operationID = UUID().uuidString
    @State private var occurred: Int64
    private enum EditorField: Hashable { case title, target }
    @FocusState private var focusedField: EditorField?

    init(model: NativeHabitModel, existing: NativeHabit?, goalOnly: Bool = false) {
        self.model = model
        self.existing = existing
        self.goalOnly = goalOnly
        _title = State(initialValue: existing?.title ?? "")
        _schedule = State(initialValue: existing?.scheduleKind ?? "daily")
        _weekly = State(initialValue: existing?.scheduleParameter ?? 3)
        _goal = State(initialValue: existing?.goalKind ?? "completion")
        _target = State(initialValue: existing?.target.map { String($0) } ?? "")
        _zone = State(initialValue: existing?.zoneID ?? TimeZone.current.identifier)
        _id = State(initialValue: existing?.id ?? UUID().uuidString)
        _occurred = State(initialValue: model.millis())
    }

    var body: some View {
        NavigationStack {
            Form {
                if !goalOnly {
                    HStack {
                        TextField("Title", text: $title).focused($focusedField, equals: .title)
                            .accessibilityIdentifier("habit-title")
                        if !title.isEmpty {
                            Button { title = ""; focusedField = .title } label: { Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44) }
                                .buttonStyle(.borderless).accessibilityLabel("Clear title")
                                .accessibilityIdentifier("clear-habit-title").disabled(model.saving)
                        }
                    }
                    Picker("Schedule", selection: $schedule) {
                        Text("Daily").tag("daily")
                        Text("Weekdays").tag("weekdays")
                        Text("Weekly").tag("weekly")
                    }
                    if schedule == "weekly" { Stepper("Days per week: \(weekly)", value: $weekly, in: 1...7) }
                    TextField("Schedule timezone", text: $zone).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                if existing == nil || goalOnly {
                    Picker("Goal", selection: $goal) {
                        Text("Completion").tag("completion")
                        Text("Steps").tag("steps")
                        Text("Minutes").tag("duration_minutes")
                        Text("Meters").tag("distance_meters")
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("habit-goal")
                }
                if goal != "completion" {
                    HStack {
                        TextField("Target", text: $target).keyboardType(.decimalPad).focused($focusedField, equals: .target)
                            .disabled(existing != nil && !goalOnly).accessibilityIdentifier("habit-target")
                        if !target.isEmpty && (existing == nil || goalOnly) {
                            Button { target = ""; focusedField = .target } label: { Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44) }
                                .buttonStyle(.borderless).accessibilityLabel("Clear target")
                                .accessibilityIdentifier("clear-habit-target").disabled(model.saving)
                        }
                    }
                }
                if let error = model.errorMessage { Text(LocalizedStringKey(error)).foregroundStyle(.red) }
            }
            .accessibilityIdentifier("habit-editor")
            .navigationTitle(goalOnly ? "Edit goal" : existing == nil ? "Add habit" : "Edit habit")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(model.saving) }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(model.saving) }
            }
        }
        .interactiveDismissDisabled(model.saving)
    }

    private func save() {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let parameter = schedule == "weekly" ? weekly : nil
        let habit = NativeHabit(ownerID: "guest", id: id, title: title, scheduleKind: schedule, scheduleParameter: parameter,
            goalKind: goal, target: goal == "completion" ? nil : Double(target), zoneID: zone, createdAtMillis: occurred, archived: false)
        let edit = NativeHabitEditCommand(ownerID: "guest", operationID: operationID, habitID: id, title: title,
            scheduleKind: schedule, scheduleParameter: parameter, zoneID: zone, occurredAtMillis: occurred, asOfMillis: model.millis())
        let operationID = operationID
        let isNew = existing == nil
        let goalChange = NativeHabitGoalCommand(ownerID: existing?.ownerID ?? "guest", operationID: operationID, habitID: id,
            goalKind: goal, target: goal == "completion" ? nil : Double(target), occurredAtMillis: occurred, asOfMillis: model.millis())
        let goalOnly = goalOnly
        Task {
            let success = await model.perform { repository in
                if goalOnly { _ = try await repository.setHabitGoal(goalChange) }
                else if isNew { _ = try await repository.saveHabit(habit, operationID: operationID) }
                else { _ = try await repository.editHabit(edit) }
            }
            if success { dismiss() }
        }
    }
}

private struct NativeProgressEditor: View {
    @ObservedObject var model: NativeHabitModel
    let habit: NativeHabit
    @Environment(\.dismiss) private var dismiss
    @State private var value = ""
    @State private var operationID = UUID().uuidString
    @State private var occurred: Int64?

    var body: some View {
        NavigationStack {
            Form {
                if let target = habit.target { LabeledContent("Target", value: "\(target) \(goalName(habit.goalKind))") }
                TextField("Manual value", text: $value).keyboardType(.decimalPad)
                if let error = model.errorMessage { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle(habit.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(model.saving) }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(model.saving) }
            }
        }
        .interactiveDismissDisabled(model.saving)
    }

    private func save() {
        if occurred == nil { occurred = model.millis() }
        guard let instant = occurred else { return }
        let command = NativeEntryCommand(ownerID: "guest", operationID: operationID, recordID: operationID, habitID: habit.id,
            occurredAtMillis: instant, value: Double(value), workoutStartedAtMillis: nil, asOfMillis: model.millis())
        let habit = habit
        Task {
            let success = await model.perform { repository in
                guard let value = command.value else { throw DomainError.invalidGoal }
                if try habit.definition().goal.isCompleted(value: value) { _ = try await repository.complete(command) }
                else { _ = try await repository.recordProgress(command) }
            }
            if success { dismiss() }
        }
    }
}