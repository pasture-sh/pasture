import Foundation
import PastureShared

/// Communicates with the local Ollama HTTP API on localhost:11434.
actor OllamaAPIClient {
    static let shared = OllamaAPIClient()
    private let baseURL = URL(string: "http://localhost:11434")!
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        return URLSession(configuration: config)
    }()

    // MARK: - Tags (list installed models)

    func fetchTags() async throws -> [OllamaModel] {
        let url = baseURL.appendingPathComponent("api/tags")
        let data = try await validatedData(for: url)
        let response = try JSONDecoder().decode(TagsResponse.self, from: data)
        return response.models
    }

    // MARK: - Chat (streaming)

    func chat(model: String, messages: [ChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let streamTask = Task {
                do {
                    let url = baseURL.appendingPathComponent("api/chat")
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    let body = ChatRequest(model: model, messages: messages, stream: true)
                    request.httpBody = try JSONEncoder().encode(body)

                    let (bytes, response) = try await session.bytes(for: request)
                    try validate(response)
                    for try await line in bytes.lines {
                        guard !line.isEmpty,
                              let data = line.data(using: .utf8),
                              let chunk = try? JSONDecoder().decode(ChatChunk.self, from: data)
                        else { continue }

                        if let errorMessage = chunk.error, !errorMessage.isEmpty {
                            throw OllamaAPIError.server(statusCode: nil, message: errorMessage)
                        }

                        if let content = chunk.message?.content, !content.isEmpty {
                            continuation.yield(content)
                        }

                        if chunk.done == true { break }
                        try Task.checkCancellation()
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                streamTask.cancel()
            }
        }
    }

    // MARK: - Pull (streaming progress)

    func pull(model: String) -> AsyncThrowingStream<PullProgress, Error> {
        AsyncThrowingStream { continuation in
            let streamTask = Task {
                do {
                    let url = baseURL.appendingPathComponent("api/pull")
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    let body = PullRequest(name: model, stream: true)
                    request.httpBody = try JSONEncoder().encode(body)

                    let (bytes, response) = try await session.bytes(for: request)
                    try validate(response)
                    for try await line in bytes.lines {
                        guard !line.isEmpty,
                              let data = line.data(using: .utf8),
                              let progress = try? JSONDecoder().decode(PullProgress.self, from: data)
                        else { continue }

                        if let errorMessage = progress.error, !errorMessage.isEmpty {
                            throw OllamaAPIError.server(statusCode: nil, message: errorMessage)
                        }

                        continuation.yield(progress)
                        if progress.isComplete { break }
                        try Task.checkCancellation()
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                streamTask.cancel()
            }
        }
    }

    // MARK: - Delete

    func delete(model: String) async throws {
        let url = baseURL.appendingPathComponent("api/delete")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["name": model])
        _ = try await validatedData(for: request)
    }

    // MARK: - Health check

    func isReachable() async -> Bool {
        let url = baseURL.appendingPathComponent("api/version")
        do {
            _ = try await validatedData(for: url)
            return true
        } catch {
            return false
        }
    }

    private func validatedData(for url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        try validate(response, data: data)
        return data
    }

    private func validatedData(for request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
        return data
    }

    private func validate(_ response: URLResponse, data: Data? = nil) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OllamaAPIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = extractErrorMessage(from: data)
            throw OllamaAPIError.server(statusCode: httpResponse.statusCode, message: message)
        }
    }

    private func extractErrorMessage(from data: Data?) -> String? {
        guard let data, !data.isEmpty else { return nil }

        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = object["error"] as? String, !error.isEmpty {
                return error
            }
            if let message = object["message"] as? String, !message.isEmpty {
                return message
            }
        }

        if let plainText = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !plainText.isEmpty {
            return plainText
        }

        return nil
    }
}

// MARK: - Models

struct TagsResponse: Codable {
    let models: [OllamaModel]
}

struct ChatRequest: Codable {
    let model: String
    let messages: [ChatMessage]
    let stream: Bool
}

struct ChatChunk: Codable {
    let message: ChatMessage?
    let done: Bool?
    let error: String?
}

struct PullRequest: Codable {
    let name: String
    let stream: Bool
}

enum OllamaAPIError: LocalizedError {
    case invalidResponse
    case server(statusCode: Int?, message: String?)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Received an invalid response from Ollama."
        case .server(let statusCode, let message):
            if let message, !message.isEmpty {
                return message
            }
            if let statusCode {
                return "Ollama returned HTTP \(statusCode)."
            }
            return "Ollama returned an error."
        }
    }
}
