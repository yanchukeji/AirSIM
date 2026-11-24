import XCTest
@testable import LanU30Core

final class LanU30CoreTests: XCTestCase {
    func testSHA256KnownAnswer() {
        XCTAssertEqual(SHA256.hex(SHA256.digest([UInt8]("abc".utf8))),
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(SHA256.hex(SHA256.digest([])),
                       "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    func testVoWLANCanonicalMatchesGateway() {
        let secret = [UInt8](repeating: UInt8(ascii: "k"), count: 32)
        let canonical = HealthProtocol.canonicalRequest(
            method: "GET", path: "/v1/health", body: [], timestamp: 1_700_000_000, nonce: "nonce-1")
        XCTAssertEqual(
            canonical,
            "GET\n/v1/health\ne3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\n1700000000\nnonce-1")
        XCTAssertEqual(
            Base64URL.encode(HMACSHA256.authenticate(key: secret, message: [UInt8](canonical.utf8))),
            "xNU8E52iGfI4W9E1PDM6fI3lvKkY55WAyYsmxyE5sTw")
        let proof = HMACSHA256.authenticate(key: secret, message: [UInt8]("AIRSIM-HEALTH1\nnonce-1\nagent-1".utf8))
        XCTAssertEqual(Base64URL.encode(proof), "lxlYMU4RSOVVZxzLG4Rwu2gxxAu9m-TBdfMGbo7X92Y")
    }

    func testPrivateAddresses() {
        XCTAssertEqual(tryHost("192.168.1.20"), true)
        XCTAssertEqual(tryHost("10.0.0.1"), true)
        XCTAssertEqual(tryHost("172.16.0.1"), true)
        XCTAssertEqual(tryHost("172.31.255.254"), true)
        XCTAssertEqual(tryHost("169.254.8.1"), true)
        for rejected in ["8.8.8.8", "1.1.1.1", "100.64.0.1", "127.0.0.1", "0.0.0.0",
                         "192.168.001.1", "192.168.1", "phone.local", "192.168.1.1.1",
                         "172.15.0.1", "172.32.0.1", "255.255.255.255", ""] {
            XCTAssertEqual(tryHost(rejected), false, rejected)
        }
        XCTAssertEqual(PrivateIPv4.port("7592"), .success(7592))
        XCTAssertEqual(PrivateIPv4.port("0"), .failure(.invalidPort))
        XCTAssertEqual(PrivateIPv4.port("65536"), .failure(.invalidPort))
        XCTAssertEqual(PrivateIPv4.port(""), .failure(.invalidPort))
    }

    func testNoDefaultCredentialAndRequestShape() {
        XCTAssertEqual(CredentialPolicy.material(from: ""), .failure(.missing))
        XCTAssertEqual(CredentialPolicy.material(from: "admin"), .failure(.rejectedDefault))
        XCTAssertEqual(CredentialPolicy.material(from: "password"), .failure(.rejectedDefault))
        XCTAssertEqual(CredentialPolicy.material(from: "short-secret"), .failure(.tooShort))
        let secret = String(repeating: "a", count: 32)
        let prepared = HealthProtocol.prepare(
            hostText: "192.168.8.8", portText: "7592", secretText: secret,
            timestamp: 1_700_000_000, nonce: "nonce-1")
        guard case .success(let request) = prepared else {
            return XCTFail("expected request")
        }
        XCTAssertEqual(request.url.scheme, "http")
        XCTAssertEqual(request.url.host, "192.168.8.8")
        XCTAssertEqual(request.url.path, "/v1/health")
        XCTAssertNil(request.url.query)
        XCTAssertEqual(request.headers["x-airsim-vowlan-version"], "1")
        XCTAssertFalse(request.headers.values.contains(secret))
        XCTAssertEqual(
            HealthProtocol.prepare(hostText: "8.8.8.8", portText: "80", secretText: secret,
                                   timestamp: 1, nonce: "n").isFailure, true)
        XCTAssertEqual(
            HealthProtocol.prepare(hostText: "192.168.1.1", portText: "443", secretText: "admin",
                                   timestamp: 1, nonce: "n").isFailure, true)
    }

    func testHealthParserDropsPhoneDataAndRequiresProof() {
        let secret = [UInt8](repeating: UInt8(ascii: "k"), count: 32)
        let proof = Base64URL.encode(HMACSHA256.authenticate(
            key: secret, message: [UInt8]("AIRSIM-HEALTH1\nnonce-1\nagent-1".utf8)))
        let body = """
        {"ok":true,"transport":"vowlan","version":1,"agent_id":"agent-1","identity_proof":"\(proof)",
        "agent_kind":"standalone","device_name":"U30","manufacturer":"ZTE","model":"U30 Air",
        "phone_number":"15550001111","sim_slots":[{"number":"15550002222","imsi":"hidden"}],
        "battery":{"percent":80,"charging":true}}
        """.data(using: .utf8)!
        let result = HealthProtocol.interpret(
            status: 200, body: body, contentType: "application/json", secret: secret, nonce: "nonce-1")
        guard case .verified(let snapshot) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(snapshot.model, "U30 Air")
        XCTAssertEqual(snapshot.batteryPercent, 80)
        XCTAssertEqual(snapshot.batteryCharging, true)
        XCTAssertFalse(String(describing: snapshot).contains("15550001111"))
        XCTAssertFalse(String(describing: snapshot).contains("hidden"))
        XCTAssertEqual(
            HealthProtocol.interpret(status: 200, body: body, contentType: "application/json",
                                     secret: secret, nonce: "other-nonce"),
            .identityRejected)
        XCTAssertEqual(
            HealthProtocol.interpret(status: 401, body: Data("secret-body".utf8), contentType: "text/plain",
                                     secret: secret, nonce: "nonce-1"),
            .httpStatus(401))
        XCTAssertEqual(
            HealthProtocol.interpret(status: 200, body: Data("<html>15550001111</html>".utf8),
                                     contentType: "text/html", secret: secret, nonce: "nonce-1"),
            .notHealthDocument)
    }

    private func tryHost(_ text: String) -> Bool {
        if case .success = PrivateIPv4.parse(text) { return true }
        return false
    }
}

private extension Result {
    var isFailure: Bool {
        if case .failure = self { return true }
        return false
    }
}
