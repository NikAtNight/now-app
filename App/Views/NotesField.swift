import NowCore
import SwiftUI

/// A task's notes, with Reminders-style lists (see `NoteList`). Callers style it like a text field.
struct NotesField: View {
    @Binding var text: String
    @State private var selection: TextSelection?

    var body: some View {
        TextField("Notes", text: $text, selection: $selection, prompt: Text("Notes"), axis: .vertical)
            #if os(macOS)
            // A Mac text field takes Return as submit, so without this notes never get a second line.
            .onKeyPress(.return) {
                apply(NoteList.newline(in: text, replacing: selectedRange))
                return .handled
            }
            #endif
            // iPhone types Return into the text, so it shows up here along with "- " and "* ".
            .onChange(of: text) { old, new in
                if let edit = NoteList.format(from: old, to: new) { apply(edit) }
            }
    }

    /// The selection as character offsets. With no selection yet, the end of the text.
    private var selectedRange: Range<Int> {
        guard case .selection(let range) = selection?.indices, range.upperBound <= text.endIndex else {
            return text.count..<text.count
        }
        return text.distance(from: text.startIndex, to: range.lowerBound)..<text.distance(from: text.startIndex, to: range.upperBound)
    }

    private func apply(_ edit: NoteList.Edit) {
        text = edit.text
        // From `edit.text`: reading `text` straight after the write can still return the old value.
        selection = TextSelection(insertionPoint: edit.text.index(edit.text.startIndex, offsetBy: edit.cursor))
    }
}
