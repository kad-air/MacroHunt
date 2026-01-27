// Utilities/CredentialsManager.swift
import Foundation
import SwiftUI
import Combine

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
