// Utilities/APIError.swift
import Foundation

enum APIError: LocalizedError {
    case invalidURL(String)
    case invalidResponse
    case httpError(statusCode: Int, body: String)
    case networkError(Error)
    case decodingError(String)
    case noData
    case emptyResponse
    case rateLimited
    case serverError(Int)
    case cancelled

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
        case .noData:
            return "No data received"
        case .emptyResponse:
            return "Empty response from server"
        case .rateLimited:
            return "Rate limited. Please try again later."
        case .serverError(let code):
            return "Server error (\(code)). Please try again."
        case .cancelled:
            return "Request was cancelled"
        }
    }

    var isRetryable: Bool {
        switch self {
        case .rateLimited, .serverError:
            return true
        case .networkError(let error):
            return (error as NSError).code != NSURLErrorCancelled
        default:
            return false
        }
    }
}
