import Foundation

/// Pure layout math for the non-mosaic arrangements: even grid, masonry
/// columns, and random non-overlapping scatter. Like `Treemap.layout`, every
/// function maps note geometry in, screen rects out (same order as input).
public enum GridLayouts {

    // MARK: Even grid

    /// Uniform cells in rows and columns; the column count is chosen so cells
    /// roughly match the screen's aspect ratio. Cells fill left-to-right
    /// starting at the top row.
    public static func evenGrid(
        count: Int,
        in bounds: CGRect,
        gap: CGFloat = Treemap.defaultGap
    ) -> [CGRect] {
        guard count > 0 else { return [] }
        let working = bounds.insetBy(dx: gap, dy: gap)
        guard working.width > 0, working.height > 0 else {
            return Array(repeating: .zero, count: count)
        }

        let aspect = Double(working.width / working.height)
        var cols = max(1, Int((Double(count) * aspect).squareRoot().rounded(.up)))
        cols = min(cols, count)
        let rows = Int((Double(count) / Double(cols)).rounded(.up))

        let cellWidth = (working.width - gap * CGFloat(cols - 1)) / CGFloat(cols)
        let cellHeight = (working.height - gap * CGFloat(rows - 1)) / CGFloat(rows)

        return (0..<count).map { i in
            let col = i % cols
            let row = i / cols
            return CGRect(
                x: working.minX + CGFloat(col) * (cellWidth + gap),
                y: working.maxY - cellHeight - CGFloat(row) * (cellHeight + gap),
                width: cellWidth, height: cellHeight)
        }
    }

    // MARK: Columns (masonry)

    /// Fixed-width columns; each note keeps its aspect ratio at the column
    /// width and drops into the currently shortest column. If a column would
    /// overflow the screen, all heights scale down uniformly to fit.
    public static func columns(
        sizes: [CGSize],
        in bounds: CGRect,
        gap: CGFloat = Treemap.defaultGap,
        minColumnWidth: CGFloat = 280
    ) -> [CGRect] {
        guard !sizes.isEmpty else { return [] }
        let working = bounds.insetBy(dx: gap, dy: gap)
        guard working.width > 0, working.height > 0 else {
            return Array(repeating: .zero, count: sizes.count)
        }

        let maxCols = max(1, Int((working.width + gap) / (minColumnWidth + gap)))
        let wanted = Int(Double(sizes.count).squareRoot().rounded(.up))
        let cols = min(max(wanted, 1), min(maxCols, sizes.count))
        let columnWidth = (working.width - gap * CGFloat(cols - 1)) / CGFloat(cols)

        let heights = sizes.map { $0.height * columnWidth / max($0.width, 1) }

        var columnNotes: [[Int]] = Array(repeating: [], count: cols)
        var columnContent = [CGFloat](repeating: 0, count: cols)
        func stackHeight(_ c: Int) -> CGFloat {
            columnContent[c] + gap * CGFloat(columnNotes[c].count)
        }
        for index in heights.indices {
            let target = columnNotes.indices.min {
                (stackHeight($0), $0) < (stackHeight($1), $1)
            }!
            columnNotes[target].append(index)
            columnContent[target] += heights[index]
        }

        var scale: CGFloat = 1
        for c in columnNotes.indices where !columnNotes[c].isEmpty {
            let gaps = gap * CGFloat(columnNotes[c].count - 1)
            let available = max(working.height - gaps, 1)
            scale = min(scale, available / columnContent[c])
        }

        var result = [CGRect](repeating: .zero, count: sizes.count)
        for c in columnNotes.indices {
            let x = working.minX + CGFloat(c) * (columnWidth + gap)
            var y = working.maxY
            for index in columnNotes[c] {
                let height = heights[index] * scale
                y -= height
                result[index] = CGRect(x: x, y: y, width: columnWidth, height: height)
                y -= gap
            }
        }
        return result
    }

    // MARK: Scatter

    /// Random non-overlapping placement. Notes keep their sizes, scaled down
    /// uniformly if they would fill more than `maxFill` of the screen so the
    /// scatter has room to breathe. Pass a seeded generator for reproducible
    /// layouts.
    public static func scatter(
        sizes: [CGSize],
        in bounds: CGRect,
        gap: CGFloat = Treemap.defaultGap,
        maxFill: CGFloat = 0.55,
        using rng: inout some RandomNumberGenerator
    ) -> [CGRect] {
        guard !sizes.isEmpty else { return [] }
        let working = bounds.insetBy(dx: gap, dy: gap)
        guard working.width > 0, working.height > 0 else {
            return Array(repeating: .zero, count: sizes.count)
        }

        let totalArea = sizes.reduce(0) { $0 + $1.width * $1.height }
        var scale = min(1, (working.width * working.height * maxFill / max(totalArea, 1)).squareRoot())
        for size in sizes {
            scale = min(scale,
                        working.width / max(size.width, 1),
                        working.height / max(size.height, 1))
        }

        // Random placement can paint itself into a corner; shrink and retry
        // until a non-overlapping arrangement exists.
        var attempt: CGFloat = scale
        while true {
            let scaled = sizes.map { CGSize(width: $0.width * attempt, height: $0.height * attempt) }
            if let rects = place(scaled, in: working, gap: gap, using: &rng) {
                return rects
            }
            attempt *= 0.85
        }
    }

    private static func place(
        _ sizes: [CGSize],
        in working: CGRect,
        gap: CGFloat,
        using rng: inout some RandomNumberGenerator
    ) -> [CGRect]? {
        // Largest first: big notes are the hardest to fit.
        let order = sizes.indices.sorted {
            sizes[$0].width * sizes[$0].height > sizes[$1].width * sizes[$1].height
        }
        var result = [CGRect](repeating: .zero, count: sizes.count)
        var placed: [CGRect] = []

        for index in order {
            let size = sizes[index]
            let maxX = working.maxX - size.width
            let maxY = working.maxY - size.height
            guard maxX >= working.minX, maxY >= working.minY else { return nil }

            var found: CGRect?
            for _ in 0..<60 {
                let candidate = CGRect(
                    x: CGFloat.random(in: working.minX...maxX, using: &rng),
                    y: CGFloat.random(in: working.minY...maxY, using: &rng),
                    width: size.width, height: size.height)
                if isFree(candidate, among: placed, gap: gap) {
                    found = candidate
                    break
                }
            }
            if found == nil {
                // Deterministic sweep so a crowded screen still resolves.
                let step: CGFloat = 16
                sweep: for y in stride(from: maxY, through: working.minY, by: -step) {
                    for x in stride(from: working.minX, through: maxX, by: step) {
                        let candidate = CGRect(x: x, y: y, width: size.width, height: size.height)
                        if isFree(candidate, among: placed, gap: gap) {
                            found = candidate
                            break sweep
                        }
                    }
                }
            }
            guard let rect = found else { return nil }
            placed.append(rect)
            result[index] = rect
        }
        return result
    }

    private static func isFree(_ rect: CGRect, among placed: [CGRect], gap: CGFloat) -> Bool {
        let grown = rect.insetBy(dx: -gap + 0.5, dy: -gap + 0.5)
        return placed.allSatisfy { !$0.intersects(grown) }
    }
}
