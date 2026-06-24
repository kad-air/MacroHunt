// Services/ClaudeAPI.swift
import Foundation

class ClaudeAPI {
    let apiKey: String

    // Flip to "claude-opus-4-8" for maximum accuracy — slower, and ~$1/month more
    // at personal logging volume. Sonnet 4.6 is the right tier for this extraction task.
    private static let model = "claude-sonnet-4-6"
    // The daily reflection is a single, quality-sensitive call — run it on Opus.
    private static let coachingModel = "claude-opus-4-8"
    private static let baseURL = "https://api.anthropic.com/v1/messages"
    private static let anthropicVersion = "2023-06-01"

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    /// Analyzes a meal from photos, a text description, or both, and returns nutritional information
    /// - Parameters:
    ///   - images: Array of JPEG image data (may be empty if a description is provided)
    ///   - description: User description of the meal (may be empty if images are provided)
    ///   - mealType: The type of meal (breakfast, lunch, dinner, snack)
    /// - Returns: NutritionAnalysis with estimated nutritional values
    func analyzeMealPhotos(images: [Data], description: String, mealType: MealType) async throws -> NutritionAnalysis {
        guard let url = URL(string: Self.baseURL) else {
            throw APIError.invalidURL(Self.baseURL)
        }

        let hasImages = !images.isEmpty
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)

        // Adapt the prompt to whether photos, a description, or both were provided.
        let intro: String
        let guidance: String
        if hasImages {
            intro = "Analyze this meal and estimate its nutritional content. Use the photo(s) provided"
                + (trimmedDescription.isEmpty ? "." : " together with the user's description.")
            guidance = """
            Be realistic with the portions shown in the photos. If multiple items are visible, sum the totals. \
            If you cannot identify a food, make your best estimate from what you see and the description.
            """
        } else {
            intro = "Estimate the nutritional content of this meal based solely on the user's description below."
            guidance = """
            No photo was provided, so estimate from the description alone. Assume typical restaurant or homemade \
            portions when an exact amount isn't given. If multiple items are described, sum the totals. Make your \
            best realistic estimate.
            """
        }

        let promptText = """
        \(intro)
        User description: \(trimmedDescription.isEmpty ? "No description provided" : trimmedDescription)
        Meal type: \(mealType.rawValue)

        \(guidance)
        Give mealName as a short descriptive name (2-5 words), and keyNutrients as notable vitamins/minerals, comma-separated.
        """

