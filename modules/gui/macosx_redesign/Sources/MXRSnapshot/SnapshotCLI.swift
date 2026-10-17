import AppKit
import Foundation
import MXRGalleryCatalog
import SwiftUI

/// `mxr-snapshot`: renders gallery entries to PNG, crops Figma references and compares them.
/// Usage: `swift run mxr-snapshot help` (from modules/gui/macosx_redesign).
@main
enum MXRSnapshotMain {
    @MainActor
    static func main() {
        var arguments = Array(CommandLine.arguments.dropFirst())
        // Must happen before any text is drawn; see GalleryRenderer.matchFigmaTextRasterization().
        if let index = arguments.firstIndex(of: "--font-smoothing") {
            arguments.remove(at: index)
        } else {
            GalleryRenderer.matchFigmaTextRasterization()
        }
        exit(SnapshotCLI().run(arguments))
    }
}

/// Exit codes of `mxr-snapshot`.
enum ExitCode {
    static let ok: Int32 = 0
    static let failVerdict: Int32 = 1
    static let error: Int32 = 2
    static let usage: Int32 = 64
}

@MainActor
struct SnapshotCLI {
    static let usage = """
        mxr-snapshot: render gallery entries and compare them with the Figma renders

        USAGE (from modules/gui/macosx_redesign)
          swift run mxr-snapshot <command> [options]

        COMMANDS
          list [--kind C|D|S|X] [--json]
              Gallery entries with size, Figma node and screens.
          render --id <entry> [--scale 2] [--scheme dark|light] [--accent <swatch>]
                 [--engine image|hosting|shipping-window] [--out file.png]
              Renders an entry at its size × scale (transparent where it draws nothing).
          ref --node <figma-node> [--scale 2] [--bounds box|render] [--out ref.png]
              Crops a Figma node out of its top-level frame render.
          compare <a.png> <b.png> [--out <dir>] [--scale 2] [--threshold 24]
                  [--backdrop checker|black|white]
              Writes side-by-side.png, overlay-50.png, diff-heatmap.png; prints metrics.
          check (--id <entry> | --all) [--out-dir <dir>] [--scale 2] [--scheme dark|light]
                [--accent <swatch>] [--engine image|hosting|shipping-window] [--threshold 24]
                [--ignore-deviations]
              render + ref (from the entry's figmaNode) + compare, with a verdict. An entry's
              documented deviations (GalleryEntry.figmaDeviations, each citing a decision) are
              applied first: rows the product leaves out are cut from the reference and areas
              that intentionally differ are left out; the report lists them. render.png and
              ref.png stay unmodified. --ignore-deviations compares the raw images.
          node <figma-node>
              A node's frame, render file, crop rectangle, ancestry and children.
          find <text> [--frame <figma-node>] [--type TEXT|FRAME|INSTANCE|…] [--limit 40]
              Searches node names and text content.

        Text is rasterized like Figma (no Core Text font smoothing); add --font-smoothing
        to any command to render with the macOS default instead.
        Node ids may be written 848:1711 or 848-1711. Output defaults to
        <package>/.build/mxr-tools/ (git-ignored). Verdicts: PASS (no visible
        difference), REVIEW (small differences: inspect diff-heatmap.png), FAIL.
        Exit codes: 0 ok / PASS / REVIEW, 1 FAIL, 2 error, 64 usage.
        """

    func run(_ arguments: [String]) -> Int32 {
        guard let command = arguments.first, !["help", "-h", "--help"].contains(command) else {
            print(Self.usage)
            return arguments.isEmpty ? ExitCode.usage : ExitCode.ok
        }
        do {
            let options = try Options(Array(arguments.dropFirst()))
            switch command {
            case "list": return try list(options)
            case "render": return try render(options)
            case "ref": return try ref(options)
            case "compare": return try compare(options)
            case "check": return try check(options)
            case "node": return try node(options)
            case "find": return try find(options)
            default:
                printError("unknown command '\(command)'\n\n\(Self.usage)")
                return ExitCode.usage
            }
        } catch let error as UsageError {
            printError("\(error.message)\nRun `mxr-snapshot help` for usage.")
            return ExitCode.usage
        } catch {
            printError("error: \(error.localizedDescription)")
            return ExitCode.error
        }
    }

    // MARK: Commands

