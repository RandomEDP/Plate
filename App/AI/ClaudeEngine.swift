import Foundation
import PlateCore

/// Claude through the Anthropic API, with the person's own key. Answers come back as JSON that matches a schema.
struct ClaudeEngine: RecipeAIEngine {
    let key: String
    let model: ClaudeModel
    var name: String { model == .opus ? "Claude Opus" : "Claude Haiku" }

    enum Failure: LocalizedError {
        case http(Int, String)
        case refused
        case unreadable

        var errorDescription: String? {
            switch self {
            case .http(401, _): return "Claude didn't accept the API key. Check it in Settings → AI (it starts with sk-ant-)."
            case .http(402, _), .http(403, _): return "Claude turned the request down: the API account may be out of credit. Top up at console.anthropic.com."
            case .http(429, _): return "Claude is busy or the account's rate limit was hit. Try again in a minute."
            case .http(let code, let body): return "Claude answered with an error (\(code)): \(body.prefix(160))"
            case .refused: return "Claude declined to answer that one."
            case .unreadable: return "Claude's answer couldn't be read. Try again."
            }
        }
    }

    static var recipeSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "name": ["type": "string"],
                "meal": ["type": "string", "enum": ["breakfast", "lunch", "dinner", "snack"]],
                "servings": ["type": "integer"],
                "minutes": ["type": "integer"],
                "ingredients": ["type": "array", "items": ["type": "string"]],
                "steps": ["type": "array", "items": ["type": "string"]],
                "calories": ["type": "number"],
                "protein": ["type": "number"],
                "carbs": ["type": "number"],
                "fat": ["type": "number"],
                "summary": ["type": "string"],
            ],
            "required": ["name", "meal", "servings", "minutes", "ingredients", "steps", "calories", "protein", "carbs", "fat", "summary"],
            "additionalProperties": false,
        ]
    }

    func call(prompt: String, schema: [String: Any]) async throws -> Data {
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 120
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        let body: [String: Any] = [
            "model": model.rawValue,
            "max_tokens": 8000,
            "system": AIPrompts.instructions,
            "messages": [["role": "user", "content": prompt]],
            "output_config": ["effort": "low", "format": ["type": "json_schema", "schema": schema]],
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let message = ((try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? [String: Any])?["message"] as? String
            throw Failure.http(status, message ?? String(data: data, encoding: .utf8) ?? "")
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Failure.unreadable }
        if obj["stop_reason"] as? String == "refusal" { throw Failure.refused }
        let blocks = obj["content"] as? [[String: Any]] ?? []
        guard let text = blocks.first(where: { $0["type"] as? String == "text" })?["text"] as? String else { throw Failure.unreadable }
        return Data(text.utf8)
    }

    func tidy(caption: String) async throws -> RecipeDraft {
        let data = try await call(prompt: AIPrompts.tidy(caption), schema: Self.recipeSchema)
        do { return try JSONDecoder().decode(RecipeDraft.self, from: data) } catch { throw Failure.unreadable }
    }

    func ideas(kitchen: [String], meal: MealType?, count: Int, people: Int) async throws -> [RecipeDraft] {
        let schema: [String: Any] = [
            "type": "object",
            "properties": ["recipes": ["type": "array", "items": Self.recipeSchema]],
            "required": ["recipes"],
            "additionalProperties": false,
        ]
        let data = try await call(prompt: AIPrompts.ideas(kitchen: kitchen, meal: meal, count: count, people: people), schema: schema)
        struct Wrapper: Decodable { var recipes: [RecipeDraft] }
        do { return try JSONDecoder().decode(Wrapper.self, from: data).recipes } catch { throw Failure.unreadable }
    }
}
