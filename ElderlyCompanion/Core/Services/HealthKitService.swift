import Foundation
import HealthKit

@Observable
final class HealthKitService {
    static let shared = HealthKitService()

    private let store = HKHealthStore()

    // Permission state
    var isAuthorized: Bool = false
    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    // Latest readings
    var stepCount: Int = 0
    var heartRate: Double = 0
    var bloodOxygen: Double = 0
    var bloodPressureSystolic: Double = 0
    var bloodPressureDiastolic: Double = 0
    var sleepHours: Double = 0

    // Data types we read
    private let readTypes: Set<HKObjectType> = {
        var types = Set<HKObjectType>()
        if let steps = HKQuantityType.quantityType(forIdentifier: .stepCount) { types.insert(steps) }
        if let hr = HKQuantityType.quantityType(forIdentifier: .heartRate) { types.insert(hr) }
        if let bp1 = HKQuantityType.quantityType(forIdentifier: .bloodPressureSystolic) { types.insert(bp1) }
        if let bp2 = HKQuantityType.quantityType(forIdentifier: .bloodPressureDiastolic) { types.insert(bp2) }
        if let spo2 = HKQuantityType.quantityType(forIdentifier: .oxygenSaturation) { types.insert(spo2) }
        if let sleep = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) { types.insert(sleep) }
        return types
    }()

    // MARK: - Authorization

    func requestAuthorization() async throws {
        guard isAvailable else {
            print("[HealthKit] Not available on this device")
            return
        }

        try await store.requestAuthorization(toShare: [], read: readTypes)
        await MainActor.run { isAuthorized = true }
        UserDefaults.standard.set(true, forKey: "healthKitAuthorized")
        print("[HealthKit] Authorization granted")
    }

    func checkAuthorization() {
        isAuthorized = UserDefaults.standard.bool(forKey: "healthKitAuthorized")
    }

    // MARK: - Fetch Today's Data

    func fetchTodayStats() async {
        guard isAvailable, isAuthorized else { return }

        async let steps = fetchSteps()
        async let hr = fetchLatestHeartRate()
        async let spo2 = fetchLatestBloodOxygen()
        async let bp = fetchLatestBloodPressure()
        async let sleep = fetchSleepHours()

        let (s, h, o, b, sl) = await (steps, hr, spo2, bp, sleep)

        await MainActor.run {
            stepCount = s
            heartRate = h
            bloodOxygen = o
            bloodPressureSystolic = b.systolic
            bloodPressureDiastolic = b.diastolic
            sleepHours = sl
        }
    }

    /// Returns a dictionary suitable for sending to the API
    func getHealthSnapshot() async -> [String: Any] {
        await fetchTodayStats()
        return [
            "stepCount": stepCount,
            "heartRate": heartRate,
            "bloodOxygen": bloodOxygen,
            "bloodPressureSystolic": bloodPressureSystolic,
            "bloodPressureDiastolic": bloodPressureDiastolic,
            "sleepHours": sleepHours,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
        ]
    }

    // MARK: - Individual Fetchers

    private func fetchSteps() async -> Int {
        guard let type = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return 0 }

        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, _ in
                let steps = result?.sumQuantity()?.doubleValue(for: .count()) ?? 0
                continuation.resume(returning: Int(steps))
            }
            store.execute(query)
        }
    }

    private func fetchLatestHeartRate() async -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return 0 }
        return await fetchLatestSample(type: type, unit: HKUnit.count().unitDivided(by: .minute()))
    }

    private func fetchLatestBloodOxygen() async -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: .oxygenSaturation) else { return 0 }
        let value = await fetchLatestSample(type: type, unit: .percent())
        return value > 0 ? value * 100 : 0 // Convert to percentage
    }

    private func fetchLatestBloodPressure() async -> (systolic: Double, diastolic: Double) {
        guard let syType = HKQuantityType.quantityType(forIdentifier: .bloodPressureSystolic),
              let diType = HKQuantityType.quantityType(forIdentifier: .bloodPressureDiastolic) else {
            return (0, 0)
        }

        let mmHg = HKUnit.millimeterOfMercury()
        async let sys = fetchLatestSample(type: syType, unit: mmHg)
        async let dia = fetchLatestSample(type: diType, unit: mmHg)
        return await (sys, dia)
    }

    private func fetchSleepHours() async -> Double {
        guard let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else { return 0 }

        let now = Date()
        let yesterday = Calendar.current.date(byAdding: .hour, value: -24, to: now) ?? now
        let predicate = HKQuery.predicateForSamples(withStart: yesterday, end: now, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, results, _ in
                var totalSeconds: TimeInterval = 0
                for sample in (results as? [HKCategorySample]) ?? [] {
                    // Only count actual sleep (not inBed)
                    if sample.value != HKCategoryValueSleepAnalysis.inBed.rawValue {
                        totalSeconds += sample.endDate.timeIntervalSince(sample.startDate)
                    }
                }
                continuation.resume(returning: totalSeconds / 3600.0)
            }
            store.execute(query)
        }
    }

    private func fetchLatestSample(type: HKQuantityType, unit: HKUnit) async -> Double {
        let now = Date()
        let yesterday = Calendar.current.date(byAdding: .hour, value: -24, to: now) ?? now
        let predicate = HKQuery.predicateForSamples(withStart: yesterday, end: now, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1, sortDescriptors: [sortDescriptor]) { _, results, _ in
                let value = (results?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit) ?? 0
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }
}
