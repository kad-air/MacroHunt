// Utilities/NetworkConfig.swift
import Foundation

enum NetworkConfig {
    /// Interactive URLSession for user-facing requests: meal analysis (Claude vision) and
    /// Craft sync. Anthropic requests are non-streaming, so no bytes arrive until the model
    /// has finished thinking and answering; the per-request timeout has to cover that whole
    /// wait, not just time-to-first-byte of a streamed reply.
    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 90   // idle time between packets (covers the full model turn)
        config.timeoutIntervalForResource = 150 // total, including multi-image uploads
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }()

    /// Separate URLSession for the background daily reflection.
    ///
    /// Sharing the interactive `session` made both Anthropic requests coalesce onto a single
    /// HTTP/2 connection to api.anthropic.com — so a reflection in flight could starve the
    /// user-facing analyze request's data frames and trip its request timeout (the food
    /// analyzer "timing out" regression introduced in Phase 3). Its own session gives the
    /// reflection its own connection, so it can never compete with analysis. It's also lower
    /// priority and gets a longer leash since it's not blocking anything the user is waiting on.
    static let reflectionSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 240 // nothing is blocked on it
        config.waitsForConnectivity = true
        config.networkServiceType = .background
        return URLSession(configuration: config)
    }()

    /// Retry configuration (Craft)
    static let maxRetries = 3
    static let retryBaseDelay: TimeInterval = 1.0
}
