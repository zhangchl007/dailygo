use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum SensorSource {
    HealthKit,
    HealthConnect,
    Manual,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct HealthSnapshot {
    pub step_delta: u32,
    pub avg_heart_rate: f64,
    pub max_heart_rate: f64,
    pub active_energy_burned_kcal: f64,
    pub distance_meters: f64,
    pub source: SensorSource,
}

impl HealthSnapshot {
    pub fn new(
        step_delta: u32,
        avg_heart_rate: f64,
        max_heart_rate: f64,
        active_energy_burned_kcal: f64,
        distance_meters: f64,
        source: SensorSource,
    ) -> Self {
        Self {
            step_delta,
            avg_heart_rate,
            max_heart_rate,
            active_energy_burned_kcal,
            distance_meters,
            source,
        }
    }
}