    private func list(_ options: Options) throws -> Int32 {
        try options.allow(values: ["kind"], flags: ["json"])
        GalleryCatalog.bootstrap()
        var entries = GalleryCatalog.allEntries()
        if let kind = options.value("kind") {
            entries = entries.filter { $0.kind.rawValue.caseInsensitiveCompare(kind) == .orderedSame }
        }
        if options.flag("json") {
            let rows: [[String: Any]] = entries.map { entry in
                [
                    "id": entry.id, "title": entry.title, "width": entry.size.width, "height": entry.size.height,
                    "figmaNode": entry.figmaNode ?? NSNull(), "screens": entry.screens,
                    "colorScheme": entry.colorScheme == .dark ? "dark" : "light",
                    "renderEngine": entry.renderEngine.rawValue, "backdropMode": entry.backdropMode.rawValue, "notes": entry.notes,
                ]
            }
            let data = try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])
            print(String(decoding: data, as: UTF8.self))
            return ExitCode.ok
        }
        let idWidth = max(4, entries.map(\.id.count).max() ?? 0)
        print("id".padded(idWidth) + "  size        figma        screens")
        for entry in entries {
            let size = "\(format(entry.size.width))×\(format(entry.size.height))"
            print(
                entry.id.padded(idWidth) + "  "
                    + size.padded(10) + "  "
                    + (entry.figmaNode ?? "—").padded(11) + "  "
                    + entry.screens.joined(separator: ",")
            )
        }
        print("\(entries.count) entries")
        return ExitCode.ok
    }

    private func render(_ options: Options) throws -> Int32 {
        try options.allow(values: ["id", "scale", "scheme", "accent", "engine", "out"])
        GalleryCatalog.bootstrap()
        let entry = try requireEntry(options)
        let scale = try options.double("scale", default: 2)
        let image = try GalleryRenderer.render(
            entry, scale: scale, environment: try environment(options, entry: entry), engine: try engine(options)
        )
        let paths = try GalleryPaths.locate()
        let out = options.url("out") ?? paths.snapshotDirectory(for: entry).appending(path: "render.png")
        try GalleryImageIO.writePNG(image, to: out)
        print("rendered \(entry.id) at \(format(scale))× → \(image.width)×\(image.height) px\n\(out.path)")
        return ExitCode.ok
    }

    private func ref(_ options: Options) throws -> Int32 {
        try options.allow(values: ["node", "scale", "bounds", "out"])
        guard let nodeID = options.value("node") ?? options.positional.first else {
            throw UsageError("ref needs --node <figma-node>")
        }
        let scale = try options.double("scale", default: 2)
        let bounds = try options.choice("bounds", default: FigmaCropBounds.boundingBox)
        let index = try FigmaIndex.shared()
        let reference = try index.reference(for: nodeID, scale: scale, bounds: bounds)
        let fileName = "\(reference.node.id.replacingOccurrences(of: ":", with: "-"))@\(format(scale))x.png"
        let out = options.url("out") ?? index.paths.toolsDirectory.appending(path: "refs/\(fileName)")
        try GalleryImageIO.writePNG(reference.image, to: out)
        print(describe(reference))
        print("→ \(reference.image.width)×\(reference.image.height) px\n\(out.path)")
        return ExitCode.ok
    }

    private func compare(_ options: Options) throws -> Int32 {
        try options.allow(values: ["out", "scale", "threshold", "backdrop"])
        guard options.positional.count == 2 else { throw UsageError("compare needs two image paths") }
        let urlA = URL(fileURLWithPath: options.positional[0])
        let urlB = URL(fileURLWithPath: options.positional[1])
        let a = try GalleryImageIO.read(urlA)
        let b = try GalleryImageIO.read(urlB)
        let out = try options.url("out") ?? GalleryPaths.locate().toolsDirectory.appending(
            path: "compare/\(urlA.deletingPathExtension().lastPathComponent)-vs-\(urlB.deletingPathExtension().lastPathComponent)"
        )
        let (comparison, images) = ImageComparator.compare(
            a, b, scale: try options.double("scale", default: 2),
            threshold: try options.int("threshold", default: ImageComparator.defaultThreshold),
            backdrop: try options.choice("backdrop", default: ComparisonBackdrop.checker)
        )
        let written = try images?.write(to: out) ?? []
        print("a           \(urlA.path)\nb           \(urlB.path)")
        print(comparison.report())
        print("files       \(out.path)/{\(written.map(\.lastPathComponent).joined(separator: ","))}")
        return comparison.verdict == .fail ? ExitCode.failVerdict : ExitCode.ok
    }

    private func check(_ options: Options) throws -> Int32 {
        try options.allow(values: ["id", "out-dir", "scale", "scheme", "accent", "engine", "threshold"], flags: ["all", "ignore-deviations"])
        GalleryCatalog.bootstrap()
        let paths = try GalleryPaths.locate()
        let index = try FigmaIndex.shared()
        let scale = try options.double("scale", default: 2)
        let threshold = try options.int("threshold", default: ImageComparator.defaultThreshold)

        if options.flag("all") {
            if options.value("id") != nil { throw UsageError("use either --id or --all") }
            let root = options.url("out-dir") ?? paths.toolsDirectory.appending(path: "snapshots")
            var counts: [ImageComparison.Verdict: Int] = [:]
            var errors = 0
            let entries = GalleryCatalog.allEntries()
            let idWidth = max(4, entries.map(\.id.count).max() ?? 0)
            for entry in entries {
                let label = entry.id.padded(idWidth)
                guard entry.figmaNode != nil else {
                    print("skip    \(label)  (no figmaNode)")
                    continue
                }
                do {
                    let result = try checkEntry(
                        entry, options: options, index: index, scale: scale, threshold: threshold,
                        directory: root.appending(path: entry.fileSafeID)
                    )
                    counts[result.verdict, default: 0] += 1
                    print(String(
                        format: "%@  %@  strict %6.2f %%  structural %6.2f %%  flat color %6.2f %%  %@",
                        result.verdict.rawValue.padded(6), label, result.differingFraction * 100,
                        result.structuralFraction * 100, result.flatColorFraction * 100,
                        result.sizeMatches ? "" : "size mismatch"
                    ))
                } catch {
                    errors += 1
                    print("ERROR   \(label)  \(error.localizedDescription)")
                }
            }
            print("PASS \(counts[.pass] ?? 0) · REVIEW \(counts[.review] ?? 0) · FAIL \(counts[.fail] ?? 0) · errors \(errors)")
            print("outputs in \(root.path)/<entry>/")
            return (counts[.fail] ?? 0) > 0 ? ExitCode.failVerdict : (errors > 0 ? ExitCode.error : ExitCode.ok)
        }

        let entry = try requireEntry(options)
        guard entry.figmaNode != nil else {
            throw GalleryToolingError("\(entry.id) has no figmaNode; use `render` and compare by eye, or add the node id")
        }
        let directory = options.url("out-dir") ?? paths.snapshotDirectory(for: entry)
        let comparison = try checkEntry(
            entry, options: options, index: index, scale: scale, threshold: threshold, directory: directory, verbose: true
        )
        return comparison.verdict == .fail ? ExitCode.failVerdict : ExitCode.ok
    }

    private func checkEntry(
        _ entry: GalleryEntry, options: Options, index: FigmaIndex, scale: CGFloat, threshold: Int,
        directory: URL, verbose: Bool = false
    ) throws -> ImageComparison {
        guard let nodeID = entry.figmaNode else { throw GalleryToolingError("\(entry.id) has no figmaNode") }
        let environment = try environment(options, entry: entry)
        let render = try GalleryRenderer.render(entry, scale: scale, environment: environment, engine: try engine(options))
        let reference = try index.reference(for: nodeID, scale: scale)
        try GalleryImageIO.writePNG(render, to: directory.appending(path: "render.png"))
        try GalleryImageIO.writePNG(reference.image, to: directory.appending(path: "ref.png"))
        let deviations = options.flag("ignore-deviations") ? [] : entry.figmaDeviations
        var compared = (render: render, reference: reference.image)
        var excludedFraction = 0.0
        if !deviations.isEmpty {
            let adjusted = try index.applying(deviations, render: render, reference: reference)
            compared = (adjusted.render, adjusted.reference)
            excludedFraction = adjusted.excludedFraction
        }
        let (comparison, images) = ImageComparator.compare(compared.render, compared.reference, scale: scale, threshold: threshold)
        try images?.write(to: directory)

        var report = """
            entry       \(entry.id) (\(format(entry.size.width))×\(format(entry.size.height)) pt, \
            \(environment.colorScheme == .dark ? "dark" : "light")\(environment.accent.map { ", accent \($0)" } ?? ""))
            \(describe(reference))
            host        \(GalleryRenderer.effectiveEngine(for: entry, override: try engine(options)).rawValue) — offscreen fixture; not an installed-app capture
            backdrop    \(entry.backdropMode.rawValue) — \(entry.backdropMode == .isolatedTint
                ? "isolated tint; native blur is not evaluated"
                : "live material; offscreen capture does not verify native blur")

            """
        if entry.size != reference.node.boundingBox.size {
            report += "note        entry size \(format(entry.size.width))×\(format(entry.size.height)) ≠ node box "
                + "\(format(reference.node.boundingBox.width))×\(format(reference.node.boundingBox.height))\n"
        }
        for (number, deviation) in deviations.enumerated() {
            report += (number == 0 ? "deviations  " : "            ") + deviation.summary + "\n"
        }
        if !deviations.isEmpty {
            report += String(format: "            %.2f %% of the canvas is not compared; the verdict covers the rest\n", excludedFraction * 100)
        } else if options.flag("ignore-deviations") && !entry.figmaDeviations.isEmpty {
            report += "deviations  \(entry.figmaDeviations.count) documented, ignored (--ignore-deviations)\n"
        }
        report += comparison.report()
        report += "\nfiles       \(directory.path)/{render,ref,side-by-side,overlay-50,diff-heatmap}.png"
        try (report + "\n").write(to: directory.appending(path: "report.txt"), atomically: true, encoding: .utf8)
        if verbose { print(report) }
        return comparison
    }

    private func node(_ options: Options) throws -> Int32 {
        try options.allow(values: [])
        guard let nodeID = options.positional.first else { throw UsageError("node needs a Figma node id") }
        let index = try FigmaIndex.shared()
        guard let node = index.node(nodeID) else { throw GalleryToolingError("unknown Figma node \(nodeID)") }
        let reference = try? index.reference(for: node.id)
        print(reference.map(describe) ?? "node        \(node.id) \(node.type) \"\(node.name)\"")
        if !node.text.isEmpty { print("text        \(node.text)") }
        print("path        " + index.ancestry(of: node).map { "\($0.name) [\($0.id)]" }.joined(separator: " › "))
        let children = index.children(of: node.id)
        if !children.isEmpty {
            print("children    \(children.count)")
            for child in children.prefix(60) {
                let box = child.boundingBox
                print("  \(child.id.padded(14)) \(child.type.padded(10)) "
                    + "\(format(box.width))×\(format(box.height)) at \(format(box.minX - node.boundingBox.minX)),\(format(box.minY - node.boundingBox.minY))  "
                    + "\(child.name)\(child.text.isEmpty ? "" : " \"\(child.text.prefix(40))\"")\(child.visible ? "" : " (hidden)")")
            }
            if children.count > 60 { print("  … \(children.count - 60) more") }
        }
        return ExitCode.ok
    }

    private func find(_ options: Options) throws -> Int32 {
        try options.allow(values: ["frame", "type", "limit"])
        let query = options.positional.joined(separator: " ")
        let index = try FigmaIndex.shared()
        let limit = try options.int("limit", default: 40)
        let results = index.search(query, inFrame: options.value("frame"), type: options.value("type"), limit: limit)
        for node in results {
            let frame = index.frames[node.frameID]
            let box = node.boundingBox
            print("\(node.id.padded(16)) \(node.type.padded(10)) "
                + "\(format(box.width))×\(format(box.height))".padded(12)
                + " \(node.name)\(node.text.isEmpty || node.text == node.name ? "" : " \"\(node.text.prefix(50))\"")"
                + "  ⟨\(frame?.name ?? node.frameID) \(node.frameID)⟩")
        }
        print("\(results.count) node(s)\(results.count == limit ? " (limit reached; use --limit)" : "")")
        return ExitCode.ok
    }

    // MARK: Helpers

    private func requireEntry(_ options: Options) throws -> GalleryEntry {
        guard let id = options.value("id") else { throw UsageError("missing --id <entry>") }
        if let entry = GalleryCatalog.entry(id: id) { return entry }
        let near = GalleryCatalog.allEntries().map(\.id).filter {
            $0.localizedCaseInsensitiveContains(id) || id.localizedCaseInsensitiveContains($0)
        }
        throw GalleryToolingError("no gallery entry '\(id)'" + (near.isEmpty ? "; see `mxr-snapshot list`" : ". Did you mean: \(near.prefix(8).joined(separator: ", "))"))
    }

    private func environment(_ options: Options, entry: GalleryEntry) throws -> GalleryEnvironment {
        var environment = GalleryEnvironment(colorScheme: entry.colorScheme)
        switch options.value("scheme")?.lowercased() {
        case nil: break
        case "dark": environment.colorScheme = .dark
        case "light": environment.colorScheme = .light
        case let other?: throw UsageError("--scheme must be dark or light, not \(other)")
        }
        if let accent = options.value("accent") {
            let known = GalleryCatalog.theme().accents.map(\.id)
            guard known.isEmpty || known.contains(accent) else {
                throw UsageError("unknown accent '\(accent)'; known: \(known.joined(separator: ", "))")
            }
            environment.accent = accent
        }
        return environment
    }

    private func engine(_ options: Options) throws -> GalleryRenderEngine? {
        guard options.value("engine") != nil else { return nil }
        return try options.choice("engine", default: GalleryRenderEngine.imageRenderer)
    }

    private func describe(_ reference: FigmaReference) -> String {
        let node = reference.node
        let box = node.boundingBox
        let rect = reference.pixelRect
        var lines = [
            "node        \(node.id) \(node.type) \"\(node.name)\" \(format(box.width))×\(format(box.height)) pt"
                + "\(node.visible ? "" : " (hidden)")",
            "frame       \(reference.frame.id) \"\(reference.frame.name)\" → renders/\(reference.frame.renderFile)"
                + String(format: " (%.2f× of render bounds)", reference.renderScale.width),
            "crop        x \(format(rect.minX)) y \(format(rect.minY)) \(format(rect.width))×\(format(rect.height)) px of the render"
                + (reference.isSubpixelShifted ? " (starts between pixels; resampled)" : ""),
        ]
        lines += reference.warnings.map { "warning     \($0)" }
        return lines.joined(separator: "\n")
    }

    private func format(_ value: CGFloat) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.2f", value)
    }

    private func printError(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}

