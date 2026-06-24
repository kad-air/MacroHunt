// Utilities/CredentialsManager.swift
import Foundation
import SwiftUI
import Combine

enum MacroSplit: String, CaseIterable, Identifiable {
    case balanced = "balanced"
    case lowCarb = "lowCarb"
    case highProtein = "highProtein"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .balanced: return "Balanced"
        case .lowCarb: return "Low Carb"
        case .highProtein: return "High Protein"
        }
    }

    var description: String {
        switch self {
        case .balanced: return "30% protein, 40% carbs, 30% fat"
        case .lowCarb: return "40% protein, 20% carbs, 40% fat"
        case .highProtein: return "35% protein, 40% carbs, 25% fat"
        }
    }

    // Returns (protein%, carbs%, fat%) as decimals
    var ratios: (protein: Double, carbs: Double, fat: Double) {
        switch self {
        case .balanced: return (0.30, 0.40, 0.30)
        case .lowCarb: return (0.40, 0.20, 0.40)
        case .highProtein: return (0.35, 0.40, 0.25)
        }
    }
}

/// Display unit for body weight. The canonical store is always kilograms (matching
/// HealthKit's internal unit); this only governs presentation/entry. The active unit is
/// resolved from the user's Health app preference at display time — see
/// `HealthKitService.preferredWeightUnit()`.
enum WeightUnit: String {
    case kilograms
    case pounds

    var abbreviation: String {
        switch self {
        case .kilograms: return "kg"
        case .pounds: return "lb"
        }
    }

    private static let poundsPerKilogram = 2.2046226218

    /// Converts a value expressed in this unit into canonical kilograms.
    func toKilograms(_ value: Double) -> Double {
        switch self {
        case .kilograms: return value
        case .pounds: return value / Self.poundsPerKilogram
        }
    }

    /// Converts canonical kilograms into a value expressed in this unit.
    func fromKilograms(_ kilograms: Double) -> Double {
        switch self {
        case .kilograms: return kilograms
        case .pounds: return kilograms * Self.poundsPerKilogram
        }
    }
}

/// Which way the user wants their weight to move. Frames the weight-trend chart and
/// (Phase 3) coaching tone.
enum WeightGoalDirection: String, CaseIterable, Identifiable {
    case lose
    case maintain
    case gain

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .lose: return "Lose"
        case .maintain: return "Maintain"
        case .gain: return "Gain"
        }
    }
}

class CredentialsManager: ObservableObject {
    static let suiteName = "group.kad-air.MacroHunt"

    private let defaults: UserDefaults?
    private let keychain = KeychainHelper.shared
    private let service = "com.kad-air.MacroHunt"
    private var isInitializing = true

    let isAppGroupAvailable: Bool

    @Published private(set) var lastKeychainError: Bool = false

    @Published var craftToken: String {
        didSet {
            guard !isInitializing else { return }
            let success = keychain.save(craftToken, service: service, account: "craftToken")
            lastKeychainError = !success
        }
    }

    @Published var spaceId: String {
        didSet {
            guard !isInitializing else { return }
            defaults?.set(spaceId, forKey: "spaceId")
        }
    }

    @Published var anthropicKey: String {
        didSet {
            guard !isInitializing else { return }
            let success = keychain.save(anthropicKey, service: service, account: "anthropicKey")
            lastKeychainError = !success
        }
    }

    @Published var collectionId: String {
        didSet {
            guard !isInitializing else { return }
            defaults?.set(collectionId, forKey: "collectionId")
        }
    }

    @Published var dailyCalorieGoal: Int {
        didSet {
            guard !isInitializing else { return }
            defaults?.set(dailyCalorieGoal, forKey: "dailyCalorieGoal")
        }
    }

    @Published var macroSplit: MacroSplit {
        didSet {
            guard !isInitializing else { return }
            defaults?.set(macroSplit.rawValue, forKey: "macroSplit")
        }
    }

    /// Opt-in: mirror logged meals into Apple Health. Independent of `isValid` (Craft/AI
    /// config); HealthKit sync works even without Craft configured. Defaults off.
    @Published var healthKitSyncEnabled: Bool {
        didSet {
            guard !isInitializing else { return }
            defaults?.set(healthKitSyncEnabled, forKey: "healthKitSyncEnabled")
        }
    }

