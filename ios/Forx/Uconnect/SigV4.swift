import CryptoKit
import Foundation

/// Temporary AWS credentials (from Cognito) used to sign API Gateway requests.
nonisolated struct AWSCredentials: Sendable, Codable {
    var accessKeyId: String
    var secretAccessKey: String
    var sessionToken: String
}

/// Minimal AWS Signature Version 4 signer, ported from py-uconnect's `sigv4.py`.
/// Only `host` and the `x-amz-*` headers are signed.
nonisolated enum SigV4 {
    private static let algorithm = "AWS4-HMAC-SHA256"

    /// Signs `request` in place: sets `X-Amz-Date`, `X-Amz-Security-Token`
    /// (when the session token is non-empty) and `Authorization`.
    /// The request URL must be the exact (already percent-encoded) URL that is sent.
    static func sign(
        _ request: inout URLRequest,
        credentials: AWSCredentials,
        region: String,
        service: String = "execute-api",
        now: Date
    ) {
        guard let url = request.url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return }

        let (amzDate, dateStamp) = formatDates(now)

        var host = (components.host ?? "").lowercased()
        if let port = components.port, port != 80, port != 443 {
            host += ":\(port)"
        }

        var added: [(String, String)] = [("X-Amz-Date", amzDate)]
        if !credentials.sessionToken.isEmpty {
            added.append(("X-Amz-Security-Token", credentials.sessionToken))
        }

        // host + every x-amz-* header (existing ones first, ours override).
        var toSign: [String: String] = ["host": host]
        let existing = (request.allHTTPHeaderFields ?? [:]).map { ($0.key, $0.value) }
        for (name, value) in existing + added where name.lowercased().hasPrefix("x-amz-") {
            toSign[name.lowercased()] = collapseWhitespace(value)
        }

        let names = toSign.keys.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
        let signedHeaders = names.joined(separator: ";")
        let canonicalHeaders = names.map { "\($0):\(toSign[$0] ?? "")\n" }.joined()

        let method = (request.httpMethod ?? "GET").uppercased()
        let path = components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath
        let payloadHash = hex(SHA256.hash(data: request.httpBody ?? Data()))

        let canonicalRequest = [
            method,
            quote(path, keeping: pathSafe),
            canonicalQuery(components.percentEncodedQuery ?? ""),
            canonicalHeaders,
            signedHeaders,
            payloadHash,
        ].joined(separator: "\n")

        let scope = "\(dateStamp)/\(region)/\(service)/aws4_request"
        let stringToSign = [
            algorithm,
            amzDate,
            scope,
            hex(SHA256.hash(data: Data(canonicalRequest.utf8))),
        ].joined(separator: "\n")

        var key = hmac(key: Data("AWS4\(credentials.secretAccessKey)".utf8), message: dateStamp)
        key = hmac(key: key, message: region)
        key = hmac(key: key, message: service)
        key = hmac(key: key, message: "aws4_request")
        let signature = hex(hmac(key: key, message: stringToSign))

        for (name, value) in added {
            request.setValue(value, forHTTPHeaderField: name)
        }
        request.setValue(
            "\(algorithm) Credential=\(credentials.accessKeyId)/\(scope), "
                + "SignedHeaders=\(signedHeaders), Signature=\(signature)",
            forHTTPHeaderField: "Authorization"
        )
    }

    // MARK: - Helpers

    private static let unreserved = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~".utf8)
    private static let pathSafe = unreserved.union([UInt8(ascii: "/")])

    /// Python `urllib.parse.quote(s, safe=...)`: percent-encode every UTF-8 byte not in `keeping`.
    private static func quote(_ s: String, keeping: Set<UInt8>) -> String {
        var out = ""
        for byte in s.utf8 {
            if keeping.contains(byte) {
                out.unicodeScalars.append(Unicode.Scalar(byte))
            } else {
                out += String(format: "%%%02X", byte)
            }
        }
        return out
    }

    /// Python `parse_qsl(query, keep_blank_values=True)`, each pair re-quoted, sorted by (key, value).
    private static func canonicalQuery(_ query: String) -> String {
        var pairs: [(String, String)] = []
        for segment in query.split(separator: "&", omittingEmptySubsequences: true) {
            let parts = segment.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let rawKey = String(parts[0])
            let rawValue = parts.count > 1 ? String(parts[1]) : ""
            pairs.append((qsDecode(rawKey), qsDecode(rawValue)))
        }
        pairs.sort { lhs, rhs in
            if lhs.0 != rhs.0 { return lhs.0.utf8.lexicographicallyPrecedes(rhs.0.utf8) }
            return lhs.1.utf8.lexicographicallyPrecedes(rhs.1.utf8)
        }
        return pairs
            .map { "\(quote($0.0, keeping: unreserved))=\(quote($0.1, keeping: unreserved))" }
            .joined(separator: "&")
    }

    /// '+' becomes a space, then percent-decoding (invalid escapes are kept literally).
    private static func qsDecode(_ s: String) -> String {
        let spaced = s.replacingOccurrences(of: "+", with: " ")
        return spaced.removingPercentEncoding ?? spaced
    }

    private static func collapseWhitespace(_ s: String) -> String {
        s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private static func formatDates(_ date: Date) -> (amzDate: String, dateStamp: String) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let day = String(format: "%04d%02d%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        let time = String(format: "%02d%02d%02d", c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
        return ("\(day)T\(time)Z", day)
    }

    private static func hmac(key: Data, message: String) -> Data {
        let code = HMAC<SHA256>.authenticationCode(
            for: Data(message.utf8), using: SymmetricKey(data: key))
        return Data(code)
    }

    private static func hex<D: Sequence>(_ bytes: D) -> String where D.Element == UInt8 {
        bytes.map { String(format: "%02x", $0) }.joined()
    }
}
