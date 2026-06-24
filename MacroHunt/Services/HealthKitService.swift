// Services/HealthKitService.swift
import Foundation
import HealthKit

/// Writes logged meals into Apple Health as dietary nutrition samples.
///
/// Phase 1 of the HealthKit integration: **write-only**. Each `Meal` is saved as an
/// `HKCorrelation` of type `.food` bundling the energy + macro quantity samples that
/// already live on the model, so the meal appears as a single entry in Apple Health's
/// nutrition log and can be read by other apps (Fitness, etc.).
///
/// All work is best-effort and gated by the user's opt-in toggle in Settings — a
/// HealthKit failure (denied permission, unavailable device) must never block meal
/// logging. See `MealRepository.saveMealWithSync`.
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
        if let food = foodCorrelationType {
            types.insert(food)
        }
        return types
    }

    // MARK: - Authorization

    /// Requests permission to write nutrition data. Phase 1 reads nothing.
    func requestAuthorization() async throws {
        guard isHealthDataAvailable else { throw HealthKitError.unavailable }
        try await store.requestAuthorization(toShare: nutritionTypesToShare, read: [])
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
