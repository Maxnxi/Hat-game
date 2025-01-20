import Foundation

// Success response structure
struct ChatGPTResponse: Codable {
	let id: String
	let object: String
	let created: Int
	let model: String
	let usage: Usage
	let choices: [Choice]
	
	struct Usage: Codable {
		let promptTokens: Int
		let completionTokens: Int
		let totalTokens: Int
		
		enum CodingKeys: String, CodingKey {
			case promptTokens = "prompt_tokens"
			case completionTokens = "completion_tokens"
			case totalTokens = "total_tokens"
		}
	}
	
	struct Choice: Codable {
		let message: Message
		let finishReason: String?
		let index: Int
		
		enum CodingKeys: String, CodingKey {
			case message
			case finishReason = "finish_reason"
			case index
		}
	}
	
	struct Message: Codable {
		let role: String
		let content: String
	}
}

// Error response structure
struct ChatGPTErrorResponse: Codable {
	let error: APIError
	
	struct APIError: Codable {
		let message: String
		let type: String
		let param: String?
		let code: String
	}
}

enum ChatGPTError: Error {
	case invalidURL
	case noData
	case decodingError(Error)
	case apiError(String)
	case networkError(Error)
	case quotaExceeded
}

class ChatGPTAPIClient {
	private let apiKey: String
	private let baseURL = "https://api.openai.com/v1/chat/completions"
	
	init(apiKey: String) {
		self.apiKey = apiKey
	}
	
	func fetchThemedWords(theme: String, language: String, completion: @escaping (Result<[String], ChatGPTError>) -> Void) {
		guard let url = URL(string: baseURL) else {
			completion(.failure(.invalidURL))
			return
		}
		
		let prompt = "Generate exactly 20 words in \(language) related to the theme '\(theme)'. Provide only the words separated by commas, no explanations."
		
		let messages: [[String: Any]] = [
			["role": "system", "content": "You are a helpful assistant that generates themed word lists."],
			["role": "user", "content": prompt]
		]
		
		let parameters: [String: Any] = [
			"model": "gpt-3.5-turbo",
			"messages": messages,
			"temperature": 0.7,
			"max_tokens": 150
		]
		
		var request = URLRequest(url: url)
		request.httpMethod = "POST"
		request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
		request.addValue("application/json", forHTTPHeaderField: "Content-Type")
		
		do {
			request.httpBody = try JSONSerialization.data(withJSONObject: parameters)
		} catch {
			completion(.failure(.apiError("Failed to encode request parameters")))
			return
		}
		
		let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
			if let error = error {
				completion(.failure(.networkError(error)))
				return
			}
			
			guard let data = data else {
				completion(.failure(.noData))
				return
			}
			
			// Debug: Print raw response and HTTP status code
			if let httpResponse = response as? HTTPURLResponse {
				print("HTTP Status Code:", httpResponse.statusCode)
			}
			if let jsonString = String(data: data, encoding: .utf8) {
				print("Raw API Response:", jsonString)
			}
			
			// First try to decode as error response
			do {
				let errorResponse = try JSONDecoder().decode(ChatGPTErrorResponse.self, from: data)
				if errorResponse.error.code == "insufficient_quota" {
					completion(.failure(.quotaExceeded))
				} else {
					completion(.failure(.apiError(errorResponse.error.message)))
				}
				return
			} catch {
				// If error response decoding fails, try to decode as success response
				do {
					let response = try JSONDecoder().decode(ChatGPTResponse.self, from: data)
					guard let content = response.choices.first?.message.content else {
						completion(.failure(.apiError("No content in response")))
						return
					}
					
					let words = content.components(separatedBy: ",")
						.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
						.filter { !$0.isEmpty }
					
					completion(.success(words))
				} catch {
					completion(.failure(.decodingError(error)))
				}
			}
		}
		
		task.resume()
	}
}

// Async/await version
//extension ChatGPTAPIClient {
//	func fetchThemedWordsAsync(theme: String, language: String) async throws -> [String] {
//		return try await withCheckedThrowingContinuation { continuation in
//			fetchThemedWords(theme: theme, language: language) { result in
//				continuation.resume(with: result)
//			}
//		}
//	}
//}

// Example usage:
let apiClient = ChatGPTAPIClient(apiKey: "chat_gpt_API")

// Using completion handler
apiClient.fetchThemedWords(theme: "nature", language: "French") { result in
	switch result {
	case .success(let words):
		print("Themed words:", words)
	case .failure(.quotaExceeded):
		print("Error: API quota exceeded. Please check your OpenAI account billing details.")
	case .failure(let error):
		print("Error:", error)
	}
}
