import Foundation
import Combine

#if canImport(HealthKit) && canImport(CoreMotion) && os(iOS)
import HealthKit
import CoreMotion

final class StepCountManager: ObservableObject {

    static let shared = StepCountManager()
    private init() {}

    // Published counters
    @Published private(set) var todaySteps: Int = 0
    @Published private(set) var sessionSteps: Int = 0

    // HealthKit for background delivery (day total)
    private let healthStore = HKHealthStore()
    private var hkObserverQuery: HKObserverQuery?

    // Core Motion for live foreground/session steps
    private let pedometer = CMPedometer()
    private var sessionStartDate: Date?

    // MARK: - Public API

    // Call once at app launch
    func start() {
        requestHealthKitAuthorization { [weak self] granted in
            guard let self else { return }
            if granted {
                self.registerHKObserver()
                self.fetchTodaySteps()
            }
        }

        // Optional: start a passive pedometer stream to warm permissions;
        // sessionStartDate will reset when a real session begins.
        if CMPedometer.isStepCountingAvailable() {
            pedometer.startUpdates(from: Date()) { [weak self] _, _ in
                // HealthKit observer will keep todaySteps fresh in background.
                _ = self // keep capture
            }
        }
    }

    // Start a navigation/session step count
    func beginSession() {
        sessionStartDate = Date()
        sessionSteps = 0

        guard CMPedometer.isStepCountingAvailable(),
              let startDate = sessionStartDate else { return }

        pedometer.stopUpdates()
        pedometer.startUpdates(from: startDate) { [weak self] data, _ in
            guard let self else { return }
            if let steps = data?.numberOfSteps.intValue {
                DispatchQueue.main.async {
                    self.sessionSteps = max(0, steps)
                }
            }
        }
    }

    // End the session step count (HealthKit background stays active)
    func endSession() {
        sessionStartDate = nil
        pedometer.stopUpdates()
    }

    // MARK: - HealthKit

    private func requestHealthKitAuthorization(completion: @escaping (Bool) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            completion(false)
            return
        }
        let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        healthStore.requestAuthorization(toShare: nil, read: [stepType]) { success, _ in
            completion(success)
        }
    }

    private func registerHKObserver() {
        let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        // Clean any previous observer
        if let q = hkObserverQuery {
            healthStore.stop(q)
            hkObserverQuery = nil
        }

        let query = HKObserverQuery(sampleType: stepType, predicate: nil) { [weak self] _, completionHandler, _ in
            self?.fetchTodaySteps {
                completionHandler()
            }
        }
        hkObserverQuery = query
        healthStore.execute(query)

        // Background delivery
        healthStore.enableBackgroundDelivery(for: stepType, frequency: .immediate) { success, error in
            if let error = error {
                print("HK enableBackgroundDelivery error:", error.localizedDescription)
            }
        }

        // Initial fetch
        fetchTodaySteps()
    }

    private func fetchTodaySteps(completion: (() -> Void)? = nil) {
        let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: Date(), options: .strictStartDate)

        let query = HKStatisticsQuery(quantityType: stepType,
                                      quantitySamplePredicate: predicate,
                                      options: .cumulativeSum) { [weak self] _, stats, _ in
            defer { completion?() }
            guard let self else { return }
            let sum = stats?.sumQuantity()?.doubleValue(for: HKUnit.count()) ?? 0
            DispatchQueue.main.async {
                self.todaySteps = Int(sum.rounded())
            }
        }
        healthStore.execute(query)
    }
}

#else

// Fallback stub for platforms/targets where HealthKit/CoreMotion aren’t available
final class StepCountManager: ObservableObject {
    static let shared = StepCountManager()
    private init() {}

    @Published private(set) var todaySteps: Int = 0
    @Published private(set) var sessionSteps: Int = 0

    func start() {}
    func beginSession() { sessionSteps = 0 }
    func endSession() {}
}

#endif
