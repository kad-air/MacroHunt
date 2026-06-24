// Services/HealthKitService.swift
import Foundation
import HealthKit

/// Bridges MacroHunt and Apple Health.
///
/// **Write** (Phase 1): each `Meal` is saved as an `HKCorrelation` of type `.food`
/// bundling the energy + macro quantity samples that already live on the model, so the
/// meal appears as a single entry in Apple Health's nutrition log and can be read by
/// other apps (Fitness, etc.).
///
/// **Read** (Phase 2): pulls weight, activity/energy-expenditure, and cardiovascular
/// trends *in* to give Trends an energy-balance and weight picture. A single unified
/// authorization request covers both directions.
///
/// All work is best-effort and gated by the user's opt-in in Settings — a HealthKit
/// failure (denied permission, unavailable device) must never block meal logging, and
/// reads degrade gracefully (HealthKit hides read-authorization status, so a denied or
/// empty read just returns `nil`/`[]`). See `MealRepository.saveMealWithSync`.
final class HealthKitService {
    static let shared = HealthKitService()

    private let store = HKHealthStore()

    private init() {}

    /// HealthKit is unavailable on iPad and in some environments.
    var isHealthDataAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    // MARK: - Types

    /// The dietary quantity types MacroHunt writes, paired with the `Meal` field and unit.
    private static let energyIdentifier: HKQuantityTypeIdentifier = .dietaryEnergyConsumed
    private static let proteinIdentifier: HKQuantityTypeIdentifier = .dietaryProtein
    private static let carbsIdentifier: HKQuantityTypeIdentifier = .dietaryCarbohydrates
    private static let fatIdentifier: HKQuantityTypeIdentifier = .dietaryFatTotal

    private var foodCorrelationType: HKCorrelationType? {
        HKCorrelationType.correlationType(forIdentifier: .food)
    }

    private var nutritionTypesToShare: Set<HKSampleType> {
        var types = Set<HKSampleType>()
        for id in [Self.energyIdentifier, Self.proteinIdentifier, Self.carbsIdentifier, Self.fatIdentifier] {
            if let type = HKObjectType.quantityType(forIdentifier: id) {
                types.insert(type)
            }
        }
        // Do NOT add the `.food` correlation type here. HealthKit disallows
        // correlation types in a share-authorization request and raises an
        // NSInvalidArgumentException (`_throwIfAuthorizationDisallowedForSharing`)
        // that Swift can't catch — a hard SIGABRT crash. Saving an HKCorrelation
        // only requires authorization for its member sample types (the quantity
        // types above), so requesting those is sufficient to write `.food`.
        return types
    }

    // MARK: - Read types (Phase 2)

    /// Quantity types read for the Trends energy-balance, weight, and cardio surfaces.
    private static let readQuantityIdentifiers: [HKQuantityTypeIdentifier] = [
        .bodyMass,
        .activeEnergyBurned,
        .basalEnergyBurned,
        .stepCount,
        .restingHeartRate,
        .heartRateVariabilitySDNN,
        .vo2Max,
        .heartRateRecoveryOneMinute
    ]

    private var typesToRead: Set<HKObjectType> {
        var types = Set<HKObjectType>()
        for id in Self.readQuantityIdentifiers {
            if let type = HKObjectType.quantityType(forIdentifier: id) {
                types.insert(type)
            }
        }
        types.insert(HKObjectType.workoutType())
        return types
    }

    // MARK: - Authorization

    /// Requests a single unified authorization covering both meal writes (nutrition) and
    /// the Phase 2 reads (weight / activity / cardio). HealthKit only prompts for types
    /// whose status is `.notDetermined`, so calling this again for an existing Phase 1
    /// user surfaces just the new read prompt — which is exactly how the Trends "Connect"
    /// affordance brings older installs up to date.
    func requestAuthorization() async throws {
        guard isHealthDataAvailable else { throw HealthKitError.unavailable }
        try await store.requestAuthorization(toShare: nutritionTypesToShare, read: typesToRead)
    }

    /// Share authorization status for our primary write type (dietary energy).
    ///
    /// HealthKit only exposes *write* authorization for privacy reasons, which is all
    /// Phase 1 needs. `.notDetermined` means we have not asked yet.
    func energyAuthorizationStatus() -> HKAuthorizationStatus {
        guard let type = HKObjectType.quantityType(forIdentifier: Self.energyIdentifier) else {
            return .notDetermined
        }
        return store.authorizationStatus(for: type)
    }

