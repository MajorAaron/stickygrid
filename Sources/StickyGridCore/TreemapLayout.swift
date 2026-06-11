import Foundation

/// Pure mosaic-tiling math: divides a screen rect into one tile per note,
/// edge-to-edge with uniform gaps, areas roughly proportional to weights.
public enum Treemap {
    public static let defaultGap: CGFloat = 8
    public static let minNoteSize = CGSize(width: 160, height: 120)

    /// Returns one rect per weight, in the same order as `weights`.
    /// - Parameters:
    ///   - weights: relative area weights (typically each note's current area)
    ///   - bounds: the screen's visible frame to fill
    ///   - gap: points between neighboring tiles and at the outer edge
    ///   - minSize: weight floor — tiny/zero weights are treated as at least this area
    public static func layout(
        weights: [Double],
        in bounds: CGRect,
        gap: CGFloat = Treemap.defaultGap,
        minSize: CGSize = Treemap.minNoteSize
    ) -> [CGRect] {
        guard !weights.isEmpty else { return [] }

        let working = bounds.insetBy(dx: gap, dy: gap)
        guard working.width > 0, working.height > 0 else {
            return Array(repeating: .zero, count: weights.count)
        }

        let minArea = Double(minSize.width * minSize.height)
        let floored = weights.map { max($0, minArea) }

        // Sort heaviest-first so the greedy partition stays balanced, but
        // carry original indices so output order matches input order.
        let items = floored.enumerated().sorted { $0.element > $1.element }

        var result = [CGRect](repeating: .zero, count: weights.count)
        split(items[...], into: working, gap: gap, result: &result)
        return result
    }

    private static func split(
        _ items: ArraySlice<(offset: Int, element: Double)>,
        into rect: CGRect,
        gap: CGFloat,
        result: inout [CGRect]
    ) {
        guard let first = items.first else { return }
        if items.count == 1 {
            result[first.offset] = rect
            return
        }

        // Partition into two contiguous groups with weights as equal as possible.
        let total = items.reduce(0) { $0 + $1.element }
        var bestSplit = items.startIndex + 1
        var bestImbalance = Double.infinity
        var prefix = 0.0
        for i in items.indices.dropLast() {
            prefix += items[i].element
            let imbalance = abs(prefix - (total - prefix))
            if imbalance < bestImbalance {
                bestImbalance = imbalance
                bestSplit = i + 1
            }
        }

        let head = items[items.startIndex..<bestSplit]
        let tail = items[bestSplit...]
        let headSum = head.reduce(0) { $0 + $1.element }
        let fraction = CGFloat(headSum / total)

        // Split along the longer axis, leaving `gap` between the halves.
        if rect.width >= rect.height {
            let usable = max(rect.width - gap, 0)
            let headWidth = usable * fraction
            split(head,
                  into: CGRect(x: rect.minX, y: rect.minY,
                               width: headWidth, height: rect.height),
                  gap: gap, result: &result)
            split(tail,
                  into: CGRect(x: rect.minX + headWidth + gap, y: rect.minY,
                               width: usable - headWidth, height: rect.height),
                  gap: gap, result: &result)
        } else {
            let usable = max(rect.height - gap, 0)
            let headHeight = usable * fraction
            split(head,
                  into: CGRect(x: rect.minX, y: rect.minY,
                               width: rect.width, height: headHeight),
                  gap: gap, result: &result)
            split(tail,
                  into: CGRect(x: rect.minX, y: rect.minY + headHeight + gap,
                               width: rect.width, height: usable - headHeight),
                  gap: gap, result: &result)
        }
    }
}
