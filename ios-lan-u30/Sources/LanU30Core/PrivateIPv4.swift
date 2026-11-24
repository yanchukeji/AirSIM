import Foundation

enum PrivateIPv4Error: Error, Equatable {
    case notLiteralIPv4
    case notLocalNetwork
    case invalidPort
}

/// LAN literals only. Hostnames are rejected so DNS cannot move the request off the local network.
enum PrivateIPv4 {
    static func parse(_ text: String) -> Result<(UInt8, UInt8, UInt8, UInt8), PrivateIPv4Error> {
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return .failure(.notLiteralIPv4) }
        var octets = [UInt8]()
        for part in parts {
            guard part.count <= 3, part.allSatisfy({ $0.isNumber }),
                  let value = UInt8(part), String(value) == part || (value == 0 && part == "0") else {
                return .failure(.notLiteralIPv4)
            }
            if part.count > 1, part.first == "0" { return .failure(.notLiteralIPv4) }
            octets.append(value)
        }
        let address = (octets[0], octets[1], octets[2], octets[3])
        guard isLocal(address) else { return .failure(.notLocalNetwork) }
        return .success(address)
    }

    static func isLocal(_ address: (UInt8, UInt8, UInt8, UInt8)) -> Bool {
        let (a, b, _, _) = address
        if a == 10 { return true }
        if a == 172, (16...31).contains(b) { return true }
        if a == 192, b == 168 { return true }
        if a == 169, b == 254 { return true }
        return false
    }

    static func port(_ text: String) -> Result<UInt16, PrivateIPv4Error> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = UInt16(trimmed), String(value) == trimmed, value > 0 else {
            return .failure(.invalidPort)
        }
        return .success(value)
    }
}
