import StickyGridCore
import SwiftUI

/// SwiftUI content of one note: header drag strip + text area.
/// M2 placeholder: a plain TextEditor to verify focus/typing; the real
/// rich-text editor replaces it in M4.
struct NoteContentView: View {
    @State private var text = ""

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: 26) // header drag strip
            TextEditor(text: $text)
                .font(.system(size: 14))
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
        }
    }
}
