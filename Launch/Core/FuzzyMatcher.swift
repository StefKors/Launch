import Foundation

/// Scores how well a query matches a name. Higher is better, `nil` is no match.
///
/// Tiers, best first: exact, name prefix, word prefix, initials ("vsc" for
/// Visual Studio Code), every term prefixing a word, substring, subsequence.
nonisolated enum FuzzyMatcher {
    static func score(_ query: String, in candidate: String) -> Double? {
        let q = fold(query).trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return nil }

        let name = fold(candidate)
        if name == q { return 1000 }
        if name.hasPrefix(q) { return 900 - Double(name.count - q.count) * 0.5 }

        let words = words(in: candidate).map(fold)
        let terms = q.split(separator: " ").map(String.init)

        if terms.count == 1 {
            if let i = words.firstIndex(where: { $0.hasPrefix(q) }) {
                return 800 - Double(i) * 10 - Double(words[i].count - q.count) * 0.2
            }
        } else if let range = name.range(of: q), isWordStart(name, range.lowerBound) {
            return 800 - Double(name.distance(from: name.startIndex, to: range.lowerBound)) * 0.5
        }

        let compact = q.replacingOccurrences(of: " ", with: "")
        if compact.count >= 2 {
            let initials = String(words.compactMap(\.first))
            if initials.hasPrefix(compact) {
                return 700 - Double(initials.count - compact.count) * 2
            }
        }

        if terms.count > 1, termsPrefixWordsInOrder(terms, words) { return 650 }

        if let range = name.range(of: q) {
            return 500 - Double(name.distance(from: name.startIndex, to: range.lowerBound)) * 0.5
        }

        return subsequenceScore(compact, in: name)
    }

    private static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// Splits on anything that isn't a letter or digit and on camelCase
    /// boundaries ("QuickTime" -> Quick, Time).
    private static func words(in s: String) -> [String] {
        var result: [String] = []
        var current = ""
        var previous: Character?
        for ch in s {
            if !(ch.isLetter || ch.isNumber) {
                if !current.isEmpty { result.append(current); current = "" }
            } else {
                if let p = previous, p.isLowercase, ch.isUppercase, !current.isEmpty {
                    result.append(current)
                    current = ""
                }
                current.append(ch)
            }
            previous = ch
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    private static func isWordStart(_ s: String, _ i: String.Index) -> Bool {
        i == s.startIndex || !(s[s.index(before: i)].isLetter || s[s.index(before: i)].isNumber)
    }

    private static func termsPrefixWordsInOrder(_ terms: [String], _ words: [String]) -> Bool {
        var next = 0
        for term in terms {
            guard let i = words[next...].firstIndex(where: { $0.hasPrefix(term) }) else { return false }
            next = i + 1
        }
        return true
    }

    /// Every query character appears in order. Runs of adjacent characters
    /// and matches at word starts score higher.
    private static func subsequenceScore(_ q: String, in name: String) -> Double? {
        var chars = q.makeIterator()
        var want = chars.next()
        var score = 100.0
        var lastMatch: String.Index?
        for i in name.indices {
            guard let w = want else { break }
            if name[i] == w {
                if let last = lastMatch, name.index(after: last) == i { score += 8 }
                if isWordStart(name, i) { score += 6 }
                lastMatch = i
                want = chars.next()
            } else if lastMatch != nil {
                score -= 1
            }
        }
        guard want == nil else { return nil }
        return min(max(score, 50), 299)
    }
}
