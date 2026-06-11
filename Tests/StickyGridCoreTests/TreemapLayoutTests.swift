import Foundation
import Testing
@testable import StickyGridCore

private let screen = CGRect(x: 0, y: 0, width: 1440, height: 800)
private let gap: CGFloat = 8

/// Deterministic LCG so randomized tests are reproducible.
private struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / Double(1 << 53)
    }
}

private func areasOverlap(_ a: CGRect, _ b: CGRect) -> Bool {
    let inter = a.intersection(b)
    return !inter.isNull && inter.width > 0.01 && inter.height > 0.01
}

@Suite("Treemap layout")
struct TreemapLayoutTests {

    @Test("empty input yields empty output")
    func emptyInput() {
        #expect(Treemap.layout(weights: [], in: screen, gap: gap) == [])
    }

    @Test("a single note fills the bounds minus the outer margin")
    func singleNote() {
        let rects = Treemap.layout(weights: [1], in: screen, gap: gap)
        #expect(rects == [screen.insetBy(dx: gap, dy: gap)])
    }

    @Test("returns one rect per weight, all inside bounds")
    func countAndContainment() {
        let rects = Treemap.layout(weights: [1, 2, 3, 4, 5, 6], in: screen, gap: gap)
        #expect(rects.count == 6)
        let inset = screen.insetBy(dx: gap - 0.01, dy: gap - 0.01)
        for rect in rects {
            #expect(inset.contains(rect), "\(rect) escapes \(inset)")
        }
    }

    @Test("tiles never overlap and neighbors are separated by the gap")
    func nonOverlapping() {
        let rects = Treemap.layout(weights: [5, 1, 3, 2, 4], in: screen, gap: gap)
        for i in rects.indices {
            for j in rects.indices where j > i {
                #expect(!areasOverlap(rects[i], rects[j]),
                        "rects \(i) and \(j) overlap: \(rects[i]) vs \(rects[j])")
                let grown = rects[i].insetBy(dx: -gap + 0.5, dy: -gap + 0.5)
                if areasOverlap(grown, rects[j]) {
                    // neighbors: ensure they are at least ~gap apart on some axis
                    let dx = max(rects[j].minX - rects[i].maxX, rects[i].minX - rects[j].maxX)
                    let dy = max(rects[j].minY - rects[i].maxY, rects[i].minY - rects[j].maxY)
                    #expect(max(dx, dy) >= gap - 0.5,
                            "rects \(i) and \(j) closer than gap: dx=\(dx) dy=\(dy)")
                }
            }
        }
    }

    @Test("mosaic fills most of the screen")
    func coverage() {
        let rects = Treemap.layout(weights: [1, 1, 1, 1, 1, 1, 1, 1], in: screen, gap: gap)
        let total = rects.reduce(0) { $0 + $1.width * $1.height }
        let available = screen.insetBy(dx: gap, dy: gap)
        #expect(total >= 0.8 * available.width * available.height,
                "tiles cover only \(total) of \(available.width * available.height)")
    }

    @Test("areas are roughly proportional to weights")
    func proportionality() {
        let rects = Treemap.layout(weights: [200_000, 100_000], in: screen, gap: gap)
        let a0 = rects[0].width * rects[0].height
        let a1 = rects[1].width * rects[1].height
        let ratio = a0 / a1
        #expect(ratio > 1.5 && ratio < 2.5, "expected ~2:1 area ratio, got \(ratio)")
    }

    @Test("output order matches input order")
    func orderPreservation() {
        let rects = Treemap.layout(weights: [100_000, 500_000, 250_000], in: screen, gap: gap)
        let areas = rects.map { $0.width * $0.height }
        #expect(areas[1] > areas[2] && areas[2] > areas[0],
                "areas \(areas) should follow weight order [small, large, medium]")
    }

    @Test("zero weights are floored, producing usable tiles")
    func zeroWeightFloor() {
        let rects = Treemap.layout(weights: [0, 0], in: screen, gap: gap)
        #expect(rects.count == 2)
        for rect in rects {
            #expect(rect.width > 10 && rect.height > 10, "degenerate tile \(rect)")
        }
        let a0 = rects[0].width * rects[0].height
        let a1 = rects[1].width * rects[1].height
        #expect(abs(a0 - a1) / max(a0, a1) < 0.2, "equal weights should give similar areas")
    }

    @Test("a tiny weight next to a huge one still gets a fair floor share")
    func skewedWeights() {
        let rects = Treemap.layout(weights: [1, 4_000_000], in: screen, gap: gap)
        let small = rects[0]
        let minArea = Treemap.minNoteSize.width * Treemap.minNoteSize.height
        let total = 4_000_000 + minArea
        let availableArea = Double(screen.insetBy(dx: gap, dy: gap).width *
                                   screen.insetBy(dx: gap, dy: gap).height)
        let expectedShare = minArea / total * availableArea
        let actual = Double(small.width * small.height)
        #expect(actual >= expectedShare * 0.5,
                "small note got \(actual), expected at least \(expectedShare * 0.5)")
    }

    @Test("randomized inputs keep invariants (fixed seed)")
    func randomizedInvariants() {
        var rng = SeededRandom(seed: 42)
        for trial in 0..<25 {
            let n = 1 + Int(rng.next() * 19)
            let weights = (0..<n).map { _ in rng.next() * 400_000 }
            let rects = Treemap.layout(weights: weights, in: screen, gap: gap)
            #expect(rects.count == n, "trial \(trial): count mismatch")
            let inset = screen.insetBy(dx: gap - 0.01, dy: gap - 0.01)
            for rect in rects {
                #expect(inset.contains(rect), "trial \(trial): \(rect) escapes bounds")
                #expect(rect.width > 0 && rect.height > 0, "trial \(trial): degenerate \(rect)")
            }
            for i in rects.indices {
                for j in rects.indices where j > i {
                    #expect(!areasOverlap(rects[i], rects[j]),
                            "trial \(trial): rects \(i)/\(j) overlap")
                }
            }
        }
    }
}
