import CoreGraphics
import Foundation
import MXRBridgeAPI
import ImageIO
import MXRCore

/// Library artwork, seek previews and waveforms through the bridge's `thumbnails` service.
///
/// Every frame request carries a token; cancelling the Swift task sends `cancel` with that token,
/// which reaches `vlc_preparser_Cancel` for the running or queued engine request (ARC-03/BB-01).
/// Frames arrive as decoded `CGImage`s scaled to the requested size (no PNG round trip).
@MainActor
final class VLCThumbnailBackend: ExactFrameThumbnailBackend {
    private let transport: any VLCServiceTransport
    /// Least-recently-used artwork cache: a long folder scroll evicts the oldest pictures one by
    /// one instead of dropping everything and making every visible row flicker (L16).
    private var cache: [String: CGImage] = [:]
    private var recency: [String] = []
    private let cacheLimit = 400
    private var nextToken = 0
    init(transport: any VLCServiceTransport) { self.transport = transport }

    /// Artwork is cached per media, artwork file and size bucket (next power of two of the larger
    /// side), so a 64 px list thumbnail never stands in for a 632 px grid card (LM3), and a library
    /// thumbnail that arrives later replaces an earlier first-frame image.
    private static func artworkKey(_ media: MediaItem, _ size: CGSize) -> String {
        let side = max(16, Int(max(size.width, size.height).rounded(.up)))
        let bucket = 1 << Int(ceil(log2(Double(side))))
        return "\(media.id)|\(media.artworkURL?.absoluteString ?? "")|\(bucket)"
    }

    /// The exact size when cached; otherwise a smaller cached image as a placeholder until
    /// ``artwork(for:maxPixelSize:)`` delivers the sharp one.
    func cachedArtwork(for media: MediaItem, maxPixelSize: CGSize) -> CGImage? {
        if let exact = cache[Self.artworkKey(media, maxPixelSize)] { touch(Self.artworkKey(media, maxPixelSize)); return exact }
        let prefix = "\(media.id)|\(media.artworkURL?.absoluteString ?? "")|"
        return cache.first { $0.key.hasPrefix(prefix) }?.value
    }

    func artwork(for media: MediaItem, maxPixelSize: CGSize) async -> CGImage? {
        let key = Self.artworkKey(media, maxPixelSize)
        if let cached = cache[key] { touch(key); return cached }
        let image = await requestImage(.artwork, media: media, time: nil, exact: false, size: maxPixelSize)
        if let image, !Task.isCancelled { store(image, for: key) }
        return image
    }

    private func touch(_ key: String) {
        if let index = recency.lastIndex(of: key) { recency.remove(at: index) }
        recency.append(key)
    }

    private func store(_ image: CGImage, for key: String) {
        cache[key] = image
        touch(key)
        while cache.count > cacheLimit, let oldest = recency.first {
            recency.removeFirst()
            cache[oldest] = nil
        }
    }

    func seekPreview(for media: MediaItem, at time: MediaTime, maxPixelSize: CGSize) async -> CGImage? {
        await requestImage(.seekPreview, media: media, time: time, exact: false, size: maxPixelSize)
    }

    func seekPreview(for media: MediaItem, at time: MediaTime, exact: Bool, maxPixelSize: CGSize) async -> CGImage? {
        await requestImage(.seekPreview, media: media, time: time, exact: exact, size: maxPixelSize)
    }

    private func requestImage(_ request: MXRBridgeRequest, media: MediaItem, time: MediaTime?, exact: Bool, size: CGSize) async -> CGImage? {
        guard !Task.isCancelled else { return nil }
        nextToken += 1
        let token = nextToken
        var input: [String: Any] = ["url": media.mrl]
        if let artwork = media.artworkURL { input["artworkURL"] = artwork.absoluteString }
        var args: [String: Any] = ["media": input, "width": Int(size.width), "height": Int(size.height),
                                   "token": token, "exact": exact]
        if let time { args["time"] = time.microseconds }
        do {
            let reply = try await withTaskCancellationHandler {
                try await transport.request(request, service: .thumbnails, arguments: args)
            } onCancel: {
                Task { @MainActor [weak self] in self?.send(.cancel, ["token": token]) }
            }
            guard !Task.isCancelled else { return nil }
            if let image = reply["image"], CFGetTypeID(image as CFTypeRef) == CGImage.typeID {
                return (image as! CGImage)
            }
            guard let data = reply["data"] as? Data else { return nil }
            let limit = max(size.width, size.height)
            return await Task.detached(priority: .utility) { Self.load(data, limit: limit) }.value
        } catch { if !Task.isCancelled { transport.log(error) }; return nil }
    }

    func waveform(for media: MediaItem, bins: Int) async -> [Float]? {
        guard transport.capabilities.bool("supportsWaveform"), !Task.isCancelled else { return nil }
        do {
            let reply = try await withTaskCancellationHandler {
                try await transport.request(.waveform, service: .thumbnails, arguments: ["media": ["id": media.id, "url": media.mrl], "bins": bins])
            } onCancel: {
                // Stops the AVAssetReader loop of the running analysis (ARC-05).
                Task { @MainActor [weak self] in self?.send(.cancelWaveform, [:]) }
            }
            guard !Task.isCancelled else { return nil }
            return (reply["samples"] as? [NSNumber])?.map(\.floatValue)
        }
        catch { if !Task.isCancelled { transport.log(error) }; return nil }
    }

    /// Fire-and-forget control request (cancellation); its reply carries nothing.
    private func send(_ request: MXRBridgeRequest, _ arguments: [String: Any]) {
        let transport = transport
        Task { @MainActor in _ = try? await transport.request(request, service: .thumbnails, arguments: arguments) }
    }

    nonisolated private static func load(_ data: Data, limit: Double) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: max(16, limit), kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary)
    }
}
