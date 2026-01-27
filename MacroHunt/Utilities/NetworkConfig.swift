// Utilities/NetworkConfig.swift
import Foundation

enum NetworkConfig {
    /// Custom URLSession with appropriate timeouts
    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30  // 30 seconds for request
        config.timeoutIntervalForResource = 60 // 60 seconds total (for image uploads)
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }()

    /// Maximum image size to send to Gemini (2MB per image)
    static let maxImageSize = 2 * 1024 * 1024

    /// Retry configuration
    static let maxRetries = 3
    static let retryBaseDelay: TimeInterval = 1.0
}