/// A command-line usage mistake (exit code 64).
struct UsageError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}

/// `--name value`, `--name=value`, boolean `--flag`s and positional arguments.
struct Options {
    private(set) var positional: [String] = []
    private var values: [String: String] = [:]
    private var flags: Set<String> = []
    private static let booleanFlags: Set<String> = ["all", "json", "ignore-deviations"]

    init(_ arguments: [String]) throws {
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if argument.hasPrefix("--") {
                let name = String(argument.dropFirst(2))
                if let equals = name.firstIndex(of: "=") {
                    values[String(name[..<equals])] = String(name[name.index(after: equals)...])
                } else if Self.booleanFlags.contains(name) {
                    flags.insert(name)
                } else {
                    guard index + 1 < arguments.count else { throw UsageError("--\(name) needs a value") }
                    values[name] = arguments[index + 1]
                    index += 1
                }
            } else {
                positional.append(argument)
            }
            index += 1
        }
    }

    /// Rejects options the command does not take.
    func allow(values allowedValues: Set<String>, flags allowedFlags: Set<String> = []) throws {
        let unknown = Set(values.keys).subtracting(allowedValues).union(flags.subtracting(allowedFlags))
        if let first = unknown.sorted().first { throw UsageError("unknown option --\(first)") }
    }

    func value(_ name: String) -> String? { values[name] }
    func flag(_ name: String) -> Bool { flags.contains(name) }

    func url(_ name: String) -> URL? {
        values[name].map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
    }

    func double(_ name: String, default fallback: Double) throws -> CGFloat {
        guard let raw = values[name] else { return fallback }
        guard let value = Double(raw), value > 0 else { throw UsageError("--\(name) must be a positive number") }
        return value
    }

    func int(_ name: String, default fallback: Int) throws -> Int {
        guard let raw = values[name] else { return fallback }
        guard let value = Int(raw), value >= 0 else { throw UsageError("--\(name) must be a non-negative integer") }
        return value
    }

    func choice<T: RawRepresentable & CaseIterable>(_ name: String, default fallback: T) throws -> T where T.RawValue == String {
        guard let raw = values[name] else { return fallback }
        guard let value = T(rawValue: raw) else {
            throw UsageError("--\(name) must be one of \(T.allCases.map(\.rawValue).joined(separator: ", "))")
        }
        return value
    }
}

extension String {
    /// Left-aligned in a column of `width` characters; never truncates.
    func padded(_ width: Int) -> String {
        count >= width ? self : self + String(repeating: " ", count: width - count)
    }
}
