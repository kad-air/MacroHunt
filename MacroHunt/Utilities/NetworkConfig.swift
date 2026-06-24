// Utilities/NetworkConfig.swift
import Foundation

enum NetworkConfig {
    /// Interactive URLSession for user-facing requests: meal analysis (Claude Sonnet
    /// vision) and Craft sync. Timeouts are sized for a multi-image vision call, which
    /// legitimately needs tens of seconds for time-to-first-token plus image upload.
    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60  // 60s between data packets (vision TTFT can be slow)
        config.timeoutIntervalForResource = 120 // 120s total (for multi-image uploads)
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }()

    /// Separate URLSession for the background daily reflection (Claude Opus).
    ///
    /// The reflection runs on the slow Opus model and auto-fires when the Today tab
    /// appears. Sharing the interactive `session` made both Anthropic requests coalesce
    /// onto a single HTTP/2 connection to api.anthropic.com — so a reflection in flight
    /// could starve the user-facing analyze request's data frames and trip its request
    /// timeout (the food analyzer "timing out" regression introduced in Phase 3). Its own
    /// session gives the reflection its own connection, so it can never compete with
    /// analysis. It's also lower priority and gets a longer leash since it's not blocking
    /// anything the user is waiting on.
    static let reflectionSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 180 // Opus is slow; nothing is blocked on it
        config.waitsForConnectivity = true
        config.networkServiceType = .background
        return URLSession(configuration: config)
    }()

    /// Maximum image size to send to Claude (2MB per image)
    static let maxImageSize = 2 * 1024 * 1024

    /// Retry configuration
    static let maxRetries = 3
    static let retryBaseDelay: TimeInterval = 1.0
}
