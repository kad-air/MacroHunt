// Utilities/APIError.swift
import Foundation

enum APIError: LocalizedError {
    case invalidURL(String)
    case invalidResponse
    case httpError(statusCode: Int, body: String)
    case networkError(Error)
    case decodingError(String)
    case emptyResponse
    case rateLimited
    case serverError(Int)
    /// The model (and any server-side fallback) declined; the associated text is user-facing.
    case refused(String)
    /// The response hit `max_tokens` before the answer finished.
    case truncated

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return "Invalid URL: \(url)"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let code, let body):
            return "HTTP \(code): \(body.prefix(100))"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError(let detail):
            return "Failed to parse response: \(detail)"
        case .emptyResponse:
            return "Empty response from server"
        case .rateLimited:
            return "Rate limited. Please try again later."
        case .serverError(let code):
            return "Server error (\(code)). Please try again."
        case .refused(let message):
            return message
        case .truncated:
            return "Claude's answer was cut off before it finished. Please try again."
        }
    }
}
