//
//  SensitiveText.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/17/26.
//

import Foundation

/// Spots text that shouldn't end up in a video: email addresses, card numbers and API keys or tokens.
public enum SensitiveText {
    public enum Kind: String, Sendable {
        case email, card, key

        public var label: String {
            switch self {
            case .email: "Email"
            case .card: "Card number"
            case .key: "Key"
            }
        }
    }

    public struct Match: Equatable {
        public var kind: Kind
        public var range: Range<String.Index>
    }

    private static let email = try! NSRegularExpression(pattern: #"[A-Za-z0-9._%+\-]+@[A-Za-z0-9\-]+(\.[A-Za-z0-9\-]+)*\.[A-Za-z]{2,}"#)
    private static let card = try! NSRegularExpression(pattern: #"(?<![\d])\d(?:[ \-]?\d){12,18}(?![\d])"#)
    /// Well-known key and token prefixes, then a JWT, then any long run mixing letters and digits.
    private static let keys = [
        #"\b(?:sk|pk|rk)[-_](?:live|test|proj|ant)?[-_]?[A-Za-z0-9_\-]{16,}"#,
        #"\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{20,}"#,
        #"\bgithub_pat_[A-Za-z0-9_]{20,}"#,
        #"\bxox[abprs]-[A-Za-z0-9\-]{10,}"#,
        #"\bAKIA[0-9A-Z]{16}\b"#,
        #"\bAIza[0-9A-Za-z_\-]{30,}"#,
        #"\beyJ[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}"#,
        #"(?<![A-Za-z0-9])(?=[A-Za-z0-9_\-]*\d)(?=[A-Za-z0-9_\-]*[A-Za-z])[A-Za-z0-9_\-]{32,}(?![A-Za-z0-9])"#,
    ].map { try! NSRegularExpression(pattern: $0) }

    public static func matches(in line: String) -> [Match] {
        var out: [Match] = []
        let whole = NSRange(line.startIndex..., in: line)
        func add(_ regex: NSRegularExpression, _ kind: Kind, accept: (String) -> Bool = { _ in true }) {
            for m in regex.matches(in: line, range: whole) {
                guard let r = Range(m.range, in: line), accept(String(line[r])),
                      !out.contains(where: { $0.range.overlaps(r) }) else { continue }
                out.append(Match(kind: kind, range: r))
            }
        }
        add(email, .email)
        add(card, .card) { isCardNumber($0) }
        for k in keys { add(k, .key) }
        return out.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    /// The Luhn check every card number passes, which rules out most long numbers that aren't cards.
    static func isCardNumber(_ text: String) -> Bool {
        let digits = text.compactMap(\.wholeNumberValue)
        guard (13 ... 19).contains(digits.count), Set(digits).count > 1 else { return false }
        var sum = 0
        for (i, d) in digits.reversed().enumerated() {
            let v = i % 2 == 1 ? d * 2 : d
            sum += v > 9 ? v - 9 : v
        }
        return sum % 10 == 0
    }
}
