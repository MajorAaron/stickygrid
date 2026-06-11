import StickyGridCore
import SwiftUI

extension Color {
    init(_ rgb: NoteColor.RGB) {
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

/// Slim icon toolbar that fades in on hover. The palette button swaps the
/// icon row for inline color swatches (more reliable than popovers in a
/// borderless window).
struct NoteToolbarView: View {
    let viewModel: NoteViewModel
    @State private var showingPalette = false

    private static let fontFamilies = [
        "System", "Helvetica Neue", "Avenir Next", "Georgia",
        "Times New Roman", "Menlo", "Marker Felt", "Noteworthy",
    ]
    private static let fontSizes: [Double] = [11, 12, 14, 16, 18, 21, 24]

    var body: some View {
        HStack(spacing: 12) {
            if showingPalette {
                paletteRow
            } else {
                iconRow
            }
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(Color(viewModel.colorID.foreground).opacity(0.65))
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(
            Capsule().fill(Color(viewModel.colorID.background).opacity(0.85))
                .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
        )
    }

    private var iconRow: some View {
        Group {
            toolbarButton("plus", help: "New Note") { viewModel.onNewNote() }
            toolbarButton("paintpalette", help: "Note Color") {
                showingPalette = true
            }
            fontMenu
            toolbarButton(viewModel.pinned ? "pin.fill" : "pin",
                          help: viewModel.pinned ? "Unpin" : "Keep on Top") {
                viewModel.pinned.toggle()
                viewModel.onAppearanceChanged()
            }
            toolbarButton("square.grid.2x2", help: "Arrange Notes") { viewModel.onTile() }
            toolbarButton("trash", help: "Delete Note") { viewModel.onDelete() }
        }
    }

    private var paletteRow: some View {
        Group {
            ForEach(NoteColor.allCases, id: \.self) { color in
                Button {
                    viewModel.colorID = color
                    viewModel.onAppearanceChanged()
                    showingPalette = false
                } label: {
                    Circle()
                        .fill(Color(color.background))
                        .overlay(
                            Circle().strokeBorder(
                                color == viewModel.colorID
                                    ? Color(color.foreground).opacity(0.8)
                                    : .black.opacity(0.18),
                                lineWidth: color == viewModel.colorID ? 2 : 1)
                        )
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .help(color.rawValue.capitalized)
            }
            toolbarButton("xmark", help: "Close Palette") { showingPalette = false }
        }
    }

    private var fontMenu: some View {
        Menu {
            Section("Font") {
                ForEach(Self.fontFamilies, id: \.self) { family in
                    Button {
                        viewModel.fontName = family
                        viewModel.onAppearanceChanged()
                    } label: {
                        if family == viewModel.fontName {
                            Label(family, systemImage: "checkmark")
                        } else {
                            Text(family)
                        }
                    }
                }
            }
            Section("Size") {
                ForEach(Self.fontSizes, id: \.self) { size in
                    Button {
                        viewModel.fontSize = size
                        viewModel.onAppearanceChanged()
                    } label: {
                        if size == viewModel.fontSize {
                            Label("\(Int(size)) pt", systemImage: "checkmark")
                        } else {
                            Text("\(Int(size)) pt")
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "textformat")
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Font")
    }

    private func toolbarButton(
        _ symbol: String, help: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
