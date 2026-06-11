import Foundation
import Testing
@testable import StickyGridCore

private let screen = CGRect(x: 0, y: 0, width: 1440, height: 800)
private let gap: CGFloat = 8

/// Deterministic generator so scatter tests are reproducible.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

private func rectsOverlap(_ a: CGRect, _ b: CGRect) -> Bool {
    let inter = a.intersection(b)
    return !inter.isNull && inter.width > 0.01 && inter.height > 0.01
}

private func assertAllInside(_ rects: [CGRect], file: StaticString = #filePath) {
    let inset = screen.insetBy(dx: gap - 0.01, dy: gap - 0.01)
    for rect in rects {
        #expect(inset.contains(rect), "\(rect) escapes \(inset)")
    }
}

private func assertNoOverlaps(_ rects: [CGRect]) {
    for i in rects.indices {
        for j in rects.indices where j > i {
            #expect(!rectsOverlap(rects[i], rects[j]),
                    "rects \(i) and \(j) overlap: \(rects[i]) vs \(rects[j])")
        }
    }
}

@Suite("Even grid layout")
struct EvenGridTests {

    @Test("empty input yields empty output")
    func emptyInput() {
        #expect(GridLayouts.evenGrid(count: 0, in: screen, gap: gap) == [])
    }

    @Test("a single note fills the bounds minus the outer margin")
    func singleNote() {
        let rects = GridLayouts.evenGrid(count: 1, in: screen, gap: gap)
        #expect(rects == [screen.insetBy(dx: gap, dy: gap)])
    }

    @Test("every cell has the same size", arguments: [2, 3, 5, 7, 12])
    func uniformCells(count: Int) {
        let rects = GridLayouts.evenGrid(count: count, in: screen, gap: gap)
        #expect(rects.count == count)
        guard let first = rects.first else { return }
        for rect in rects {
            #expect(abs(rect.width - first.width) < 0.5, "widths differ")
            #expect(abs(rect.height - first.height) < 0.5, "heights differ")
        }
    }

    @Test("cells stay inside bounds and never overlap")
    func containmentAndOverlap() {
        for count in [2, 4, 6, 9, 17, 30] {
            let rects = GridLayouts.evenGrid(count: count, in: screen, gap: gap)
            assertAllInside(rects)
            assertNoOverlaps(rects)
        }
    }

    @Test("a wide screen gets more columns than rows")
    func aspectAwareColumns() {
        let rects = GridLayouts.evenGrid(count: 6, in: screen, gap: gap)
        let columns = Set(rects.map { ($0.minX * 10).rounded() }).count
        let rows = Set(rects.map { ($0.minY * 10).rounded() }).count
        #expect(columns >= rows, "expected at least as many columns (\(columns)) as rows (\(rows)) on a 1440x800 screen")
    }
}

@Suite("Columns (masonry) layout")
struct ColumnsLayoutTests {

    @Test("empty input yields empty output")
    func emptyInput() {
        #expect(GridLayouts.columns(sizes: [], in: screen, gap: gap) == [])
    }

    @Test("returns one rect per size, all inside bounds, none overlapping")
    func basics() {
        let sizes = [CGSize(width: 320, height: 240), CGSize(width: 200, height: 400),
                     CGSize(width: 400, height: 180), CGSize(width: 320, height: 320),
                     CGSize(width: 280, height: 200)]
        let rects = GridLayouts.columns(sizes: sizes, in: screen, gap: gap)
        #expect(rects.count == sizes.count)
        assertAllInside(rects)
        assertNoOverlaps(rects)
    }

    @Test("all notes share the same column width")
    func equalWidths() {
        let sizes = (0..<6).map { CGSize(width: 200 + 40 * $0, height: 240) }
        let rects = GridLayouts.columns(sizes: sizes, in: screen, gap: gap)
        guard let first = rects.first else { return }
        for rect in rects {
            #expect(abs(rect.width - first.width) < 0.5, "column widths differ")
        }
    }

    @Test("notes keep their aspect ratio when there is room")
    func aspectPreserved() {
        let sizes = [CGSize(width: 400, height: 150), CGSize(width: 400, height: 200),
                     CGSize(width: 400, height: 180), CGSize(width: 360, height: 140),
                     CGSize(width: 360, height: 200), CGSize(width: 400, height: 160),
                     CGSize(width: 320, height: 120), CGSize(width: 360, height: 160),
                     CGSize(width: 400, height: 190)]
        let rects = GridLayouts.columns(sizes: sizes, in: screen, gap: gap)
        for (size, rect) in zip(sizes, rects) {
            let original = size.height / size.width
            let laidOut = rect.height / rect.width
            #expect(abs(original - laidOut) < 0.01,
                    "aspect changed: \(original) -> \(laidOut)")
        }
    }

    @Test("a tall stack of notes is scaled to fit the screen height")
    func overflowScalesDown() {
        let sizes = Array(repeating: CGSize(width: 320, height: 700), count: 12)
        let rects = GridLayouts.columns(sizes: sizes, in: screen, gap: gap)
        assertAllInside(rects)
        assertNoOverlaps(rects)
    }
}

@Suite("Scatter layout")
struct ScatterLayoutTests {

    private let sizes = [CGSize(width: 320, height: 240), CGSize(width: 260, height: 300),
                         CGSize(width: 400, height: 220), CGSize(width: 220, height: 220),
                         CGSize(width: 340, height: 260), CGSize(width: 280, height: 240),
                         CGSize(width: 300, height: 200)]

    @Test("empty input yields empty output")
    func emptyInput() {
        var rng = SeededGenerator(seed: 1)
        #expect(GridLayouts.scatter(sizes: [], in: screen, gap: gap, using: &rng) == [])
    }

    @Test("returns one rect per size, all inside bounds")
    func countAndContainment() {
        var rng = SeededGenerator(seed: 7)
        let rects = GridLayouts.scatter(sizes: sizes, in: screen, gap: gap, using: &rng)
        #expect(rects.count == sizes.count)
        assertAllInside(rects)
    }

    @Test("scattered notes never overlap", arguments: [1, 2, 3, 42, 99] as [UInt64])
    func noOverlap(seed: UInt64) {
        var rng = SeededGenerator(seed: seed)
        let rects = GridLayouts.scatter(sizes: sizes, in: screen, gap: gap, using: &rng)
        assertNoOverlaps(rects)
    }

    @Test("a crowded screen still produces a non-overlapping layout")
    func crowdedScreen() {
        var rng = SeededGenerator(seed: 5)
        let many = Array(repeating: CGSize(width: 360, height: 300), count: 16)
        let rects = GridLayouts.scatter(sizes: many, in: screen, gap: gap, using: &rng)
        #expect(rects.count == many.count)
        assertAllInside(rects)
        assertNoOverlaps(rects)
    }

    @Test("the same seed reproduces the same layout")
    func deterministic() {
        var a = SeededGenerator(seed: 11)
        var b = SeededGenerator(seed: 11)
        let first = GridLayouts.scatter(sizes: sizes, in: screen, gap: gap, using: &a)
        let second = GridLayouts.scatter(sizes: sizes, in: screen, gap: gap, using: &b)
        #expect(first == second)
    }

    @Test("different seeds produce different layouts")
    func seedsVary() {
        var a = SeededGenerator(seed: 11)
        var b = SeededGenerator(seed: 12)
        let first = GridLayouts.scatter(sizes: sizes, in: screen, gap: gap, using: &a)
        let second = GridLayouts.scatter(sizes: sizes, in: screen, gap: gap, using: &b)
        #expect(first != second)
    }
}
