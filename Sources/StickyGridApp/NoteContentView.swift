import StickyGridCore
import SwiftUI

/// SwiftUI content of one note: header drag strip, rich text editor,
/// and the hover-fade toolbar along the bottom.
struct NoteContentView: View {
    let viewModel: NoteViewModel
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: 26) // header drag strip
            RichTextEditor(viewModel: viewModel)
                .padding(.horizontal, 4)
                .padding(.bottom, 4)
        }
        .overlay(alignment: .bottom) {
            NoteToolbarView(viewModel: viewModel)
                .padding(.bottom, 8)
                .opacity(hovering ? 1 : 0)
                .animation(.easeInOut(duration: 0.15), value: hovering)
                .allowsHitTesting(hovering)
        }
        .onHover { hovering = $0 }
    }
}