    // MARK: - Write

    /// Saves a meal to Apple Health as a `.food` correlation. Returns the correlation's
    /// HealthKit UUID (as a string) so it can be deleted later, or `nil` if nothing was
    /// written (e.g. all macro values were zero).
    @discardableResult
    func saveMeal(_ meal: Meal) async throws -> String? {
        guard isHealthDataAvailable else { throw HealthKitError.unavailable }
        guard let foodType = foodCorrelationType else { throw HealthKitError.typeUnavailable }

        var samples = Set<HKSample>()
        let date = meal.date

        func add(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, value: Double) {
            guard value > 0, let type = HKObjectType.quantityType(forIdentifier: identifier) else { return }
            let quantity = HKQuantity(unit: unit, doubleValue: value)
            samples.insert(HKQuantitySample(type: type, quantity: quantity, start: date, end: date))
        }

        add(Self.energyIdentifier, unit: .kilocalorie(), value: Double(meal.calories))
        add(Self.proteinIdentifier, unit: .gram(), value: meal.protein)
        add(Self.carbsIdentifier, unit: .gram(), value: meal.carbs)
        add(Self.fatIdentifier, unit: .gram(), value: meal.fat)

        guard !samples.isEmpty else { return nil }

        let metadata: [String: Any] = [
            HKMetadataKeyFoodType: meal.name
        ]
        let correlation = HKCorrelation(type: foodType, start: date, end: date, objects: samples, metadata: metadata)

        try await store.save(correlation)
        return correlation.uuid.uuidString
    }

    // MARK: - Delete