    /// Target body weight in canonical kilograms. `0` means no goal set. Display/entry is
    /// converted to the user's preferred `WeightUnit` in the UI.
    @Published var weightGoalKg: Double {
        didSet {
            guard !isInitializing else { return }
            defaults?.set(weightGoalKg, forKey: "weightGoalKg")
        }
    }

    /// Direction the user wants their weight to move (lose/maintain/gain).
    @Published var weightGoalDirection: WeightGoalDirection {
        didSet {
            guard !isInitializing else { return }
            defaults?.set(weightGoalDirection.rawValue, forKey: "weightGoalDirection")
        }
    }

    /// Whether the AI "Daily reflection" coach surfaces on Today. Defaults on. Independent
    /// of `isValid`, though generating a reflection still needs a configured Anthropic key.
    @Published var dailyReflectionEnabled: Bool {
        didSet {
            guard !isInitializing else { return }
            defaults?.set(dailyReflectionEnabled, forKey: "dailyReflectionEnabled")
        }
    }

    /// Whether a weight target has been set (non-zero).
    var hasWeightGoal: Bool { weightGoalKg > 0 }

    // Computed macro goals based on calorie goal and split
    var proteinGoal: Int {
        let calories = Double(dailyCalorieGoal) * macroSplit.ratios.protein
        return Int(calories / 4.0) // 4 cal per gram of protein
    }

    var carbsGoal: Int {
        let calories = Double(dailyCalorieGoal) * macroSplit.ratios.carbs
        return Int(calories / 4.0) // 4 cal per gram of carbs
    }

    var fatGoal: Int {
        let calories = Double(dailyCalorieGoal) * macroSplit.ratios.fat
        return Int(calories / 9.0) // 9 cal per gram of fat
    }

    init() {
        let defaults = UserDefaults(suiteName: Self.suiteName)
        self.defaults = defaults
        self.isAppGroupAvailable = defaults != nil

        // Load from storage (didSet guards prevent re-saving during init)
        self.craftToken = keychain.read(service: service, account: "craftToken") ?? ""
        self.spaceId = defaults?.string(forKey: "spaceId") ?? ""
        self.anthropicKey = keychain.read(service: service, account: "anthropicKey") ?? ""
        self.collectionId = defaults?.string(forKey: "collectionId") ?? ""
        self.dailyCalorieGoal = defaults?.integer(forKey: "dailyCalorieGoal") ?? 2000

        // Load macro split (default to balanced)
        if let splitRaw = defaults?.string(forKey: "macroSplit"),
           let split = MacroSplit(rawValue: splitRaw) {
            self.macroSplit = split
        } else {
            self.macroSplit = .balanced
        }

        self.healthKitSyncEnabled = defaults?.bool(forKey: "healthKitSyncEnabled") ?? false
        self.weightGoalKg = defaults?.double(forKey: "weightGoalKg") ?? 0

        if let directionRaw = defaults?.string(forKey: "weightGoalDirection"),
           let direction = WeightGoalDirection(rawValue: directionRaw) {
            self.weightGoalDirection = direction
        } else {
            self.weightGoalDirection = .maintain
        }

        // Daily reflection defaults on, but honor a stored "off".
        self.dailyReflectionEnabled = defaults?.object(forKey: "dailyReflectionEnabled") as? Bool ?? true

        // Done initializing - future changes will save
        isInitializing = false
    }

    var isValid: Bool {
        !craftToken.isEmpty && !spaceId.isEmpty && !anthropicKey.isEmpty && !collectionId.isEmpty
    }

    var configurationError: String? {
        if !isAppGroupAvailable {
            return "App Group is not configured. Please enable '\(Self.suiteName)' in Xcode."
        }
        if lastKeychainError {
            return "Failed to save credentials to Keychain."
        }
        return nil
    }

    func clearKeychainCredentials() {
        keychain.delete(service: service, account: "craftToken")
        keychain.delete(service: service, account: "anthropicKey")
        craftToken = ""
        anthropicKey = ""
    }
}
