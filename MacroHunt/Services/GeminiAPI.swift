// Services/GeminiAPI.swift
import Foundation

class GeminiAPI {
    let apiKey: String

    private static let baseURL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent"

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    /// Analyzes meal photos and returns nutritional information
    /// - Parameters:
    ///   - images: Array of JPEG image data
    ///   - description: Optional user description of the meal
    ///   - mealType: The type of meal (breakfast, lunch, dinner, snack)
    /// - Returns: NutritionAnalysis with estimated nutritional values
    func analyzeMealPhotos(images: [Data], description: String, mealType: MealType) async throws -> NutritionAnalysis {
        guard let url = URL(string: Self.baseURL) else {
            throw APIError.invalidURL(Self.baseURL)
        }

        // Build the prompt
        let promptText = """
        Analyze these meal photos and estimate nutritional content.
        User description: \(description.isEmpty ? "No description provided" : description)
        Meal type: \(mealType.rawValue)

        Return ONLY valid JSON with these exact keys:
        - mealName: A descriptive name for this meal (string, 2-5 words)
        - calories: Estimated total calories (integer)
        - protein: Grams of protein (number, one decimal place)
        - carbs: Grams of carbohydrates (number, one decimal place)
        - fat: Grams of fat (number, one decimal place)
        - keyNutrients: Notable vitamins/minerals present, comma-separated (string)

        Be realistic with portions shown in photos. If multiple items visible, sum the totals.
        If you cannot identify the food, make your best estimate based on what you see.

        Example response:
        {"mealName": "Grilled Chicken Salad", "calories": 450, "protein": 35.0, "carbs": 20.5, "fat": 25.0, "keyNutrients": "Vitamin A, Vitamin C, Iron, Fiber"}
        """

        // Build multimodal request with images
        var parts: [[String: Any]] = [["text": promptText]]

        // Add each image as base64-encoded inline data
        for imageData in images {
            let base64String = imageData.base64EncodedString()
            parts.append([
                "inline_data": [
                    "mime_type": "image/jpeg",
                    "data": base64String
                ]
            ])
        }

        let requestBody: [String: Any] = [
            "contents": [
                ["parts": parts]
            ],
            "generationConfig": [
                "temperature": 0.3,
                "maxOutputTokens": 500
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await NetworkConfig.session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.noData
        }

        if httpResponse.statusCode != 200 {
            let errorBody = parseGeminiError(from: data) ?? String(data: data, encoding: .utf8) ?? "Unknown error"

            switch httpResponse.statusCode {
            case 429:
                throw APIError.rateLimited
            case 500...599:
                throw APIError.serverError(httpResponse.statusCode)
            default:
                throw APIError.httpError(statusCode: httpResponse.statusCode, body: errorBody)
            }
        }

        // Parse Gemini response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let responseParts = content["parts"] as? [[String: Any]],
              let firstPart = responseParts.first,
              let text = firstPart["text"] as? String else {
            let errorMessage = parseGeminiError(from: data) ?? "Unexpected response format"
            throw APIError.decodingError("Unexpected Gemini response: \(errorMessage)")
        }

        // Clean up markdown code blocks
        let cleanedText = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let jsonData = cleanedText.data(using: .utf8) else {
            throw APIError.decodingError("Failed to encode response as UTF-8")
        }

        do {
            let analysis = try JSONDecoder().decode(NutritionAnalysis.self, from: jsonData)
            return analysis
        } catch {
            throw APIError.decodingError("Failed to parse nutrition analysis: \(cleanedText.prefix(200))")
        }
    }

    private func parseGeminiError(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any] else {
            return nil
        }

        var message = ""

        if let errorMessage = error["message"] as? String {
            message = errorMessage
        }

        if let status = error["status"] as? String {
            message = message.isEmpty ? status : "\(status): \(message)"
        }

        return message.isEmpty ? nil : message
    }
}
