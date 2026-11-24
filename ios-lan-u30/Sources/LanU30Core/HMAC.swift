import Foundation

enum HMACSHA256 {
    static func authenticate(key: [UInt8], message: [UInt8]) -> [UInt8] {
        let block = 64
        var normalized = key
        if normalized.count > block {
            normalized = SHA256.digest(normalized)
        }
        if normalized.count < block {
            normalized.append(contentsOf: [UInt8](repeating: 0, count: block - normalized.count))
        }
        let ipad = normalized.map { $0 ^ 0x36 }
        let opad = normalized.map { $0 ^ 0x5C }
        return SHA256.digest(opad + SHA256.digest(ipad + message))
    }
}

enum FixedTime {
    static func equal(_ lhs: [UInt8], _ rhs: [UInt8]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        var difference: UInt8 = 0
        for index in lhs.indices {
            difference |= lhs[index] ^ rhs[index]
        }
        return difference == 0
    }
}
