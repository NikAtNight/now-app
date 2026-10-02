/// Lists in plain-text notes, the way Notes and Reminders handle them. A line starting with "• ",
/// "- ", "* ", or "1. " is a list item. Return starts the next item, Return on an empty item ends
/// the list, and typing "- " or "* " at the start of a line makes a "• " bullet.
/// Positions are character offsets.
public enum NoteList {
    public struct Edit: Equatable, Sendable {
        public var text: String
        public var cursor: Int

        public init(text: String, cursor: Int) {
            self.text = text
            self.cursor = cursor
        }
    }

    /// Return pressed with `selection` selected (an empty range is the cursor).
    public static func newline(in text: String, replacing selection: Range<Int>) -> Edit {
        let chars = Array(text)
        let start = lineStart(chars, at: selection.lowerBound)
        let end = chars[selection.lowerBound...].firstIndex(of: "\n") ?? chars.count
        let line = chars[start..<end]
        guard let marker = marker(of: line), selection.lowerBound >= start + marker.count else {
            return replace(chars, selection, with: "\n")
        }
        if line.count == marker.count && selection.isEmpty {
            return replace(chars, start..<end, with: "")
        }
        return replace(chars, selection, with: "\n" + next(after: marker))
    }

    /// The list formatting a typed change calls for, or nil when there's none. Only a single typed
    /// character counts: a newline (iPhone types Return into the text) or the space after "-" or "*".
    public static func format(from old: String, to new: String) -> Edit? {
        let a = Array(old), b = Array(new)
        guard b.count == a.count + 1 else { return nil }
        var at = zip(a, b).prefix(while: { $0 == $1 }).count
        let typed = b[at]
        guard a[at...] == b[(at + 1)...] else { return nil }
        // A newline next to another reads the same from either side. Take the earliest spot, so
        // it counts as Return at the end of the line before.
        if typed == "\n" {
            while at > 0 && a[at - 1] == "\n" { at -= 1 }
        }

        switch typed {
        case "\n":
            let edit = newline(in: old, replacing: at..<at)
            return edit.text == new ? nil : edit
        case " ":
            let start = lineStart(a, at: at)
            let indent = a[start..<at].prefix(while: { $0 == " " || $0 == "\t" })
            let typedOnLine = a[(start + indent.count)..<at]
            guard typedOnLine.elementsEqual("-") || typedOnLine.elementsEqual("*") else { return nil }
            return replace(a, (at - 1)..<at, with: "• ")
        default:
            return nil
        }
    }

    private static func lineStart(_ chars: [Character], at offset: Int) -> Int {
        chars[..<offset].lastIndex(of: "\n").map { $0 + 1 } ?? 0
    }

    /// "  • ", "- ", "12. ": the indent, marker, and space a list line starts with.
    private static func marker(of line: ArraySlice<Character>) -> String? {
        let indent = line.prefix(while: { $0 == " " || $0 == "\t" })
        let rest = line.dropFirst(indent.count)
        let symbol: ArraySlice<Character>
        if let first = rest.first, "•-*".contains(first) {
            symbol = rest.prefix(1)
        } else {
            let digits = rest.prefix(while: \.isASCIIDigit)
            guard !digits.isEmpty, let separator = rest.dropFirst(digits.count).first, ".)".contains(separator) else { return nil }
            symbol = rest.prefix(digits.count + 1)
        }
        guard rest.dropFirst(symbol.count).first == " " else { return nil }
        return String(indent + symbol) + " "
    }

    /// The same bullet, or the next number.
    private static func next(after marker: String) -> String {
        let indent = marker.prefix(while: { $0 == " " || $0 == "\t" })
        let digits = marker.dropFirst(indent.count).prefix(while: \.isASCIIDigit)
        guard let number = Int(digits) else { return marker }
        return String(indent) + String(number + 1) + marker.dropFirst(indent.count + digits.count)
    }

    private static func replace(_ chars: [Character], _ range: Range<Int>, with insert: String) -> Edit {
        var result = chars
        result.replaceSubrange(range, with: insert)
        return Edit(text: String(result), cursor: range.lowerBound + insert.count)
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
