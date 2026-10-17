import AppKit
import MXRGalleryCatalog
import SwiftUI

/// Entry details, the Figma node it reproduces, and the measurement against it.
struct GalleryInspector: View {
    let model: GalleryModel

    var body: some View {
        if let entry = model.selectedEntry {
            Form {
                Section("Entry") {
                    LabeledContent("Id") { Text(entry.id).textSelection(.enabled) }
                    LabeledContent("Title", value: entry.title)
                    LabeledContent("Kind", value: entry.kind.title)
                    LabeledContent("Size", value: "\(StatusText.number(entry.size.width)) × \(StatusText.number(entry.size.height)) pt")
                    LabeledContent("Scheme", value: entry.colorScheme == .dark ? "Dark" : "Light")
                    LabeledContent("Background", value: entry.background == nil ? "Transparent" : "Set")
                    LabeledContent("Renderer", value: entry.renderEngine.rawValue)
                    LabeledContent("Backdrop", value: entry.backdropMode == .isolatedTint ? "Isolated tint; blur unverified" : "Live material; inspect native window")
                    if !entry.screens.isEmpty {
                        LabeledContent("Screens", value: entry.screens.joined(separator: ", "))
                    }
                    if !entry.notes.isEmpty {
                        Text(entry.notes).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
                FigmaSection(model: model, entry: entry)
                if entry.figmaNode != nil { MeasurementSection(model: model, entry: entry) }
            }
            .formStyle(.grouped)
        } else {
            ContentUnavailableView("No Selection", systemImage: "info.circle")
        }
    }
}

private struct FigmaSection: View {
    let model: GalleryModel
    let entry: GalleryEntry

    var body: some View {
        Section("Figma") {
            if let nodeID = entry.figmaNode {
                LabeledContent("Node") { Text(nodeID).textSelection(.enabled) }
                switch model.reference {
                case .loaded(let crop, _):
                    LabeledContent("Name", value: "\(crop.node.name) (\(crop.node.type))")
                    LabeledContent("Node box", value: "\(StatusText.number(crop.node.boundingBox.width)) × \(StatusText.number(crop.node.boundingBox.height)) pt")
                    if crop.node.boundingBox.size != entry.size {
                        Label("Entry size differs from the node box", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                    LabeledContent("Frame", value: "\(crop.frame.name) · \(crop.frame.id)")
                    LabeledContent("Render") { Text(crop.frame.renderFile).textSelection(.enabled) }
                    LabeledContent(
                        "Crop",
                        value: "x \(StatusText.number(crop.pixelRect.minX)) y \(StatusText.number(crop.pixelRect.minY)) · "
                            + "\(StatusText.number(crop.pixelRect.width))×\(StatusText.number(crop.pixelRect.height)) px"
                    )
                    ForEach(crop.warnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    }
                    Button("Reveal Render in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([crop.renderURL])
                    }
                case .loading:
                    ProgressView().controlSize(.small)
                case .none(let message), .failed(let message):
                    Text(message).foregroundStyle(.secondary)
                }
            } else {
                Text("No Figma node. Set `figmaNode` on the entry to compare it with the design.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct MeasurementSection: View {
    let model: GalleryModel
    let entry: GalleryEntry

    var body: some View {
        Section("Compare") {
            if model.isMeasuring {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Measuring…").foregroundStyle(.secondary)
                }
            }
            if let error = model.measureError {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
            if let measurement = model.measurement, measurement.entryID == entry.id {
                let comparison = measurement.comparison
                if !model.measurementIsCurrent {
                    Label("Measured with a different scheme or accent", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Button("Measure Again") { model.measure() }
                }
                VerdictBadge(comparison: comparison)
                Text(comparison.reason).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                LabeledContent("Sizes", value: "\(Int(comparison.sizeA.width))×\(Int(comparison.sizeA.height)) vs \(Int(comparison.sizeB.width))×\(Int(comparison.sizeB.height)) px")
                LabeledContent("Mean |Δ|", value: String(format: "%.2f / 255", comparison.meanAbsoluteDifference))
                LabeledContent("Strict Δ > \(comparison.threshold)", value: String(format: "%.3f %% (%d px)", comparison.differingFraction * 100, comparison.differingPixels))
                LabeledContent("Structural", value: String(format: "%.3f %% (%d px)", comparison.structuralFraction * 100, comparison.structuralPixels))
                LabeledContent("Flat color", value: String(format: "%.3f %% (%d px)", comparison.flatColorFraction * 100, comparison.flatColorPixels))
                if let shift = comparison.bestShift {
                    LabeledContent("Offset", value: "matches better moved \(comparison.points(of: shift))")
                }
                if let region = comparison.largestRegion {
                    LabeledContent("Largest region", value: Self.points(region.rect, scale: comparison.scale))
                    if let colors = region.flatColors {
                        Text(colors.summary).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
                if let strict = comparison.largestStrictRegion {
                    LabeledContent("Largest Δ > \(comparison.threshold) area", value: Self.points(strict.rect, scale: comparison.scale))
                }
                HStack {
                    Button("Heat Map") { model.mode = .heatmap }
                    Button("Save Files") { model.saveComparison() }
                        .help("Writes render, ref, comparison images and report.txt (measures again if out of date)")
                }
                if let directory = model.lastSavedDirectory {
                    Button("Reveal Saved Files") { NSWorkspace.shared.activateFileViewerSelecting([directory]) }
                }
            } else if !model.isMeasuring {
                Button("Measure Against Figma") { model.measure() }
                Text("Renders the entry like `mxr-snapshot check` and compares it with the crop.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if let command = model.checkCommand {
                LabeledContent("CLI") { Text(command).font(.caption.monospaced()).textSelection(.enabled) }
                Button("Copy Command") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                }
            }
        }
    }

    /// A pixel rectangle in points: "12,4 · 30×8 pt".
    private static func points(_ rect: CGRect, scale: CGFloat) -> String {
        String(format: "%.0f,%.0f · %.0f×%.0f pt", rect.minX / scale, rect.minY / scale, rect.width / scale, rect.height / scale)
    }
}

enum StatusText {
    static func number(_ value: CGFloat) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.2f", value)
    }
}