    /// Removes a previously written meal correlation from Apple Health. Best-effort —
    /// if the object can't be found (e.g. the user deleted it in Health) this is a no-op.
    func deleteMeal(healthKitFoodUUID: String) async throws {
        guard isHealthDataAvailable else { return }
        guard let foodType = foodCorrelationType, let uuid = UUID(uuidString: healthKitFoodUUID) else { return }

        let predicate = HKQuery.predicateForObject(with: uuid)

        let objects: [HKSample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: foodType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, results, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: results ?? [])
                }
            }
            store.execute(query)
        }

        guard !objects.isEmpty else { return }
        try await store.delete(objects)
    }

    // MARK: - Read: Weight (Phase 2)

    private static let kilogramUnit = HKUnit.gramUnit(with: .kilo)

    /// The user's preferred body-weight unit, taken from the Health app. Falls back to the
    /// device locale's measurement system if Health can't be queried.
    func preferredWeightUnit() async -> WeightUnit {
        guard isHealthDataAvailable, let type = HKObjectType.quantityType(forIdentifier: .bodyMass) else {
            return localeDefaultWeightUnit
        }
        guard let units = try? await store.preferredUnits(for: [type]), let unit = units[type] else {
            return localeDefaultWeightUnit
        }
        return unit == .pound() ? .pounds : .kilograms
    }

    private var localeDefaultWeightUnit: WeightUnit {
        Locale.current.measurementSystem == .us ? .pounds : .kilograms
    }

    /// Most recent body-mass measurement, in kilograms.
    func latestBodyMass() async -> (date: Date, kilograms: Double)? {
        guard let result = await latestQuantity(identifier: .bodyMass, unit: Self.kilogramUnit) else { return nil }
        return (date: result.date, kilograms: result.value)
    }

    /// All body-mass measurements over the trailing `days`, oldest first, in kilograms.
    func bodyMassSeries(days: Int) async -> [(date: Date, kilograms: Double)] {
        let samples = await quantitySamples(identifier: .bodyMass, days: days, unit: Self.kilogramUnit)
        return samples.map { (date: $0.date, kilograms: $0.value) }
    }

    // MARK: - Read: Activity / energy expenditure (Phase 2)

    /// Active energy burned per day (kcal) over the trailing `days`. Days with no data are omitted.
    func dailyActiveEnergy(days: Int) async -> [(date: Date, value: Double)] {
        await statisticsSeries(identifier: .activeEnergyBurned, unit: .kilocalorie(), days: days, options: .cumulativeSum)
    }

    /// Basal (resting) energy burned per day (kcal) over the trailing `days`.
    func dailyBasalEnergy(days: Int) async -> [(date: Date, value: Double)] {
        await statisticsSeries(identifier: .basalEnergyBurned, unit: .kilocalorie(), days: days, options: .cumulativeSum)
    }

    /// Step count per day over the trailing `days`.
    func dailySteps(days: Int) async -> [(date: Date, value: Double)] {
        await statisticsSeries(identifier: .stepCount, unit: .count(), days: days, options: .cumulativeSum)
    }

    /// Bucketed step totals for trend sparklines/charts (`intervalDays`: 1 daily, 7 weekly).
    func stepsSeries(days: Int, intervalDays: Int) async -> [(date: Date, value: Double)] {
        await statisticsSeries(identifier: .stepCount, unit: .count(), days: days, options: .cumulativeSum, intervalDays: intervalDays)
    }

    /// Bucketed active-energy totals (kcal) for trend sparklines/charts.
    func activeEnergySeries(days: Int, intervalDays: Int) async -> [(date: Date, value: Double)] {
        await statisticsSeries(identifier: .activeEnergyBurned, unit: .kilocalorie(), days: days, options: .cumulativeSum, intervalDays: intervalDays)
    }

    /// Number of recorded workouts over the trailing `days`.
    func workoutCount(days: Int) async -> Int {
        guard isHealthDataAvailable else { return 0 }
        guard let startDate = trailingStart(days: days) else { return 0 }
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: nil, options: .strictStartDate)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, results, _ in
                continuation.resume(returning: results?.count ?? 0)
            }
            store.execute(query)
        }
    }

    // MARK: - Read: Cardiovascular (Phase 2)

    private static let bpmUnit = HKUnit.count().unitDivided(by: .minute())
    private static let hrvUnit = HKUnit.secondUnit(with: .milli)
    // mL/(kg·min). Built explicitly — HKUnit(from:) parses left-to-right with no operator
    // precedence, so "ml/kg*min" would wrongly evaluate as (ml/kg)*min.
    private static let vo2Unit = HKUnit.literUnit(with: .milli)
        .unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: .minute()))

    func latestRestingHeartRate() async -> (date: Date, value: Double)? {
        await latestQuantity(identifier: .restingHeartRate, unit: Self.bpmUnit)
    }

    func latestHRV() async -> (date: Date, value: Double)? {
        await latestQuantity(identifier: .heartRateVariabilitySDNN, unit: Self.hrvUnit)
    }

    func latestVO2Max() async -> (date: Date, value: Double)? {
        await latestQuantity(identifier: .vo2Max, unit: Self.vo2Unit)
    }

    func latestCardioRecovery() async -> (date: Date, value: Double)? {
        await latestQuantity(identifier: .heartRateRecoveryOneMinute, unit: Self.bpmUnit)
    }

    /// Bucketed trend series for the cardio metrics, used for the tile sparklines and the
    /// tap-through detail charts (`intervalDays`: 1 daily, 7 weekly). Sparse metrics
    /// (VO₂ max, recovery) simply yield fewer points.
    func restingHeartRateSeries(days: Int, intervalDays: Int) async -> [(date: Date, value: Double)] {
        await statisticsSeries(identifier: .restingHeartRate, unit: Self.bpmUnit, days: days, options: .discreteAverage, intervalDays: intervalDays)
    }

    func hrvSeries(days: Int, intervalDays: Int) async -> [(date: Date, value: Double)] {
        await statisticsSeries(identifier: .heartRateVariabilitySDNN, unit: Self.hrvUnit, days: days, options: .discreteAverage, intervalDays: intervalDays)
    }

    func vo2MaxSeries(days: Int, intervalDays: Int) async -> [(date: Date, value: Double)] {
        await statisticsSeries(identifier: .vo2Max, unit: Self.vo2Unit, days: days, options: .discreteAverage, intervalDays: intervalDays)
    }

    func cardioRecoverySeries(days: Int, intervalDays: Int) async -> [(date: Date, value: Double)] {
        await statisticsSeries(identifier: .heartRateRecoveryOneMinute, unit: Self.bpmUnit, days: days, options: .discreteAverage, intervalDays: intervalDays)
    }

    // MARK: - Read: Query primitives

    /// Start-of-day `days-1` days ago, so the trailing window includes today — mirroring
    /// `MealRepository.dailyCaloriesForRange(days:)` and the Trends calorie chart.
    private func trailingStart(days: Int) -> Date? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .day, value: -(days - 1), to: today)
    }

    /// Latest single sample for a quantity type, converted to `unit`.
    private func latestQuantity(identifier: HKQuantityTypeIdentifier, unit: HKUnit) async -> (date: Date, value: Double)? {
        guard isHealthDataAvailable, let type = HKObjectType.quantityType(forIdentifier: identifier) else { return nil }
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: sort) { _, results, _ in
                guard let sample = results?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: (sample.endDate, sample.quantity.doubleValue(for: unit)))
            }
            store.execute(query)
        }
    }

    /// Raw quantity samples over the trailing window, oldest first.
    private func quantitySamples(identifier: HKQuantityTypeIdentifier, days: Int, unit: HKUnit) async -> [(date: Date, value: Double)] {
        guard isHealthDataAvailable,
              let type = HKObjectType.quantityType(forIdentifier: identifier),
              let startDate = trailingStart(days: days) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: nil, options: .strictStartDate)
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: sort) { _, results, _ in
                let samples = (results as? [HKQuantitySample]) ?? []
                continuation.resume(returning: samples.map { ($0.startDate, $0.quantity.doubleValue(for: unit)) })
            }
            store.execute(query)
        }
    }

    /// One value per bucket over the trailing window, via `HKStatisticsCollectionQuery`.
    /// `intervalDays` sets the bucket size (1 = daily, 7 = weekly — used to keep long-range
    /// sparklines/charts readable). `options` selects the aggregation: `.cumulativeSum` for
    /// energy/steps, `.discreteAverage` for rates like resting HR. Empty buckets are omitted.
    private func statisticsSeries(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        days: Int,
        options: HKStatisticsOptions,
        intervalDays: Int = 1
    ) async -> [(date: Date, value: Double)] {
        guard isHealthDataAvailable,
              let type = HKObjectType.quantityType(forIdentifier: identifier),
              let startDate = trailingStart(days: days) else { return [] }
        let calendar = Calendar.current
        let endDate = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date()))!
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: options,
                anchorDate: startDate,
                intervalComponents: DateComponents(day: intervalDays)
            )
            query.initialResultsHandler = { _, results, _ in
                guard let results else {
                    continuation.resume(returning: [])
                    return
                }
                var points: [(date: Date, value: Double)] = []
                results.enumerateStatistics(from: startDate, to: endDate) { stat, _ in
                    let quantity = options.contains(.cumulativeSum) ? stat.sumQuantity() : stat.averageQuantity()
                    if let quantity {
                        points.append((stat.startDate, quantity.doubleValue(for: unit)))
                    }
                }
                continuation.resume(returning: points)
            }
            store.execute(query)
        }
    }

    /// Workout counts per bucket over the trailing window. Unlike the quantity series, empty
    /// buckets are kept as `0` — a week with no workouts is meaningful in the trend.
    func workoutCountsSeries(days: Int, intervalDays: Int) async -> [(date: Date, value: Double)] {
        guard isHealthDataAvailable, let startDate = trailingStart(days: days), intervalDays > 0 else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: nil, options: .strictStartDate)
        let starts: [Date] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, results, _ in
                continuation.resume(returning: (results as? [HKWorkout])?.map(\.startDate) ?? [])
            }
            store.execute(query)
        }

        let calendar = Calendar.current
        let bucketCount = max(1, Int(ceil(Double(days) / Double(intervalDays))))
        var buckets = [(date: Date, value: Double)]()
        for index in 0..<bucketCount {
            let date = calendar.date(byAdding: .day, value: index * intervalDays, to: startDate) ?? startDate
            buckets.append((date: date, value: 0))
        }
        for start in starts {
            let dayOffset = calendar.dateComponents([.day], from: startDate, to: start).day ?? 0
            let bucket = min(max(dayOffset / intervalDays, 0), bucketCount - 1)
            buckets[bucket].value += 1
        }
        return buckets
    }
}

enum HealthKitError: LocalizedError {
    case unavailable
    case typeUnavailable

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Apple Health is not available on this device."
        case .typeUnavailable:
            return "The required Health data type could not be created."
        }
    }
}
