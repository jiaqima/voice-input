import Foundation

final class LLMClient {
    final class RefinementRequest {
        private let lock = NSLock()
        private var completion: ((Result<String, Error>) -> Void)?
        private var task: URLSessionDataTask?
        private var isFinished = false

        init(completion: @escaping (Result<String, Error>) -> Void) {
            self.completion = completion
        }

        func setTask(_ task: URLSessionDataTask) {
            lock.lock()
            if isFinished {
                lock.unlock()
                task.cancel()
                return
            }
            self.task = task
            lock.unlock()
        }

        func complete(_ result: Result<String, Error>) {
            let callback: ((Result<String, Error>) -> Void)?
            lock.lock()
            guard !isFinished else {
                lock.unlock()
                return
            }
            isFinished = true
            callback = completion
            completion = nil
            task = nil
            lock.unlock()

            callback?(result)
        }

        func cancel() {
            let taskToCancel: URLSessionDataTask?
            lock.lock()
            guard !isFinished else {
                lock.unlock()
                return
            }
            isFinished = true
            taskToCancel = task
            task = nil
            completion = nil
            lock.unlock()

            taskToCancel?.cancel()
        }
    }

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

    private static let refinementMaxTokens = 128

    func refine(text: String, completion: @escaping (Result<String, Error>) -> Void) -> RefinementRequest {
        let refinementRequest = RefinementRequest(completion: completion)
        let settings = Settings.shared
        guard settings.isLLMConfigured else {
            refinementRequest.complete(.success(text))
            return refinementRequest
        }

        guard let url = Self.chatCompletionsURL(from: settings.llmBaseURL) else {
            refinementRequest.complete(.failure(LLMError.invalidURL))
            return refinementRequest
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
            "stream": false,
            "temperature": 0.1,
            "max_tokens": Self.refinementMaxTokens,
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            refinementRequest.complete(.failure(error))
            return refinementRequest
        }

        let task = URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error {
                refinementRequest.complete(.failure(error))
                return
            }

            guard let data = data else {
                refinementRequest.complete(.failure(LLMError.noData))
                return
            }

            do {
                let refinedText = try Self.parseRefinementResponse(data)
                refinementRequest.complete(.success(refinedText))
            } catch {
                refinementRequest.complete(.failure(error))
            }
        }

        refinementRequest.setTask(task)
        task.resume()
        return refinementRequest
    }

    func testConnection(baseURL: String, apiKey: String, model: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let url = Self.chatCompletionsURL(from: baseURL) else {
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
            "stream": false,
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

    private static func chatCompletionsURL(from baseURL: String) -> URL? {
        var normalizedBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedBaseURL.hasSuffix("/") {
            normalizedBaseURL.removeLast()
        }

        let urlString: String
        if normalizedBaseURL.hasSuffix("/chat/completions") {
            urlString = normalizedBaseURL
        } else if normalizedBaseURL.hasSuffix("/v1") {
            urlString = normalizedBaseURL + "/chat/completions"
        } else {
            urlString = normalizedBaseURL + "/v1/chat/completions"
        }

        return URL(string: urlString)
    }

    private static func parseRefinementResponse(_ data: Data) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMError.invalidResponse
        }

        if let apiError = apiErrorMessage(from: json) {
            throw LLMError.apiError(apiError)
        }

        guard let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = messageContent(from: message) else {
            throw LLMError.invalidResponse
        }

        guard let sanitizedContent = sanitizeRefinedText(content) else {
            throw LLMError.emptyResponse
        }

        return sanitizedContent
    }

    private static func apiErrorMessage(from json: [String: Any]) -> String? {
        if let errorObject = json["error"] as? [String: Any],
           let message = errorObject["message"] as? String,
           !message.isEmpty {
            return message
        }

        if let errorMessage = json["error"] as? String, !errorMessage.isEmpty {
            return errorMessage
        }

        return nil
    }

    private static func messageContent(from message: [String: Any]) -> String? {
        if let content = message["content"] as? String {
            return content
        }

        guard let contentParts = message["content"] as? [Any] else {
            return nil
        }

        let combinedText = contentParts.compactMap(textContent(from:)).joined()
        return combinedText.isEmpty ? nil : combinedText
    }

    private static func textContent(from part: Any) -> String? {
        guard let dictionary = part as? [String: Any] else {
            return nil
        }

        if let text = dictionary["text"] as? String {
            return text
        }

        if let textObject = dictionary["text"] as? [String: Any],
           let value = textObject["value"] as? String {
            return value
        }

        if let content = dictionary["content"] as? String {
            return content
        }

        return nil
    }

    private static func sanitizeRefinedText(_ rawText: String) -> String? {
        var text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)

        while text.hasPrefix("<think>") {
            guard let endRange = text.range(of: "</think>") else {
                text = ""
                break
            }

            text.removeSubrange(text.startIndex..<endRange.upperBound)
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return text.isEmpty ? nil : text
    }
}

enum LLMError: LocalizedError {
    case invalidURL
    case noData
    case invalidResponse
    case emptyResponse
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid API URL"
        case .noData: return "No data received"
        case .invalidResponse: return "Invalid response format"
        case .emptyResponse: return "Response did not contain usable text"
        case .apiError(let msg): return msg
        }
    }
}
