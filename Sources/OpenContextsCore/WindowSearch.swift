import Foundation

public enum WindowSearch {
    public struct Match {
        public let window: WindowInfo
        public let appRanges: [NSRange]
        public let titleRanges: [NSRange]
        fileprivate let score: Int
    }

    public static func filter(_ windows: [WindowInfo], query: String) -> [Match] {
        var matches: [(match: Match, index: Int)] = []
        for (index, window) in windows.enumerated() {
            if let match = match(window, query: query) {
                matches.append((match, index))
            }
        }
        matches.sort {
            $0.match.score == $1.match.score ? $0.index < $1.index : $0.match.score > $1.match.score
        }
        return matches.map(\.match)
    }

    public static func match(_ window: WindowInfo, query: String) -> Match? {
        var appRanges: [NSRange] = []
        var titleRanges: [NSRange] = []
        var score = 0
        for token in query.split(whereSeparator: \.isWhitespace) {
            let app = matchText(window.appName, token: String(token))
            let title = matchText(window.displayTitle, token: String(token))
            guard app != nil || title != nil else { return nil }
            appRanges += app?.ranges ?? []
            titleRanges += title?.ranges ?? []
            score += max(app?.score ?? Int.min, title?.score ?? Int.min)
        }
        return Match(window: window, appRanges: appRanges, titleRanges: titleRanges, score: score)
    }

    private static func matchText(_ text: String, token: String) -> (score: Int, ranges: [NSRange])? {
        func isWordStart(_ index: String.Index) -> Bool {
            guard index != text.startIndex else { return true }
            let previous = text[text.index(before: index)]
            return !previous.isLetter && !previous.isNumber
                || previous.isLowercase && text[index].isUppercase
        }

        if let range = text.range(of: token, options: [.caseInsensitive, .diacriticInsensitive]) {
            let score = range == text.startIndex..<text.endIndex ? 1_000
                : range.lowerBound == text.startIndex ? 700
                : isWordStart(range.lowerBound) ? 600 : 500
            return (score, [NSRange(range, in: text)])
        }

        return matchPinyin(text, token: token)
    }

    /// Matches an ASCII token against the toneless pinyin of Chinese characters, e.g. "weixin" or "weix" for 微信.
    /// The match starts at a character and may end inside the last syllable; highlights cover whole characters.
    private static func matchPinyin(_ text: String, token: String) -> (score: Int, ranges: [NSRange])? {
        guard token.unicodeScalars.allSatisfy(\.isASCII),
              text.unicodeScalars.contains(where: isHan) else { return nil }
        let token = token.lowercased()
        let indices = Array(text.indices)
        let syllables = indices.map { pinyin(for: text[$0]) }

        for start in indices.indices where syllables[start].first.map({ token.hasPrefix(String($0)) }) == true {
            var remaining = Substring(token)
            var end = start
            var endsMidSyllable = false
            while end < indices.count, !remaining.isEmpty {
                let syllable = syllables[end]
                if remaining.hasPrefix(syllable) {
                    remaining = remaining.dropFirst(syllable.count)
                } else if syllable.hasPrefix(remaining) {
                    remaining = ""
                    endsMidSyllable = true
                } else {
                    break
                }
                end += 1
            }
            guard remaining.isEmpty else { continue }
            let range = indices[start]..<(end < indices.count ? indices[end] : text.endIndex)
            // Pinyin matches rank just below the equivalent literal match.
            let score = !endsMidSyllable && range == text.startIndex..<text.endIndex ? 950
                : start == 0 ? 650
                : isHan(text[indices[start]].unicodeScalars.first!) || !text[indices[start - 1]].isLetter ? 550 : 450
            return (score, [NSRange(range, in: text)])
        }
        return nil
    }

    private static let pinyinCache = NSCache<NSString, NSString>()

    private static func pinyin(for character: Character) -> String {
        guard let scalar = character.unicodeScalars.first, isHan(scalar) else { return character.lowercased() }
        let key = String(character) as NSString
        if let cached = pinyinCache.object(forKey: key) { return cached as String }
        let latin = String(character).applyingTransform(.mandarinToLatin, reverse: false)?
            .applyingTransform(.stripDiacritics, reverse: false)?
            .lowercased().filter { !$0.isWhitespace } ?? ""
        let value = latin.isEmpty ? character.lowercased() : latin
        pinyinCache.setObject(value as NSString, forKey: key)
        return value
    }

    private static func isHan(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x2EBEF: true
        default: false
        }
    }
}
