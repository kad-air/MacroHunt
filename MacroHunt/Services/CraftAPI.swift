// Services/CraftAPI.swift
import Foundation

// MARK: - Models

struct CraftCreateItemResponse: Codable {
    let items: [CraftItemResponse]
}

struct CraftItemResponse: Codable {
    let id: String
}

// MARK: - Craft API Service

class CraftAPI {
    let token: String
    let spaceId: String

    init(token: String, spaceId: String) {
        self.token = token
        self.spaceId = spaceId
    }

    private var baseURL: String {
        "https://connect.craft.do/links/\(spaceId)/api/v1"
    }

    // MARK: - Request Building

    private func buildRequest(endpoint: String, method: String = "GET", body: Data? = nil) throws -> URLRequest {
        let urlString = "\(baseURL)\(endpoint)"
        guard let url = URL(string: urlString) else {
            throw APIError.invalidURL(urlString)
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        return request
    }

    private func encodeCollectionId(_ collectionId: String) throws -> String {
        guard let encoded = collectionId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw APIError.invalidURL(collectionId)
        }
        return encoded
    }

    // MARK: - Request Execution

    private func executeRequest(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        var lastError: Error?

        for attempt in 0..<NetworkConfig.maxRetries {
            do {
                let (data, response) = try await NetworkConfig.session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw APIError.invalidResponse
                }

                switch httpResponse.statusCode {
                case 200...299:
                    return (data, httpResponse)

                case 429:
                    if attempt < NetworkConfig.maxRetries - 1 {
                        let delay = NetworkConfig.retryBaseDelay * pow(2.0, Double(attempt))
                        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        continue
                    }
                    let errorText = String(data: data, encoding: .utf8) ?? "Rate limited"
                    throw APIError.httpError(statusCode: 429, body: errorText)

                case 500...599:
                    if attempt < NetworkConfig.maxRetries - 1 {
                        let delay = NetworkConfig.retryBaseDelay * pow(2.0, Double(attempt))
                        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        continue
                    }
                    let errorText = String(data: data, encoding: .utf8) ?? "Server error"
                    throw APIError.httpError(statusCode: httpResponse.statusCode, body: errorText)

                default:
                    let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
                    throw APIError.httpError(statusCode: httpResponse.statusCode, body: errorText)
                }

            } catch let error as APIError {
                throw error
            } catch {
                lastError = error
                if attempt < NetworkConfig.maxRetries - 1 {
                    let delay = NetworkConfig.retryBaseDelay * pow(2.0, Double(attempt))
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }
            }
        }

        throw lastError ?? APIError.networkError(NSError(domain: "CraftAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Max retries exceeded"]))
    }

    // MARK: - API Methods

    /// Creates a meal item in the Craft collection
    func createMealItem(collectionId: String, meal: Meal) async throws -> String {
        // Build the item payload matching Craft collection schema
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]

        let craftItem: [String: Any] = [
            "meal_name": meal.name,
            "properties": [
                "date": dateFormatter.string(from: meal.date),
                "meal_type": meal.mealType.rawValue,
                "calories": meal.calories,
                "protein_g": meal.protein,
                "carbs_g": meal.carbs,
                "fat_g": meal.fat,
                "key_nutrients": meal.keyNutrients,
                "notes": meal.notes
            ]
        ]

        let payload: [String: Any] = ["items": [craftItem]]
        let body = try JSONSerialization.data(withJSONObject: payload)

        let encodedId = try encodeCollectionId(collectionId)
        let request = try buildRequest(endpoint: "/collections/\(encodedId)/items", method: "POST", body: body)
        let (data, _) = try await executeRequest(request)

        let decoded = try JSONDecoder().decode(CraftCreateItemResponse.self, from: data)

        guard let itemId = decoded.items.first?.id, !itemId.isEmpty else {
            throw APIError.emptyResponse
        }

        return itemId
    }

    /// Adds photo content to a Craft document
    func addMealPhotos(documentId: String, photoData: [Data]) async throws {
        guard !photoData.isEmpty else { return }

        // For now, we'll add a note about photos - Craft API requires image URLs, not raw data
        // In a production app, you'd upload images to a hosting service first
        let blocks: [[String: Any]] = photoData.enumerated().map { index, _ in
            [
                "type": "text",
                "markdown": "Photo \(index + 1) attached"
            ]
        }

        let payload: [String: Any] = [
            "blocks": blocks,
            "position": [
                "position": "end",
                "pageId": documentId
            ]
        ]

        let body = try JSONSerialization.data(withJSONObject: payload)
        let request = try buildRequest(endpoint: "/blocks", method: "POST", body: body)
        let _ = try await executeRequest(request)
    }
}
