# SDD Spec 005: UniFFI Cross-Platform API Specification (跨端接口契约)

## 1. Exported Objects
- `DailyGoEngine`: Singleton coordinator holding the SQLite connection pool, streak calculator, and anti-cheat engine.

## 2. Exported Methods
- `create_engine(db_path: String) -> Result<Arc<DailyGoEngine>, DailyGoError>`
- `create_habit(title: String, frequency: HabitFrequencyFfi, metric: MetricTypeFfi) -> Result<HabitFfi, DailyGoError>`
- `list_habits() -> Result<Vec<HabitFfi>, DailyGoError>`
- `check_in(habit_id: String, value: Option<f64>, sensor_data: Option<SensorDataFfi>, tz_offset_minutes: i32) -> Result<CheckInResultFfi, DailyGoError>`
- `get_streak(habit_id: String) -> Result<StreakSummaryFfi, DailyGoError>`
- `get_heat_map(habit_id: String, year: i32) -> Result<Vec<HeatMapDayFfi>, DailyGoError>`
