import Foundation
import HealthKit
import DailyGoDomain

enum NativeHealthReadStatus: Equatable, Sendable { case unavailable, unknown, available, failed }
enum NativeHealthAuthorizationResult: Equatable, Sendable { case unavailable, completed, failed }

struct NativeHealthReading: Sendable {
    let status: NativeHealthReadStatus
    let evidence: HealthEvidence?
    let sourceIdentifiers: Set<String>
}

actor NativeHealthService {
    private let store = HKHealthStore()

    nonisolated static var available: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestStepAccess() async -> NativeHealthAuthorizationResult {
        guard Self.available, let type = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return .unavailable }
        return await withCheckedContinuation { continuation in
            store.requestAuthorization(toShare: [], read: [type]) { @Sendable completed, error in
                continuation.resume(returning: completed && error == nil ? .completed : .failed)
            }
        }
    }

    func readSteps(window: HealthReadWindow) async -> NativeHealthReading {
        guard Self.available, let type = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            return NativeHealthReading(status: .unavailable, evidence: nil, sourceIdentifiers: [])
        }
        let dates = HKQuery.predicateForSamples(withStart: window.startedAt, end: window.endedAt, options: [])
        let manual = HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeyWasUserEntered, allowedValues: [true])
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [dates,
            NSCompoundPredicate(notPredicateWithSubpredicate: manual)])
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) {
                @Sendable _, statistics, error in
                guard error == nil else {
                    continuation.resume(returning: NativeHealthReading(status: .failed, evidence: nil, sourceIdentifiers: []))
                    return
                }
                let sources = Set(statistics?.sources()?.map(\.bundleIdentifier) ?? [])
                guard let quantity = statistics?.sumQuantity(), !sources.isEmpty,
                      let evidence = try? HealthEvidence(source: .healthKit, startedAt: window.startedAt,
                          endedAt: window.endedAt, steps: quantity.doubleValue(for: .count())) else {
                    continuation.resume(returning: NativeHealthReading(status: .unknown, evidence: nil, sourceIdentifiers: []))
                    return
                }
                continuation.resume(returning: NativeHealthReading(status: .available, evidence: evidence, sourceIdentifiers: sources))
            }
            store.execute(query)
        }
    }
}