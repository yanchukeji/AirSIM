import Foundation

enum HealthProtocolError: Error, Equatable {
    case address(PrivateIPv4Error)
    case credential(CredentialPolicyError)
    case randomUnavailable
}

struct PreparedHealthRequest: Equatable {
    let url: URL
    let headers: [String: String]
    let nonce: String
    let secret: [UInt8]
}

struct HealthSnapshot: Equatable {
    let transport: String
    let agentKind: String
    let deviceName: String
    let manufacturer: String
    let model: String
    let batteryPercent: Int?
    let batteryCharging: Bool?
}

enum HealthReadResult: Equatable {
    case verified(HealthSnapshot)
    case httpStatus(Int)
    case notHealthDocument
    case identityRejected
    case responseTooLarge
}

enum HealthProtocol {
    static let path = "/v1/health"
    static let maximumBodyBytes = 8_192

    static func prepare(
        hostText: String,
        portText: String,
        secretText: String,
        timestamp: Int64,
        nonce: String
    ) -> Result<PreparedHealthRequest, HealthProtocolError> {
        let host: (UInt8, UInt8, UInt8, UInt8)
        switch PrivateIPv4.parse(hostText) {
        case .success(let value): host = value
        case .failure(let error): return .failure(.address(error))
        }
        let port: UInt16
        switch PrivateIPv4.port(portText) {
        case .success(let value): port = value
        case .failure(let error): return .failure(.address(error))
        }
        let secret: [UInt8]
        switch CredentialPolicy.material(from: secretText) {
        case .success(let value): secret = value
        case .failure(let error): return .failure(.credential(error))
        }
        guard !nonce.isEmpty, nonce.utf8.count <= 128, !nonce.contains("\n") else {
            return .failure(.randomUnavailable)
        }
        let canonical = canonicalRequest(method: "GET", path: path, body: [], timestamp: timestamp, nonce: nonce)
        let signature = Base64URL.encode(HMACSHA256.authenticate(key: secret, message: [UInt8](canonical.utf8)))
        var components = URLComponents()
        components.scheme = "http"
        components.host = "\(host.0).\(host.1).\(host.2).\(host.3)"
        components.port = Int(port)
        components.path = path
        guard let url = components.url, url.query == nil, url.user == nil else {
            return .failure(.address(.notLiteralIPv4))
        }
        let headers = [
            "x-airsim-vowlan-version": "1",
            "x-airsim-vowlan-timestamp": String(timestamp),
            "x-airsim-vowlan-nonce": nonce,
            "x-airsim-vowlan-signature": signature,
            "accept": "application/json",
        ]
        return .success(PreparedHealthRequest(url: url, headers: headers, nonce: nonce, secret: secret))
    }

    static func canonicalRequest(method: String, path: String, body: [UInt8], timestamp: Int64, nonce: String) -> String {
        "\(method.uppercased())\n\(path)\n\(SHA256.hex(SHA256.digest(body)))\n\(timestamp)\n\(nonce)"
    }

    static func interpret(status: Int, body: Data, contentType: String?, secret: [UInt8], nonce: String) -> HealthReadResult {
        guard (200...299).contains(status) else { return .httpStatus(status) }
        guard body.count <= maximumBodyBytes else { return .responseTooLarge }
        if let contentType, !contentType.lowercased().contains("json") {
            return .notHealthDocument
        }
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return .notHealthDocument
        }
        guard object["ok"] as? Bool == true else { return .identityRejected }
        guard let agentID = object["agent_id"] as? String, !agentID.isEmpty,
              let proof = object["identity_proof"] as? String,
              let supplied = Base64URL.decode(proof) else {
            return .identityRejected
        }
        let expected = HMACSHA256.authenticate(
            key: secret,
            message: [UInt8]("AIRSIM-HEALTH1\n\(nonce)\n\(agentID)".utf8)
        )
        guard FixedTime.equal(expected, supplied) else { return .identityRejected }
        let battery = object["battery"] as? [String: Any]
        let percent = battery?["percent"] as? Int
        let boundedPercent = percent.flatMap { (0...100).contains($0) ? $0 : nil }
        return .verified(HealthSnapshot(
            transport: string(object["transport"]),
            agentKind: string(object["agent_kind"]),
            deviceName: string(object["device_name"]),
            manufacturer: string(object["manufacturer"]),
            model: string(object["model"]),
            batteryPercent: boundedPercent,
            batteryCharging: battery?["charging"] as? Bool
        ))
    }

    private static func string(_ value: Any?) -> String {
        guard let text = value as? String else { return "" }
        return String(text.prefix(80))
    }
}