        // One user turn: the prompt text followed by each image as an inline base64 block.
        var content: [[String: Any]] = [["type": "text", "text": promptText]]
        for imageData in images {
            content.append([
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": "image/jpeg",
                    "data": imageData.base64EncodedString()
                ]
            ])
        }

        // Structured outputs guarantee schema-valid JSON — no markdown cleanup or
        // "return ONLY JSON" prompting needed. Schema mirrors NutritionAnalysis.
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "mealName": ["type": "string"],
                "calories": ["type": "integer"],
                "protein": ["type": "number"],
                "carbs": ["type": "number"],
                "fat": ["type": "number"],
                "keyNutrients": ["type": "string"]
            ],
            "required": ["mealName", "calories", "protein", "carbs", "fat", "keyNutrients"],
            "additionalProperties": false
        ]

        let requestBody: [String: Any] = [
            "model": Self.model,
            "max_tokens": 1024,
            "messages": [
                ["role": "user", "content": content]
            ],
            "output_config": [
                "format": [
                    "type": "json_schema",
                    "schema": schema
                ]
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.addValue(Self.anthropicVersion, forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await NetworkConfig.session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.noData
        }

        if httpResponse.statusCode != 200 {
            let errorBody = parseAnthropicError(from: data) ?? String(data: data, encoding: .utf8) ?? "Unknown error"

            switch httpResponse.statusCode {
            case 429:
                throw APIError.rateLimited
            case 500...599:
                throw APIError.serverError(httpResponse.statusCode)
            default:
                throw APIError.httpError(statusCode: httpResponse.statusCode, body: errorBody)
            }
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.decodingError("Unexpected Claude response: not a JSON object")
        }

        // A safety refusal returns HTTP 200 with stop_reason "refusal" and no usable content.
        if let stopReason = json["stop_reason"] as? String, stopReason == "refusal" {
            throw APIError.decodingError("The model declined to analyze these photos.")
        }

        // With output_config.format, the first text block holds schema-valid JSON.
        guard let contentBlocks = json["content"] as? [[String: Any]],
              let text = contentBlocks.first(where: { ($0["type"] as? String) == "text" })?["text"] as? String,
              let jsonData = text.data(using: .utf8) else {
            let errorMessage = parseAnthropicError(from: data) ?? "Unexpected response format"
            throw APIError.decodingError("Unexpected Claude response: \(errorMessage)")
        }

        do {
            return try JSONDecoder().decode(NutritionAnalysis.self, from: jsonData)
        } catch {
            throw APIError.decodingError("Failed to parse nutrition analysis: \(text.prefix(200))")
        }
    }

    // MARK: - Daily Reflection (Phase 3 coaching)

    /// Generates a supportive daily reflection from a compact snapshot of the user's
    /// recent intake, goals, and Apple Health trends. Uses Opus for this single,
    /// quality-sensitive call (meal analysis stays on Sonnet). Tone is enforced via the
    /// system prompt: curious and encouraging, never shaming, food framed neutrally, one
    /// gentle suggestion — and explicitly not medical advice.
    func generateReflection(context: String) async throws -> CoachingReflection {
        guard let url = URL(string: Self.baseURL) else {
            throw APIError.invalidURL(Self.baseURL)
        }

        let system = """
        You are a warm, perceptive nutrition companion inside a personal meal-logging app. \
        You write a short daily reflection from the user's own logs and Apple Health data.

        Voice and rules:
        - Supportive, curious, and human. Acknowledge effort. Never shame or scold.
        - Food is neutral — there are no "good" or "bad" foods, and no guilt.
        - Surface patterns gently and concretely, citing the user's real numbers.
        - Offer exactly ONE small, actionable idea — never a list of demands.
        - This is NOT medical advice. Avoid anything diagnostic, especially around heart \
          metrics or rate of weight change. If data is sparse, say so kindly rather than overreaching.
        - Write in second person ("you"). Keep it concise and specific to the data given.

        Return:
        - headline: one encouraging sentence summarizing the week (no period required).
        - observations: 2–4 short, specific observations grounded in the numbers.
        - suggestion: one gentle, optional idea for today.
        - encouragement: one closing line that recognizes their effort.
        """

        let userText = """
        Here is the user's recent snapshot. Write today's reflection.

        \(context)
        """

        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "headline": ["type": "string"],
                "observations": [
                    "type": "array",
                    "items": ["type": "string"],
                    "minItems": 1,
                    "maxItems": 4
                ],
                "suggestion": ["type": "string"],
                "encouragement": ["type": "string"]
            ],
            "required": ["headline", "observations", "suggestion", "encouragement"],
            "additionalProperties": false
        ]

        let requestBody: [String: Any] = [
            "model": Self.coachingModel,
            "max_tokens": 1024,
            "system": system,
            "messages": [
                ["role": "user", "content": [["type": "text", "text": userText]]]
            ],
            "output_config": [
                "format": [
                    "type": "json_schema",
                    "schema": schema
                ]
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.addValue(Self.anthropicVersion, forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await NetworkConfig.session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.noData
        }

        if httpResponse.statusCode != 200 {
            let errorBody = parseAnthropicError(from: data) ?? String(data: data, encoding: .utf8) ?? "Unknown error"
            switch httpResponse.statusCode {
            case 429:
                throw APIError.rateLimited
            case 500...599:
                throw APIError.serverError(httpResponse.statusCode)
            default:
                throw APIError.httpError(statusCode: httpResponse.statusCode, body: errorBody)
            }
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.decodingError("Unexpected Claude response: not a JSON object")
        }

        if let stopReason = json["stop_reason"] as? String, stopReason == "refusal" {
            throw APIError.decodingError("The model declined to write a reflection.")
        }

        guard let contentBlocks = json["content"] as? [[String: Any]],
              let text = contentBlocks.first(where: { ($0["type"] as? String) == "text" })?["text"] as? String,
              let jsonData = text.data(using: .utf8) else {
            let errorMessage = parseAnthropicError(from: data) ?? "Unexpected response format"
            throw APIError.decodingError("Unexpected Claude response: \(errorMessage)")
        }

        do {
            return try JSONDecoder().decode(CoachingReflection.self, from: jsonData)
        } catch {
            throw APIError.decodingError("Failed to parse reflection: \(text.prefix(200))")
        }
    }

    private func parseAnthropicError(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any] else {
            return nil
        }

        var message = ""
        if let errorMessage = error["message"] as? String {
            message = errorMessage
        }
        if let type = error["type"] as? String {
            message = message.isEmpty ? type : "\(type): \(message)"
        }
        return message.isEmpty ? nil : message
    }
}
