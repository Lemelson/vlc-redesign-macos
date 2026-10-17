import CoreGraphics
import Foundation

/// A documented place where a gallery entry intentionally differs from its Figma node (F-06).
///
/// Each deviation names the accepted decision in redesign/docs/DECISIONS.md that makes it
/// intentional. The comparison treats only that area specially and compares everything else
/// with the normal verdict; there is no threshold to loosen. A row the product leaves out is cut
/// out of the reference, so the rows below it are still compared pixel for pixel at the position
/// the product draws them.
public struct FigmaDeviation: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// Figma content the product leaves out. The node's band (its box height plus `gap`, the
        /// layout spacing that disappears with it) is cut out of the reference across the node's
        /// width, and what is below it in that column moves up. The strip this uncovers at the
        /// bottom of the column (content Figma's frame clips) has no reference and is not compared.
        case removed(node: String, gap: CGFloat)
        /// The product draws something else in this area, e.g. a different default value. `rect`
        /// is in the entry's points, in product coordinates (after every `removed` cut).
        case differs(CGRect)
        /// The product draws something else where Figma node `node` is, e.g. a control showing a
        /// different default value. The node's box, grown by `outset` points on every side, is
        /// placed where the product draws it: moved up by every `removed` band above it in its
        /// column. Prefer this to a literal rect, which stays put when rows above it change.
        case differsAt(node: String, outset: CGFloat)
        /// The product draws Figma node `node` unchanged but `offset` points away (e.g. the top bar's
        /// left group after the Mac traffic lights). The node's reference pixels are moved by
        /// `offset` and compared there, pixel for pixel; only the part of its Figma box the moved
        /// box does not cover (what the product draws instead) is left out.
        case moved(node: String, offset: CGSize)
    }

    public let kind: Kind
    /// The decision that makes the difference intentional, e.g. "D035".
    public let decision: String
    /// What differs, in a few words.
    public let reason: String

    /// Figma node `node` (and `gap` points of spacing after it) is not in the product.
    public static func removed(_ node: String, gap: CGFloat = 0, decision: String, _ reason: String) -> FigmaDeviation {
        FigmaDeviation(kind: .removed(node: FigmaIndex.normalizedID(node), gap: gap), decision: decision, reason: reason)
    }

    /// The product draws something else inside `rect` (entry points, product coordinates).
    public static func differs(_ rect: CGRect, decision: String, _ reason: String) -> FigmaDeviation {
        FigmaDeviation(kind: .differs(rect), decision: decision, reason: reason)
    }

    /// The product draws something else where Figma node `node` is (see `Kind.differsAt`).
    public static func differs(node: String, outset: CGFloat = 0, decision: String, _ reason: String) -> FigmaDeviation {
        FigmaDeviation(kind: .differsAt(node: FigmaIndex.normalizedID(node), outset: outset), decision: decision, reason: reason)
    }

    /// The product draws Figma node `node` moved by `offset` points (see `Kind.moved`).
    public static func moved(node: String, by offset: CGSize, decision: String, _ reason: String) -> FigmaDeviation {
        FigmaDeviation(kind: .moved(node: FigmaIndex.normalizedID(node), offset: offset), decision: decision, reason: reason)
    }

    /// The Figma node a deviation is anchored to, if any.
    public var node: String? {
        switch kind {
        case let .removed(node, _), let .differsAt(node, _), let .moved(node, _): node
        case .differs: nil
        }
    }

    /// "removed 3062:12874 (+20 pt) — D035: Pause on interruption".
    public var summary: String {
        switch kind {
        case let .removed(node, gap):
            return "removed \(node)\(gap > 0 ? " (+\(Int(gap)) pt)" : "") — \(decision): \(reason)"
        case let .differs(rect):
            return "differs \(Int(rect.minX)),\(Int(rect.minY)) \(Int(rect.width))×\(Int(rect.height)) pt — \(decision): \(reason)"
        case let .differsAt(node, outset):
            return "differs at \(node)\(outset > 0 ? " (±\(Int(outset)) pt)" : "") — \(decision): \(reason)"
        case let .moved(node, offset):
            return "moved \(node) by \(Int(offset.width.rounded())),\(Int(offset.height.rounded())) pt — \(decision): \(reason)"
        }
    }
}

/// A render and its Figma reference with the entry's documented deviations applied.
public struct DeviationAdjustedImages: Sendable {
    public let render: CGImage
    public let reference: CGImage
    /// Pixels left out of the comparison (cleared in both images): `differs` areas and the
    /// strips uncovered by `removed` cuts.
    public let excludedPixels: Int
    public let totalPixels: Int
    public var excludedFraction: Double { Double(excludedPixels) / max(1, Double(totalPixels)) }
}

