//
//  JWTDecode.swift
//  Albert Script Runner
//

import Foundation

struct JwtSummary {
    let name: String?
    let tenantId: String?
    let email: String?
    let expiresAt: Date?
}

/// Decodes a JWT payload (2nd segment) into a dictionary without verifying signature.
/// Returns nil for empty/invalid tokens.
private func decodeJwtPayload(_ tokenRaw: String) -> [String: Any]? {
    let token = tokenRaw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !token.isEmpty else { return nil }

    let parts = token.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 3 else { return nil }

    let payloadPart = String(parts[1])
    guard let payloadData = base64URLDecode(payloadPart) else { return nil }

    guard
        let obj = try? JSONSerialization.jsonObject(with: payloadData, options: []),
        let payload = obj as? [String: Any]
    else { return nil }

    return payload
}

/// Extracts a small set of JWT claims for compact UI display (no signature verification).
/// Returns nil if token is empty or invalid.
func decodeJwtSummary(_ tokenRaw: String) -> JwtSummary? {
    guard let payload = decodeJwtPayload(tokenRaw) else { return nil }

    let name = payload["name"] as? String

    let tenantId: String? = {
        if let s = payload["tenantId"] as? String { return s }
        if let n = payload["tenantId"] as? NSNumber { return n.stringValue }
        if let v = payload["tenantId"] { return String(describing: v) }
        return nil
    }()

    let email = payload["email"] as? String

    let expiresAt: Date? = {
        guard let expAny = payload["exp"] else { return nil }
        let expSeconds: TimeInterval?
        if let t = expAny as? TimeInterval {
            expSeconds = t
        } else if let i = expAny as? Int {
            expSeconds = TimeInterval(i)
        } else if let n = expAny as? NSNumber {
            expSeconds = n.doubleValue
        } else if let s = expAny as? String, let d = Double(s) {
            expSeconds = d
        } else {
            expSeconds = nil
        }
        guard let expSeconds else { return nil }
        return Date(timeIntervalSince1970: expSeconds)
    }()

    return JwtSummary(name: name, tenantId: tenantId, email: email, expiresAt: expiresAt)
}

/// Pretty-prints a JWT payload without verifying the signature.
/// Mirrors the behavior of `decodeJwt_pretty()` in your Python app.
func decodeJwtPretty(_ tokenRaw: String) -> String {
    let token = tokenRaw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !token.isEmpty else { return "" }

    guard let payload = decodeJwtPayload(tokenRaw) else {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        if parts.count != 3 { return "Invalid token: expected 3 parts separated by dots." }
        return "Invalid token: payload is not valid JSON."
    }

    // Fields (be permissive with types)
    let name = payload["name"] as? String ?? "N/A"
    let email = payload["email"] as? String ?? "N/A"

    let tenantId: String = {
        if let s = payload["tenantId"] as? String { return s }
        if let n = payload["tenantId"] as? NSNumber { return n.stringValue }
        if let v = payload["tenantId"] { return String(describing: v) }
        return "N/A"
    }()

    let role = payload["role"] as? String ?? "N/A"
    let klass = payload["class"] as? String ?? "N/A"

    // Teams may be a list or a single value
    let teams: String = {
        guard let teamsValue = payload["teams"] else { return "N/A" }
        if let list = teamsValue as? [Any] {
            let s = list.map { String(describing: $0) }.joined(separator: ", ")
            return s.isEmpty ? "N/A" : s
        }
        let s = String(describing: teamsValue)
        return s.isEmpty ? "N/A" : s
    }()

    // Expiration (exp can be Int / Double / String)
    let expString: String = {
        guard let expAny = payload["exp"] else { return "N/A" }

        let expSeconds: TimeInterval?
        if let t = expAny as? TimeInterval {
            expSeconds = t
        } else if let i = expAny as? Int {
            expSeconds = TimeInterval(i)
        } else if let n = expAny as? NSNumber {
            expSeconds = n.doubleValue
        } else if let s = expAny as? String, let d = Double(s) {
            expSeconds = d
        } else {
            expSeconds = nil
        }

        guard let expSeconds else { return "N/A" }
        let date = Date(timeIntervalSince1970: expSeconds)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date) + " UTC"
    }()

    return """
    Name: \(name)
    Email: \(email)
    Tenant ID: \(tenantId)
    Role: \(role)
    Class: \(klass)
    Teams: \(teams)
    Expires: \(expString)
    """
}

/// Base64URL (RFC 7515) decode helper.
private func base64URLDecode(_ input: String) -> Data? {
    var base64 = input
        .replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")

    let remainder = base64.count % 4
    if remainder != 0 {
        base64.append(String(repeating: "=", count: 4 - remainder))
    }

    return Data(base64Encoded: base64)
}
