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

        return nil
    }
}