extension FigmaIndex {
    /// Applies `deviations` to `render` and `reference` (see `FigmaDeviation`). `removed` nodes
    /// must be descendants of the reference node; they are cut bottom-up, so every node keeps its own
    /// Figma position while the cuts above it are made.
    public func applying(
        _ deviations: [FigmaDeviation], render: CGImage, reference: FigmaReference
    ) throws -> DeviationAdjustedImages {
        let width = max(render.width, reference.image.width), height = max(render.height, reference.image.height)
        var a = GalleryImageIO.rgba(render, width: width, height: height)
        var b = GalleryImageIO.rgba(reference.image, width: width, height: height)
        var excluded = [Bool](repeating: false, count: width * height)
        let scale = reference.scale
        let root = reference.node.boundingBox

        // A node's box in the reference's points. Rows below the frame's clip (Figma frames clip
        // scrolled content) are still descendants.
        func box(of id: String) throws -> CGRect {
            guard let node = self.node(id) else { throw GalleryToolingError("deviation: unknown Figma node \(id)") }
            guard ancestry(of: node).contains(where: { $0.id == reference.node.id }) else {
                throw GalleryToolingError("deviation: node \(id) is not inside \(reference.node.id)")
            }
            return node.boundingBox.offsetBy(dx: -root.minX, dy: -root.minY)
        }

        var cuts: [(rect: CGRect, band: Int)] = []
        for deviation in deviations {
            guard case let .removed(id, gap) = deviation.kind else { continue }
            let rect = try box(of: id)
            cuts.append((rect, Int(((rect.height + gap) * scale).rounded())))
        }
        var differing: [CGRect] = []
        // Moves read the reference before any of them writes, so overlapping moves do not chain.
        let original = b
        for deviation in deviations {
            guard case let .moved(id, offset) = deviation.kind else { continue }
            let rect = try box(of: id)
            let x0 = max(0, Int((rect.minX * scale).rounded())), x1 = min(width, Int((rect.maxX * scale).rounded()))
            let y0 = max(0, Int((rect.minY * scale).rounded())), y1 = min(height, Int((rect.maxY * scale).rounded()))
            let dx = Int((offset.width * scale).rounded()), dy = Int((offset.height * scale).rounded())
            guard x1 > x0, y1 > y0 else { continue }
            let moved = (x: (x0 + dx)..<(x1 + dx), y: (y0 + dy)..<(y1 + dy))
            // The vacated part of the Figma box: the product draws something else there.
            for y in y0..<y1 { for x in x0..<x1 where !(moved.x.contains(x) && moved.y.contains(y)) { excluded[y * width + x] = true } }
            for y in y0..<y1 {
                for x in x0..<x1 {
                    let tx = x + dx, ty = y + dy
                    guard tx >= 0, tx < width, ty >= 0, ty < height else { continue }
                    let from = y * width + x, to = ty * width + tx
                    for c in 0..<4 { b[to * 4 + c] = original[from * 4 + c] }
                    excluded[to] = false
                }
            }
        }
        for deviation in deviations {
            switch deviation.kind {
            case .removed, .moved: continue
            case let .differs(rect): differing.append(rect)
            case let .differsAt(id, outset):
                let rect = try box(of: id)
                // Where the product draws it: every cut above it in its column moves it up.
                let shift = cuts.filter { $0.rect.minY < rect.minY && $0.rect.minX < rect.maxX && rect.minX < $0.rect.maxX }
                    .reduce(0) { $0 + CGFloat($1.band) / scale }
                differing.append(rect.offsetBy(dx: 0, dy: -shift).insetBy(dx: -outset, dy: -outset))
            }
        }
        for cut in cuts.sorted(by: { $0.rect.minY > $1.rect.minY }) {
            let x0 = max(0, Int((cut.rect.minX * scale).rounded())), x1 = min(width, Int((cut.rect.maxX * scale).rounded()))
            let y0 = max(0, Int((cut.rect.minY * scale).rounded()))
            guard x1 > x0, cut.band > 0 else { continue }
            var y = y0
            while y < height {
                let source = y + cut.band
                for x in x0..<x1 {
                    let to = y * width + x
                    if source < height {
                        let from = source * width + x
                        for c in 0..<4 { b[to * 4 + c] = b[from * 4 + c] }
                        excluded[to] = excluded[from]
                    } else {
                        excluded[to] = true
                    }
                }
                y += 1
            }
        }
        for rect in differing {
            let x0 = max(0, Int((rect.minX * scale).rounded(.down))), x1 = min(width, Int((rect.maxX * scale).rounded(.up)))
            let y0 = max(0, Int((rect.minY * scale).rounded(.down))), y1 = min(height, Int((rect.maxY * scale).rounded(.up)))
            guard x1 > x0, y1 > y0 else { continue }
            for y in y0..<y1 { for x in x0..<x1 { excluded[y * width + x] = true } }
        }
        var count = 0
        for index in excluded.indices where excluded[index] {
            count += 1
            for c in 0..<4 { a[index * 4 + c] = 0; b[index * 4 + c] = 0 }
        }
        guard let adjustedA = GalleryImageIO.image(fromRGBA: a, width: width, height: height),
              let adjustedB = GalleryImageIO.image(fromRGBA: b, width: width, height: height)
        else { throw GalleryToolingError("deviation: cannot build the adjusted images") }
        return DeviationAdjustedImages(render: adjustedA, reference: adjustedB, excludedPixels: count, totalPixels: width * height)
    }
}
