use dailygo_core::anti_cheat::proof_of_sweat::{
    verify_proof_of_sweat, UserFitnessProfile,
};
use dailygo_core::domain::check_in::VerificationStatus;
use dailygo_core::domain::habit::MetricType;
use dailygo_core::domain::health::{HealthSnapshot, SensorSource};

#[test]
fn test_manual_check_in_without_sensors_is_self_reported() {
    let profile = UserFitnessProfile::default(); // age 25, resting HR 65
    let metric = MetricType::Completion;

    let result = verify_proof_of_sweat(
        &metric,
        None, // no value
        None, // no sensors provided
        &profile,
    );

    assert_eq!(result.status, VerificationStatus::SelfReported);
    assert!(result.score < 0.70);
}

#[test]
fn test_vigorous_workout_with_high_hr_and_steps_is_verified() {
    let profile = UserFitnessProfile::default();
    let metric = MetricType::DistanceMeters { target: 5000 };

    let snapshot = HealthSnapshot::new(
        4800,           // step delta
        155.0,          // avg HR (vigorous aerobic)
        175.0,          // max HR
        360.0,          // 360 kcal
        5100.0,         // 5100 meters
        SensorSource::HealthKit,
    );

    let result = verify_proof_of_sweat(
        &metric,
        Some(5100.0),
        Some(&snapshot),
        &profile,
    );

    assert_eq!(result.status, VerificationStatus::Verified);
    assert!(result.score >= 0.70);
}

#[test]
fn test_impossible_speed_or_contradiction_is_suspect() {
    let profile = UserFitnessProfile::default();
    let metric = MetricType::DistanceMeters { target: 10000 };

    // Claimed 10km in 5 minutes with resting heart rate and 100 steps (car or fake data)
    let snapshot = HealthSnapshot::new(
        120,            // only 120 steps!
        62.0,           // resting HR!
        68.0,
        15.0,           // 15 kcal!
        10000.0,        // reported 10km!
        SensorSource::HealthConnect,
    );

    let result = verify_proof_of_sweat(
        &metric,
        Some(10000.0),
        Some(&snapshot),
        &profile,
    );

    assert_eq!(result.status, VerificationStatus::Suspect);
    assert!(result.score < 0.35);
}
