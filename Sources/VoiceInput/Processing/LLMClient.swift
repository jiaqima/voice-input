import Foundation

final class LLMClient {
    static let systemPrompt = """
    You are a speech recognition post-processor. Your ONLY job is to fix obvious speech recognition errors in the transcribed text. Be extremely conservative:

    1. Fix Chinese homophone errors (e.g., 的/得/地 confusion, 在/再 confusion)
    2. Fix English technical terms that were mistakenly converted to Chinese phonetic equivalents (e.g., 配森→Python, 杰森→JSON, 瑞安→React, 诺德→Node, 加瓦→Java, 斯威夫特→Swift, 盖特→Git, 盖特哈布→GitHub, 多科→Docker, 库伯奈提斯→Kubernetes, 阿皮→API, 优阿尔艾尔→URL, 艾奇提提皮→HTTP, 杰S→JS, 提S→TS, 西加加→C++, 西夏普→C#, 拉斯特→Rust, 戈→Go, 卡夫卡→Kafka, 瑞迪斯→Redis, SQL→SQL, 麦克OS→macOS)
    3. Fix obvious punctuation errors

    CRITICAL RULES:
    - If the input text looks correct, return it EXACTLY as-is
    - NEVER rewrite, rephrase, polish, or improve the text
    - NEVER add or remove content
    - NEVER change the meaning or tone
    - NEVER translate between languages
    - Only fix clear, unambiguous recognition errors
    - Return ONLY the corrected text, no explanations

    Respond with the corrected text only, nothing else.
    """

    func refine(text: String, completion: @escaping (Result<String, Error>) -> Void) {
        let settings = Settings.shared
        guard settings.isLLMConfigured else {
            completion(.success(text))
            return
        }

        var baseURL = settings.llmBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if baseURL.hasSuffix("/") { baseURL.removeLast() }

        // Support both full URL and base URL
        let urlString: String
        if baseURL.hasSuffix("/chat/completions") {
            urlString = baseURL
        } else if baseURL.hasSuffix("/v1") {
            urlString = baseURL + "/chat/completions"
        } else {
            urlString = baseURL + "/v1/chat/completions"
        }

        guard let url = URL(string: urlString) else {
            completion(.failure(LLMError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(settings.llmAPIKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "model": settings.llmModel,
            "messages": [
                ["role": "system", "content": Self.systemPrompt],
                ["role": "user", "content": text],
            ],
            "temperature": 0.1,
            "max_tokens": 2048,
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let data = data else {
                completion(.failure(LLMError.noData))
                return
            }

            do {
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let choices = json["choices"] as? [[String: Any]],
                      let first = choices.first,
                      let message = first["message"] as? [String: Any],
                      let content = message["content"] as? String else {
                    completion(.failure(LLMError.invalidResponse))
                    return
                }
                completion(.success(content.trimmingCharacters(in: .whitespacesAndNewlines)))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    func testConnection(baseURL: String, apiKey: String, model: String, completion: @escaping (Result<String, Error>) -> Void) {
        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.hasSuffix("/") { base.removeLast() }

        let urlString: String
        if base.hasSuffix("/chat/completions") {
            urlString = base
        } else if base.hasSuffix("/v1") {
            urlString = base + "/chat/completions"
        } else {
            urlString = base + "/v1/chat/completions"
        }

        guard let url = URL(string: urlString) else {
            completion(.failure(LLMError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "user", "content": "Say OK"],
            ],
            "max_tokens": 10,
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(.failure(LLMError.invalidResponse))
                return
            }
            if let errorObj = json["error"] as? [String: Any],
               let message = errorObj["message"] as? String {
                completion(.failure(LLMError.apiError(message)))
                return
            }
            if let choices = json["choices"] as? [[String: Any]], !choices.isEmpty {
                completion(.success("Connection successful!"))
            } else {
                completion(.failure(LLMError.invalidResponse))
            }
        }.resume()
    }
}

enum LLMError: LocalizedError {
    case invalidURL
    case noData
    case invalidResponse
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid API URL"
        case .noData: return "No data received"
        case .invalidResponse: return "Invalid response format"
        case .apiError(let msg): return msg
        }
    }
}
