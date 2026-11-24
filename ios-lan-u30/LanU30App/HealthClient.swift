import Foundation

enum LocalHealthFailure: Error {
    case transport(String)
}

final class LocalHealthClient: NSObject, URLSessionTaskDelegate {
    func read(request: PreparedHealthRequest) async -> HealthReadResult {
        var urlRequest = URLRequest(url: request.url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 8)
        urlRequest.httpMethod = "GET"
        request.headers.forEach { urlRequest.setValue($1, forHTTPHeaderField: $0) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        do {
            let (data, response) = try await session.data(for: urlRequest)
            guard let http = response as? HTTPURLResponse else { return .notHealthDocument }
            return HealthProtocol.interpret(
                status: http.statusCode,
                body: data,
                contentType: http.value(forHTTPHeaderField: "Content-Type"),
                secret: request.secret,
                nonce: request.nonce)
        } catch {
            return .notHealthDocument
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
