// Services/ClaudeAPI.swift
import Foundation

class ClaudeAPI {
    let apiKey: String

    // Both calls run on the current Sonnet. Sonnet 5.5 always thinks adaptively — thinking
    // can be lowered with `effort` but not switched off — and thinking tokens count toward
    // `max_tokens` even though their text isn't returned, hence the generous cap below (the
    // old 1,024 would truncate the JSON mid-object). Flip `model` to "claude-opus-5-5" for
    // maximum accuracy at about twice the price.
    static let model = "claude-sonnet-5-5"
    /// Meal analysis is extraction-shaped and the user is waiting on it: keep thinking short.
    static let analysisEffort = "low"
    /// The reflection runs in the background after each logged meal, so a little more thought
    /// for spotting patterns across the week costs the user nothing.
    static let reflectionEffort = "medium"
    private static let maxTokens = 16_000
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let anthropicVersion = "2023-06-01"
    /// Beta header for server-side refusal fallback (`"fallbacks": "default"` in the body): if a
    /// safety classifier declines, the API re-runs the request on another model instead of
    /// returning the refusal. Harmless for food photos, and it keeps logging from dead-ending.
    private static let fallbackBeta = "server-side-fallback-2026-07-01"

    init(apiKey: String) {
        // A pasted key often carries a trailing newline or space, which the API rejects as an
        // invalid x-api-key.
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Analyzes a meal from photos, a text description, or both, and returns nutritional information
    /// - Parameters:
    ///   - images: JPEG payloads, already downsampled with `ImageDownsampler.analysisJPEG`
    ///     (may be empty if a description is provided)
    ///   - description: User description of the meal (may be empty if images are provided)
    ///   - mealType: The type of meal (breakfast, lunch, dinner, snack)
    /// - Returns: NutritionAnalysis with estimated nutritional values
    func analyzeMealPhotos(images: [Data], description: String, mealType: MealType) async throws -> NutritionAnalysis {
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

        // One user turn: each image as an inline base64 block, then the prompt text (images
        // before text is the documented best order for vision prompts).
        var content: [[String: Any]] = images.map { imageData in
            [
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": "image/jpeg",
                    "data": imageData.base64EncodedString()
                ]
            ]
        }
        content.append(["type": "text", "text": promptText])

        return try await send(
            NutritionAnalysis.self,
            content: content,
            schema: Self.nutritionSchema,
            effort: Self.analysisEffort,
            session: NetworkConfig.session,
            refusalMessage: "Claude declined to analyze this meal. Try a different photo or description."
        )
    }

    // MARK: - Daily Reflection (Phase 3 coaching)

    /// Generates a supportive daily reflection from a compact snapshot of the user's recent
    /// intake, goals, and Apple Health trends. Tone is enforced via the system prompt: curious
    /// and encouraging, never shaming, food framed neutrally, one gentle suggestion — and
    /// explicitly not medical advice.
    func generateReflection(context: String) async throws -> CoachingReflection {
        let userText = """
        Here is the user's recent snapshot. Write today's reflection.

        \(context)
        """

        // The dedicated reflection session, not the interactive one: it keeps this background
        // call off the connection the user-facing meal analyzer relies on, so a reflection in
        // flight can't starve an analyze request and trip its timeout.
        return try await send(
            CoachingReflection.self,
            system: Self.reflectionSystemPrompt,
            content: [["type": "text", "text": userText]],
            schema: Self.reflectionSchema,
            effort: Self.reflectionEffort,
            session: NetworkConfig.reflectionSession,
            refusalMessage: "Claude declined to write a reflection."
        )
    }

    // MARK: - Prompts & schemas

    private static let reflectionSystemPrompt = """
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

    /// Mirrors `NutritionAnalysis` — keep the two in sync.
    private static let nutritionSchema: [String: Any] = [
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

    /// Mirrors `CoachingReflection` — keep the two in sync.
    private static let reflectionSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "headline": ["type": "string"],
            // Note: array count bounds (minItems/maxItems) are NOT part of the
            // structured-outputs JSON Schema subset — including them makes the API
            // reject the whole request with a 400. The 2–4 range is conveyed via the
            // system prompt instead.
            "observations": [
                "type": "array",
                "items": ["type": "string"]
            ],
            "suggestion": ["type": "string"],
            "encouragement": ["type": "string"]
        ],
        "required": ["headline", "observations", "suggestion", "encouragement"],
        "additionalProperties": false
    ]

    // MARK: - Shared request path

    /// Sends one structured-output request (`output_config.format`, so the reply is guaranteed
    /// schema-valid JSON) and decodes it into `T`.
    private func send<T: Decodable>(
        _ type: T.Type,
        system: String? = nil,
        content: [[String: Any]],
        schema: [String: Any],
        effort: String,
        session: URLSession,
        refusalMessage: String
    ) async throws -> T {
        var body: [String: Any] = [
            "model": Self.model,
            "max_tokens": Self.maxTokens,
            "messages": [["role": "user", "content": content]],
            "output_config": [
                "effort": effort,
                "format": ["type": "json_schema", "schema": schema]
            ],
            "fallbacks": "default"
        ]
        if let system { body["system"] = system }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.anthropicVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue(Self.fallbackBeta, forHTTPHeaderField: "anthropic-beta")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        return try Self.decodeResponse(type, data: data, statusCode: httpResponse.statusCode, refusalMessage: refusalMessage)
    }

    /// Maps a raw Messages API response to `T` or a specific `APIError`. Free of networking so
    /// `scripts/core-check.sh` can feed it canned responses.
    static func decodeResponse<T: Decodable>(_ type: T.Type, data: Data, statusCode: Int, refusalMessage: String) throws -> T {
        guard statusCode == 200 else {
            let errorBody = parseAnthropicError(from: data) ?? String(data: data, encoding: .utf8) ?? "Unknown error"
            switch statusCode {
            case 429:
                throw APIError.rateLimited
            case 500...599:
                throw APIError.serverError(statusCode)
            default:
                throw APIError.httpError(statusCode: statusCode, body: errorBody)
            }
        }

        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw APIError.decodingError("Unexpected Claude response: not a JSON object")
        }

        switch json["stop_reason"] as? String {
        case "refusal":
            // A safety decline is HTTP 200 with no usable content (after any fallback also declined).
            throw APIError.refused(refusalMessage)
        case "max_tokens":
            // Cut off mid-answer: whatever text there is, it's truncated JSON.
            throw APIError.truncated
        default:
            break
        }

        // Read blocks by type, not position: with adaptive thinking the response opens with a
        // `thinking` block (empty text by default); the schema-valid JSON is the text block.
        guard let contentBlocks = json["content"] as? [[String: Any]],
              let text = contentBlocks.first(where: { ($0["type"] as? String) == "text" })?["text"] as? String else {
            let errorMessage = parseAnthropicError(from: data) ?? "no text block"
            throw APIError.decodingError("Unexpected Claude response: \(errorMessage)")
        }

        do {
            return try JSONDecoder().decode(T.self, from: Data(text.utf8))
        } catch {
            throw APIError.decodingError("\(T.self): \(text.prefix(200))")
        }
    }

    private static func parseAnthropicError(from data: Data) -> String? {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
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
