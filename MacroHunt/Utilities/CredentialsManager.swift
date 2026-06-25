// Utilities/CredentialsManager.swift
import Foundation
import SwiftUI
import Combine

enum MacroSplit: String, CaseIterable, Identifiable {
    case balanced = "balanced"
    case lowCarb = "lowCarb"
    case highProtein = "highProtein"
    case custom = "custom"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .balanced: return "Balanced"
        case .lowCarb: return "Low Carb"
        case .highProtein: return "High Protein"
        case .custom: return "Custom"
        }
    }

    var description: String {
        switch self {
        case .balanced: return "20% protein, 50% carbs, 30% fat"
        case .lowCarb: return "25% protein, 20% carbs, 55% fat"
        case .highProtein: return "35% protein, 40% carbs, 25% fat"
        case .custom: return "Your own protein, carbs & fat targets"
        }
    }

    /// Fixed macro ratios (protein, carbs, fat) as decimals of total calories. `nil` for
    /// `.custom`, whose ratios come from the user-set percentages on `CredentialsManager`.
    /// Balanced and High Protein sit inside the Institute of Medicine's Acceptable
    /// Macronutrient Distribution Ranges (protein 10–35%, carbs 45–65%, fat 20–35%); Low
    /// Carb is intentionally carb-restricted below that range with fat raised to compensate.
    var presetRatios: (protein: Double, carbs: Double, fat: Double)? {
        switch self {
        case .balanced:    return (0.20, 0.50, 0.30)
        case .highProtein: return (0.35, 0.40, 0.25)
        case .lowCarb:     return (0.25, 0.20, 0.55)
        case .custom:      return nil
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

    /// User-defined macro percentages (whole-number percent of daily calories) used only
    /// when `macroSplit == .custom`. Resolved and normalized via `macroRatios`.
    @Published var customProteinPct: Int {
        didSet {
            guard !isInitializing else { return }
            defaults?.set(customProteinPct, forKey: "customProteinPct")
        }
    }

    @Published var customCarbsPct: Int {
        didSet {
            guard !isInitializing else { return }
            defaults?.set(customCarbsPct, forKey: "customCarbsPct")
        }
    }

    @Published var customFatPct: Int {
        didSet {
            guard !isInitializing else { return }
            defaults?.set(customFatPct, forKey: "customFatPct")
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

    /// Opt-out: mirror logged meals to Craft Docs. Defaults on so existing users keep
    /// syncing after an update. Only has an effect when Craft is fully configured
    /// (`isCraftConfigured`); `craftSyncActive` combines the two. Turning this off — or
    /// simply never configuring Craft — lets meal logging and AI analysis work on their own.
    @Published var craftSyncEnabled: Bool {
        didSet {
            guard !isInitializing else { return }
            defaults?.set(craftSyncEnabled, forKey: "craftSyncEnabled")
        }
    }

    /// Whether a weight target has been set (non-zero).
    var hasWeightGoal: Bool { weightGoalKg > 0 }

    /// Active macro ratios (protein, carbs, fat) as decimals of the calorie goal: the
    /// preset's fixed split, or the user's custom percentages when `macroSplit == .custom`.
    /// Custom percentages are normalized to sum to 1 so the three macro goals always add up
    /// to the calorie goal even if the entered numbers don't total exactly 100%.
    var macroRatios: (protein: Double, carbs: Double, fat: Double) {
        if let preset = macroSplit.presetRatios { return preset }
        let p = Double(max(customProteinPct, 0))
        let c = Double(max(customCarbsPct, 0))
        let f = Double(max(customFatPct, 0))
        let total = p + c + f
        guard total > 0 else { return (0.20, 0.50, 0.30) } // all-zero falls back to balanced
        return (p / total, c / total, f / total)
    }

    // Computed macro goals based on calorie goal and split
    var proteinGoal: Int {
        let calories = Double(dailyCalorieGoal) * macroRatios.protein
        return Int(calories / 4.0) // 4 cal per gram of protein
    }

    var carbsGoal: Int {
        let calories = Double(dailyCalorieGoal) * macroRatios.carbs
        return Int(calories / 4.0) // 4 cal per gram of carbs
    }

    var fatGoal: Int {
        let calories = Double(dailyCalorieGoal) * macroRatios.fat
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

        // Custom macro percentages (only consulted when macroSplit == .custom). Default to a
        // 30/40/30 starting point; object(forKey:) distinguishes "unset" from a stored 0.
        self.customProteinPct = defaults?.object(forKey: "customProteinPct") as? Int ?? 30
        self.customCarbsPct = defaults?.object(forKey: "customCarbsPct") as? Int ?? 40
        self.customFatPct = defaults?.object(forKey: "customFatPct") as? Int ?? 30

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

        // Craft sync defaults on (so existing users keep syncing after this update), but
        // honor a stored "off".
        self.craftSyncEnabled = defaults?.object(forKey: "craftSyncEnabled") as? Bool ?? true

        // Done initializing - future changes will save
        isInitializing = false
    }

    /// True when every credential — both AI and Craft — is filled in. Used only as a
    /// "fully set up" indicator; it does **not** gate meal logging. AI analysis needs only
    /// `isAIConfigured`, and Craft sync needs only `craftSyncActive`.
    var isValid: Bool {
        isAIConfigured && isCraftConfigured
    }

    /// AI meal analysis (and reflections) need only the Anthropic key. This is what gates
    /// logging — a user can analyze and save meals locally without ever touching Craft.
    var isAIConfigured: Bool {
        !anthropicKey.isEmpty
    }

    /// Craft Docs sync needs all three Craft fields. Independent of the AI key.
    var isCraftConfigured: Bool {
        !craftToken.isEmpty && !spaceId.isEmpty && !collectionId.isEmpty
    }

    /// Whether meals should actually be mirrored to Craft: the user has opted in *and* Craft
    /// is configured. This is the single gate the repository checks.
    var craftSyncActive: Bool {
        craftSyncEnabled && isCraftConfigured
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
