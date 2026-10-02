import Testing
@testable import NowCore

struct NoteListTests {
    /// Return with the cursor at the end of `text`.
    private func returnAtEnd(_ text: String) -> NoteList.Edit {
        NoteList.newline(in: text, replacing: text.count..<text.count)
    }

    @Test func returnContinuesABulletList() {
        #expect(returnAtEnd("• Milk") == .init(text: "• Milk\n• ", cursor: 9))
        #expect(returnAtEnd("Shop:\n- Milk") == .init(text: "Shop:\n- Milk\n- ", cursor: 15))
        #expect(returnAtEnd("* Milk") == .init(text: "* Milk\n* ", cursor: 9))
    }

    @Test func returnCountsUpANumberedList() {
        #expect(returnAtEnd("1. Milk") == .init(text: "1. Milk\n2. ", cursor: 11))
        #expect(returnAtEnd("9) Eggs") == .init(text: "9) Eggs\n10) ", cursor: 12))
    }

    @Test func returnKeepsTheIndent() {
        #expect(returnAtEnd("  • Milk") == .init(text: "  • Milk\n  • ", cursor: 13))
    }

    @Test func returnOnAnEmptyItemEndsTheList() {
        #expect(returnAtEnd("• Milk\n• ") == .init(text: "• Milk\n", cursor: 7))
        #expect(returnAtEnd("1. Milk\n2. ") == .init(text: "1. Milk\n", cursor: 8))
    }

    @Test func returnInTheMiddleOfAnItemSplitsIt() {
        // "• Milk| and eggs" -> a new item holding the rest of the line.
        #expect(NoteList.newline(in: "• Milk and eggs", replacing: 6..<6) == .init(text: "• Milk\n•  and eggs", cursor: 9))
    }

    @Test func returnReplacesTheSelection() {
        #expect(NoteList.newline(in: "• Milk and eggs", replacing: 6..<15) == .init(text: "• Milk\n• ", cursor: 9))
    }

    @Test func plainLinesGetAPlainNewline() {
        #expect(returnAtEnd("Call Sam") == .init(text: "Call Sam\n", cursor: 9))
        #expect(returnAtEnd("") == .init(text: "\n", cursor: 1))
        // Not a list: no space after the marker, or a number without a separator.
        #expect(returnAtEnd("-5 degrees") == .init(text: "-5 degrees\n", cursor: 11))
        #expect(returnAtEnd("2026 plan") == .init(text: "2026 plan\n", cursor: 10))
    }

    @Test func returnBeforeTheMarkerIsAPlainNewline() {
        #expect(NoteList.newline(in: "• Milk", replacing: 0..<0) == .init(text: "\n• Milk", cursor: 1))
    }

    @Test func typedDashOrStarBecomesABullet() {
        #expect(NoteList.format(from: "-", to: "- ") == .init(text: "• ", cursor: 2))
        #expect(NoteList.format(from: "Shop:\n*", to: "Shop:\n* ") == .init(text: "Shop:\n• ", cursor: 8))
        #expect(NoteList.format(from: "  -", to: "  - ") == .init(text: "  • ", cursor: 4))
        // Typed at the start of a line that already has text.
        #expect(NoteList.format(from: "-Milk", to: "- Milk") == .init(text: "• Milk", cursor: 2))
    }

    @Test func dashInsideALineStaysADash() {
        #expect(NoteList.format(from: "a -", to: "a - ") == nil)
        #expect(NoteList.format(from: "--", to: "-- ") == nil)
    }

    @Test func typedNewlineContinuesTheList() {
        // iPhone types Return into the text, so it arrives as a change.
        #expect(NoteList.format(from: "• Milk", to: "• Milk\n") == .init(text: "• Milk\n• ", cursor: 9))
        #expect(NoteList.format(from: "• Milk\n• ", to: "• Milk\n• \n") == .init(text: "• Milk\n", cursor: 7))
        #expect(NoteList.format(from: "Call Sam", to: "Call Sam\n") == nil)
    }

    @Test func typedNewlineNextToAnotherIsReadAsEndOfLine() {
        // "• Milk\n• Eggs" with Return at the end of Milk reads the same as Return at the start of
        // Eggs. End of line is the likelier one.
        #expect(NoteList.format(from: "• Milk\n• Eggs", to: "• Milk\n\n• Eggs") == .init(text: "• Milk\n• \n• Eggs", cursor: 9))
    }

    @Test func otherChangesAreLeftAlone() {
        #expect(NoteList.format(from: "• Milk", to: "• Milks") == nil)
        #expect(NoteList.format(from: "• Milk", to: "• Mil") == nil)
        #expect(NoteList.format(from: "", to: "pasted\n- text ") == nil)
        // Our own edit coming back through the change handler.
        #expect(NoteList.format(from: "• Milk", to: "• Milk\n• ") == nil)
    }
}
