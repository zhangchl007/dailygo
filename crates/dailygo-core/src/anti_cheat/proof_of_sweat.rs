use serde::{Deserialize, Serialize};
use crate::domain::check_in::VerificationStatus;
use crate::domain::habit::MetricType;
use crate::domain::health::HealthSnapshot;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UserFitnessProfile {
    pub age: u32,
    pub resting_heart_rate: f64,
}

impl Default for UserFitnessProfile {
    fn default() -> Self {
        Self {
            age: 28,
            resting_heart_rate: 65.0,
        }
    }
}

impl UserFitnessProfile {
    pub fn max_heart_rate(&self) -> f64 {
        220.0 - self.age as f64
    }

    pub fn heart_rate_reserve(&self) -> f64 {
        (self.max_heart_rate() - self.resting_heart_rate).max(40.0)
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct VerificationResult {
    pub score: f64,
    pub status: VerificationStatus,
    pub heart_rate_score: f64,
    pub movement_consistency_score: f64,
    pub energy_score: f64,
    pub explanation: String,
}

pub fn verify_proof_of_sweat(
    metric: &MetricType,
    claimed_value: Option<f64>,
    snapshot: Option<&HealthSnapshot>,
    profile: &UserFitnessProfile,
) -> VerificationResult {
    let sensor_data = match snapshot {
        None => {
            return VerificationResult {
                score: 0.50,
                status: VerificationStatus::SelfReported,
                heart_rate_score: 0.0,
                movement_consistency_score: 0.0,
                energy_score: 0.0,
                explanation: "No sensor evidence provided; recorded as self-reported".to_string(),
            };
        }
        Some(s) => s,
    };

    // 1. Heart Rate Score
    let hrr = profile.heart_rate_reserve();
    let hr_diff = sensor_data.avg_heart_rate - profile.resting_heart_rate;
    let hr_intensity = (hr_diff / hrr).clamp(0.0, 1.2);
    let hr_score = if hr_intensity >= 0.45 {
        1.0
    } else if hr_intensity >= 0.25 {
        0.75
    } else if hr_intensity >= 0.10 {
        0.40
    } else {
        0.10 // Heart rate did not elevate above resting
    };

    // 2. Movement Consistency Score
    let mut movement_score = 1.0;
    if let MetricType::DistanceMeters { target } = metric {
        let distance = claimed_value.unwrap_or(*target as f64);
        if distance > 1000.0 {
            // Check stride length: steps / distance
            let stride_len = if sensor_data.step_delta > 0 {
                distance / (sensor_data.step_delta as f64)
            } else {
                999.0 // impossible
            };

            // Human running stride is typically between 0.6m and 1.8m
            if stride_len > 4.0 || stride_len < 0.2 {
                // Highly suspect (vehicle or spoofed pedometer)
                movement_score = 0.05;
            } else {
                movement_score = 0.95;
            }
        }
    } else if let MetricType::Steps { target } = metric {
        let ratio = (sensor_data.step_delta as f64) / (*target as f64);
        movement_score = (ratio).clamp(0.0, 1.0);
    } else {
        movement_score = if sensor_data.step_delta > 500 { 0.9 } else { 0.5 };
    }

    // 3. Energy / Calorie Score
    let energy_score = if sensor_data.active_energy_burned_kcal > 150.0 {
        1.0
    } else if sensor_data.active_energy_burned_kcal > 50.0 {
        0.7
    } else if sensor_data.active_energy_burned_kcal > 20.0 {
        0.4
    } else {
        0.1
    };

    // Weighted Overall Score
    let overall_score = 0.35 * hr_score + 0.35 * movement_score + 0.30 * energy_score;

    let (status, explanation) = if movement_score < 0.20 || (hr_score < 0.20 && energy_score < 0.20) {
        (
            VerificationStatus::Suspect,
            "Sensor metrics conflict with exercise intensity or movement kinematics".to_string(),
        )
    } else if overall_score >= 0.70 {
        (
            VerificationStatus::Verified,
            "Strong sensor verification: elevated cardiovascular and biometric output confirmed"
                .to_string(),
        )
    } else {
        (
            VerificationStatus::SelfReported,
            "Low sensor confidence; classified as self-reported".to_string(),
        )
    };

    VerificationResult {
        score: overall_score,
        status,
        heart_rate_score: hr_score,
        movement_consistency_score: movement_score,
        energy_score,
        explanation,
    }
}
