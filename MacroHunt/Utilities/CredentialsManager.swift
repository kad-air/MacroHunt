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

    @Published var geminiKey: String {
        didSet {
            guard !isInitializing else { return }
            let success = keychain.save(geminiKey, service: service, account: "geminiKey")
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
        self.geminiKey = keychain.read(service: service, account: "geminiKey") ?? ""
        self.collectionId = defaults?.string(forKey: "collectionId") ?? ""
        self.dailyCalorieGoal = defaults?.integer(forKey: "dailyCalorieGoal") ?? 2000

        // Load macro split (default to balanced)
        if let splitRaw = defaults?.string(forKey: "macroSplit"),
           let split = MacroSplit(rawValue: splitRaw) {
            self.macroSplit = split
        } else {
            self.macroSplit = .balanced
        }

        // Done initializing - future changes will save
        isInitializing = false
    }

    var isValid: Bool {
        !craftToken.isEmpty && !spaceId.isEmpty && !geminiKey.isEmpty && !collectionId.isEmpty
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
        keychain.delete(service: service, account: "geminiKey")
        craftToken = ""
        geminiKey = ""
    }
}
