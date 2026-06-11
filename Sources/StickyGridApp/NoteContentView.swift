import StickyGridCore
import SwiftUI

/// SwiftUI content of one note: header drag strip + rich text editor.
/// The hover toolbar overlays the header in M6.
struct NoteContentView: View {
    let viewModel: NoteViewModel

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: 26) // header drag strip
            RichTextEditor(viewModel: viewModel)
                .padding(.horizontal, 4)
                .padding(.bottom, 4)
        }
    }
}
