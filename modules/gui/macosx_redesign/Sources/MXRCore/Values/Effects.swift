import Foundation

/// An sRGB color stored like VLC's `CONFIG_ITEM_RGB` options (0xRRGGBB). Data only; views take
/// their own colors from the design tokens.
public struct RGBColor: Hashable, Sendable, Codable, CustomStringConvertible {
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// Creates a color from VLC's integer form `0xRRGGBB`.
    public init(vlcValue: Int) {
        red = UInt8((vlcValue >> 16) & 0xFF)
        green = UInt8((vlcValue >> 8) & 0xFF)
        blue = UInt8(vlcValue & 0xFF)
    }

    /// Parses "#RRGGBB" or "RRGGBB" (the color fields).
    public init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = Int(text, radix: 16) else { return nil }
        self.init(vlcValue: value)
    }

    /// `0xRRGGBB`.
    public var vlcValue: Int { Int(red) << 16 | Int(green) << 8 | Int(blue) }

    /// "#RRGGBB" in upper case, as the design shows it.
    public var hex: String { String(format: "#%02X%02X%02X", red, green, blue) }

    public var description: String { hex }

    public static let white = RGBColor(red: 255, green: 255, blue: 255)
    public static let black = RGBColor(red: 0, green: 0, blue: 0)
}

// MARK: - Video

/// Mirror transform (sidebar Video tab "Flip"; VLC `transform` filter `hflip`/`vflip`).
public enum VideoFlip: String, Sendable, Codable, Hashable, CaseIterable {
    case none
    case horizontal
    case vertical

    public var title: String {
        switch self {
        case .none: "None"
        case .horizontal: "Horizontal"
        case .vertical: "Vertical"
        }
    }
}

/// Fixed zoom levels (VLC `zoom` vout variable) plus fit-to-window (`autoscale`).
public enum VideoZoom: String, Sendable, Codable, Hashable, CaseIterable {
    case fitWindow
    case quarter
    case half
    case original
    case double

    /// Labels as in VLC menus and the Figma dropdown ("1:1 Original").
    public var title: String {
        switch self {
        case .fitWindow: "Fit to Window"
        case .quarter: "1:4 Quarter"
        case .half: "1:2 Half"
        case .original: "1:1 Original"
        case .double: "2:1 Double"
        }
    }

    /// The VLC `zoom` factor; nil for fit-to-window (autoscale on).
    public var factor: Double? {
        switch self {
        case .fitWindow: nil
        case .quarter: 0.25
        case .half: 0.5
        case .original: 1
        case .double: 2
        }
    }
}

/// HDR output choices from the Figma "HDR Options" dropdown. How each maps to the display
/// (tone mapping vs EDR passthrough) is decided by the backend (ARCHITECTURE §3.6).
public enum HDRMode: String, Sendable, Codable, Hashable, CaseIterable {
    case auto
    case off
    case hdr10
    case hdr10Plus
    case dolbyVision
    case hlg

    public var title: String {
        switch self {
        case .auto: "Auto"
        case .off: "Off"
        case .hdr10: "HDR10"
        case .hdr10Plus: "HDR10+"
        case .dolbyVision: "Dolby Vision"
        case .hlg: "HLG"
        }
    }
}

/// Deinterlacing (VLC `deinterlace` -1 auto / 0 off / 1 on, and `deinterlace-mode`).
public enum DeinterlaceMode: String, Sendable, Codable, Hashable, CaseIterable {
    case automatic
    /// Deinterlacing forced on while VLC chooses its default algorithm.
    case autoAlgorithm = "auto"
    case off
    case blend, bob, discard, linear, mean, x, yadif, yadif2x, phosphor, ivtc

    public var title: String {
        switch self {
        case .automatic: "Automatic"
        case .autoAlgorithm: "On (Automatic Method)"
        case .off: "Off"
        case .yadif2x: "Yadif (2x)"
        case .ivtc: "Film NTSC (IVTC)"
        default: rawValue.prefix(1).uppercased() + rawValue.dropFirst()
        }
    }
}

/// Essential picture filters (Figma "Video - Essential" card): VLC `adjust`, `sharpen`, `gradfun`, `grain`.
public struct EssentialVideoFilters: Hashable, Sendable, Codable {
    public var isEnabled: Bool
    /// Degrees, -180...180 (adjust `hue`).
    public var hue: Double
    /// 0...2, 1 = unchanged (adjust `brightness`).
    public var brightness: Double
    /// 0...2, 1 = unchanged.
    public var contrast: Double
    /// 0...3, 1 = unchanged.
    public var saturation: Double
    /// 0.01...10, 1 = unchanged.
    public var gamma: Double
    /// 0...2, 0 = off (`sharpen-sigma`).
    public var sharpenSigma: Double
    /// 0 = off, else 1...32 (`gradfun-radius`, "Banding Removal Radius").
    public var bandingRemovalRadius: Int
    /// 0 = off, else 0...10 (`grain-variance`, "Film Grain Variance").
    public var filmGrainVariance: Double

    public init(isEnabled: Bool = false, hue: Double = 0, brightness: Double = 1, contrast: Double = 1, saturation: Double = 1,
                gamma: Double = 1, sharpenSigma: Double = 0, bandingRemovalRadius: Int = 0, filmGrainVariance: Double = 0) {
        self.isEnabled = isEnabled
        self.hue = hue
        self.brightness = brightness
        self.contrast = contrast
        self.saturation = saturation
        self.gamma = gamma
        self.sharpenSigma = sharpenSigma
        self.bandingRemovalRadius = bandingRemovalRadius
        self.filmGrainVariance = filmGrainVariance
    }

    /// True when hue, brightness, contrast, saturation or gamma differ from neutral, i.e. when VLC's
    /// `adjust` filter changes the picture. The Essential card has no enable switch (536:1860).
    public var adjustsPicture: Bool {
        hue != 0 || brightness != 1 || contrast != 1 || saturation != 1 || gamma != 1
    }
}

/// Pixel crop (Figma "Video - Crop" card; VLC `croppadd`).
public struct CropInsets: Hashable, Sendable, Codable {
    public var top: Int
    public var bottom: Int
    public var left: Int
    public var right: Int

    public init(top: Int = 0, bottom: Int = 0, left: Int = 0, right: Int = 0) {
        self.top = top
        self.bottom = bottom
        self.left = left
        self.right = right
    }

    public static let zero = CropInsets()
}

/// Color filters (Figma "Video - Colors" card): VLC `extract`, `colorthres`, `invert`, `posterize`,
/// `gradient`, `sepia`.
public struct ColorVideoFilters: Hashable, Sendable, Codable {
    public var colorExtraction: Bool
    public var extractionColor: RGBColor
    public var colorThreshold: Bool
    public var thresholdColor: RGBColor
    /// 0...255 (`colorthres-saturationthres`).
    public var thresholdSaturation: Int
    /// 0...255 (`colorthres-similaritythres`).
    public var thresholdSimilarity: Int
    public var negate: Bool
    public var posterize: Bool
    /// 2...256 (`posterize-level`).
    public var posterizeLevel: Int
    public var gradient: Bool
    /// `gradient-color` ("Keep color"; VLC's default is off).
    public var gradientColor: Bool
    /// `gradient-mode`: "gradient", "edge" or "hough" (``gradientModes``).
    public var gradientMode: String
    /// `gradient-cartoon`.
    public var cartoon: Bool
    public var sepia: Bool
    /// 0...255 (`sepia-intensity`).
    public var sepiaIntensity: Int

    public init(colorExtraction: Bool = false, extractionColor: RGBColor = RGBColor(red: 255, green: 0, blue: 0),
                colorThreshold: Bool = false, thresholdColor: RGBColor = RGBColor(red: 255, green: 0, blue: 0),
                thresholdSaturation: Int = 20, thresholdSimilarity: Int = 15, negate: Bool = false, posterize: Bool = false,
                posterizeLevel: Int = 6, gradient: Bool = false, gradientColor: Bool = false, gradientMode: String = ColorVideoFilters.defaultGradientMode,
                cartoon: Bool = true, sepia: Bool = false, sepiaIntensity: Int = 120) {
        self.colorExtraction = colorExtraction
        self.extractionColor = extractionColor
        self.colorThreshold = colorThreshold
        self.thresholdColor = thresholdColor
        self.thresholdSaturation = thresholdSaturation
        self.thresholdSimilarity = thresholdSimilarity
        self.negate = negate
        self.posterize = posterize
        self.posterizeLevel = posterizeLevel
        self.gradient = gradient
        self.gradientColor = gradientColor
        self.gradientMode = gradientMode
        self.cartoon = cartoon
        self.sepia = sepia
        self.sepiaIntensity = sepiaIntensity
    }

    /// The gradient filter's distort modes (modules/video_filter/gradient.c `mode_list`), value and title.
    public static let gradientModes: [(value: String, title: String)] = [("gradient", "Gradient"), ("edge", "Edge"), ("hough", "Hough")]
    /// VLC's default `gradient-mode`.
    public static let defaultGradientMode = "gradient"

    /// Values saved before `gradientMode` existed (presets, settings), or an engine without the
    /// gradient module (its option then reads as a number), decode with VLC's default.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(colorExtraction: try c.decode(Bool.self, forKey: .colorExtraction),
                  extractionColor: try c.decode(RGBColor.self, forKey: .extractionColor),
                  colorThreshold: try c.decode(Bool.self, forKey: .colorThreshold),
                  thresholdColor: try c.decode(RGBColor.self, forKey: .thresholdColor),
                  thresholdSaturation: try c.decode(Int.self, forKey: .thresholdSaturation),
                  thresholdSimilarity: try c.decode(Int.self, forKey: .thresholdSimilarity),
                  negate: try c.decode(Bool.self, forKey: .negate), posterize: try c.decode(Bool.self, forKey: .posterize),
                  posterizeLevel: try c.decode(Int.self, forKey: .posterizeLevel), gradient: try c.decode(Bool.self, forKey: .gradient),
                  gradientColor: try c.decode(Bool.self, forKey: .gradientColor),
                  gradientMode: (try? c.decodeIfPresent(String.self, forKey: .gradientMode)) ?? Self.defaultGradientMode,
                  cartoon: try c.decode(Bool.self, forKey: .cartoon), sepia: try c.decode(Bool.self, forKey: .sepia),
                  sepiaIntensity: try c.decode(Int.self, forKey: .sepiaIntensity))
    }
}

/// Everything in the sidebar Video tab (S18). Applied live to the current vouts.
public struct VideoEffects: Hashable, Sendable, Codable {
    public var flip: VideoFlip
    /// Rotation in degrees, 0...359 (`rotate` filter); 0 = off.
    public var rotation: Double
    public var zoom: VideoZoom
    public var hdr: HDRMode
    /// Preferred resolution for adaptive streams ("Best Available" = nil), e.g. "1080p".
    public var resolution: String?
    /// Aspect ratio override ("16:9"); nil = Default.
    public var aspectRatio: String?
    /// Crop ratio ("2.35:1"); nil = Default.
    public var crop: String?
    public var deinterlace: DeinterlaceMode
    /// Renderer (cast target) id; nil = "Local".
    public var rendererID: String?
    public var essential: EssentialVideoFilters
    public var cropInsets: CropInsets
    public var colors: ColorVideoFilters

    public init(flip: VideoFlip = .none, rotation: Double = 0, zoom: VideoZoom = .original, hdr: HDRMode = .auto,
                resolution: String? = nil, aspectRatio: String? = nil, crop: String? = nil, deinterlace: DeinterlaceMode = .automatic,
                rendererID: String? = nil, essential: EssentialVideoFilters = EssentialVideoFilters(),
                cropInsets: CropInsets = .zero, colors: ColorVideoFilters = ColorVideoFilters()) {
        self.flip = flip
        self.rotation = rotation
        self.zoom = zoom
        self.hdr = hdr
        self.resolution = resolution
        self.aspectRatio = aspectRatio
        self.crop = crop
        self.deinterlace = deinterlace
        self.rendererID = rendererID
        self.essential = essential
        self.cropInsets = cropInsets
        self.colors = colors
    }

    /// The defaults (no filter active).
    public static let `default` = VideoEffects()

    /// Aspect-ratio choices (VLC defaults); the first entry (nil) is "Default".
    public static let aspectRatioChoices: [String?] = [nil, "16:9", "4:3", "1:1", "16:10", "2.21:1", "2.35:1", "2.39:1", "5:4"]
    /// Crop choices (VLC defaults); the first entry (nil) is "Default".
    public static let cropChoices: [String?] = [nil, "16:10", "16:9", "4:3", "1.85:1", "2.21:1", "2.35:1", "2.39:1", "5:3", "5:4", "1:1"]
    /// Preferred stream resolutions the engine accepts (`preferred-resolution`, VLC's own list);
    /// nil is "Best Available". The bridge rejects anything else.
    public static let resolutionChoices: [String?] = [nil, "1080p", "720p", "576p", "360p", "240p"]

    /// The same effects limited to what the engine accepts (D039): an unsupported preferred
    /// resolution becomes "Best Available" and any HDR override becomes Auto. Legacy presets saved
    /// with 2160p or HDR10 then still apply their flip, rotation, zoom, crop and filters.
    public var sanitized: VideoEffects {
        var copy = self
        if let resolution, !Self.resolutionChoices.contains(resolution) { copy.resolution = nil }
        copy.hdr = .auto
        return copy
    }
}

// MARK: - Audio

/// Stereo mode (`vlc_player_aout_SetStereoMode`, `enum vlc_aout_stereo_mode`).
public enum StereoMode: Int, Sendable, Codable, Hashable, CaseIterable {
    case unset = 0
    case stereo = 1
    case reverseStereo = 2
    case left = 3
    case right = 4
    case dolbySurround = 5
    case headphones = 6
    case mono = 7

    public var title: String {
        switch self {
        case .unset: "Original"
        case .stereo: "Stereo"
        case .reverseStereo: "Reverse Stereo"
        case .left: "Left"
        case .right: "Right"
        case .dolbySurround: "Dolby Surround"
        case .headphones: "Headphones"
        case .mono: "Mono"
        }
    }
}

/// A 10-band equalizer preset (`modules/audio_filter/equalizer_presets.h`).
public struct EqualizerPreset: Identifiable, Hashable, Sendable, Codable {
    /// VLC preset name ("flat", "rock"); "none" disables the equalizer.
    public var id: String
    /// Label from the Figma "EQ presets" list.
    public var title: String
    /// Preamp in dB (-20...20).
    public var preamp: Double
    /// Gains in dB for the 10 bands of ``EqualizerSettings/bandFrequencies``.
    public var bands: [Double]

    public init(id: String, title: String, preamp: Double, bands: [Double]) {
        self.id = id
        self.title = title
        self.preamp = preamp
        self.bands = bands
    }

    /// "None" plus VLC's 18 presets, in the Figma order. Values are VLC's.
    public static let builtIn: [EqualizerPreset] = [
        .init(id: "none", title: "None", preamp: 0, bands: Array(repeating: 0, count: 10)),
        .init(id: "flat", title: "Flat", preamp: 12, bands: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
        .init(id: "classical", title: "Classical", preamp: 12, bands: [0, 0, 0, 0, 0, 0, -7.2, -7.2, -7.2, -9.6]),
        .init(id: "club", title: "Club", preamp: 6, bands: [0, 0, 8, 5.6, 5.6, 5.6, 3.2, 0, 0, 0]),
        .init(id: "dance", title: "Dance", preamp: 5, bands: [9.6, 7.2, 2.4, 0, 0, -5.6, -7.2, -7.2, 0, 0]),
        .init(id: "fullbass", title: "Full base", preamp: 5, bands: [-8, 9.6, 9.6, 5.6, 1.6, -4, -8, -10.4, -11.2, -11.2]),
        .init(id: "fullbasstreble", title: "Full base & treble", preamp: 4, bands: [7.2, 5.6, 0, -7.2, -4.8, 1.6, 8, 11.2, 12, 12]),
        .init(id: "fulltreble", title: "Full treble", preamp: 3, bands: [-9.6, -9.6, -9.6, -4, 2.4, 11.2, 16, 16, 16, 16.8]),
        .init(id: "headphones", title: "Headphones", preamp: 4, bands: [4.8, 11.2, 5.6, -3.2, -2.4, 1.6, 4.8, 9.6, 12.8, 14.4]),
        .init(id: "largehall", title: "Large hall", preamp: 5, bands: [10.4, 10.4, 5.6, 5.6, 0, -4.8, -4.8, -4.8, 0, 0]),
        .init(id: "live", title: "Live", preamp: 7, bands: [-4.8, 0, 4, 5.6, 5.6, 5.6, 4, 2.4, 2.4, 2.4]),
        .init(id: "party", title: "Party", preamp: 6, bands: [7.2, 7.2, 0, 0, 0, 0, 0, 0, 7.2, 7.2]),
        .init(id: "pop", title: "Pop", preamp: 6, bands: [-1.6, 4.8, 7.2, 8, 5.6, 0, -2.4, -2.4, -1.6, -1.6]),
        .init(id: "reggae", title: "Reggae", preamp: 8, bands: [0, 0, 0, -5.6, 0, 6.4, 6.4, 0, 0, 0]),
        .init(id: "rock", title: "Rock", preamp: 5, bands: [8, 4.8, -5.6, -8, -3.2, 4, 8.8, 11.2, 11.2, 11.2]),
        .init(id: "ska", title: "Ska", preamp: 6, bands: [-2.4, -4.8, -4, 0, 4, 5.6, 8.8, 9.6, 11.2, 9.6]),
        .init(id: "soft", title: "Soft", preamp: 5, bands: [4.8, 1.6, 0, -2.4, 0, 4, 8, 9.6, 11.2, 12]),
        .init(id: "softrock", title: "Soft rock", preamp: 7, bands: [4, 4, 2.4, 0, -4, -5.6, -3.2, 0, 2.4, 8.8]),
        .init(id: "techno", title: "Techno", preamp: 5, bands: [8, 5.6, 0, -5.6, -4.8, 0, 8, 9.6, 9.6, 8.8]),
    ]
}

/// Equalizer state (VLC `equalizer` audio filter: `equalizer-preset`, `equalizer-preamp`,
/// `equalizer-bands`, `equalizer-2pass`).
public struct EqualizerSettings: Hashable, Sendable, Codable {
    public var isEnabled: Bool
    /// The selected preset id, or nil when the bands were edited by hand.
    public var presetID: String?
    /// dB, -20...20.
    public var preamp: Double
    /// dB per band, -20...20, 10 values.
    public var bands: [Double]
    /// Filter twice ("2 Pass").
    public var twoPass: Bool

    public init(isEnabled: Bool = false, presetID: String? = "none", preamp: Double = 12, bands: [Double] = Array(repeating: 0, count: 10), twoPass: Bool = false) {
        self.isEnabled = isEnabled
        self.presetID = presetID
        self.preamp = preamp
        self.bands = bands
        self.twoPass = twoPass
    }

    /// The band centers in Hz (VLC frequency table, `equalizer-vlcfreqs`, as in the Figma EQ).
    public static let bandFrequencies: [Double] = [60, 170, 310, 600, 1_000, 3_000, 6_000, 12_000, 14_000, 16_000]

    /// Labels for the band sliders: "60 Hz" … "16 KHz", as in the Figma EQ.
    public static let bandLabels: [String] = ["60 Hz", "170 Hz", "310 Hz", "600 Hz", "1 KHz", "3 KHz", "6 KHz", "12 KHz", "14 KHz", "16 KHz"]
}

/// Dynamic range compressor (VLC `compressor` filter). Ranges are VLC's.
public struct CompressorSettings: Hashable, Sendable, Codable {
    public var isEnabled: Bool
    /// 0 = RMS … 1 = peak ("FM5 / Peak").
    public var rmsPeak: Double
    /// ms, 1.5...400.
    public var attack: Double
    /// ms, 2...800.
    public var release: Double
    /// dB, -30...0.
    public var threshold: Double
    /// 1...20 (":1").
    public var ratio: Double
    /// dB, 1...10.
    public var kneeRadius: Double
    /// dB, 0...24.
    public var makeupGain: Double

    public init(isEnabled: Bool = false, rmsPeak: Double = 0.2, attack: Double = 25, release: Double = 100, threshold: Double = -11,
                ratio: Double = 4, kneeRadius: Double = 5, makeupGain: Double = 7) {
        self.isEnabled = isEnabled
        self.rmsPeak = rmsPeak
        self.attack = attack
        self.release = release
        self.threshold = threshold
        self.ratio = ratio
        self.kneeRadius = kneeRadius
        self.makeupGain = makeupGain
    }
}

/// Spatializer (VLC `spatializer` filter). Values are VLC's 0...1.1 ranges; the design shows them ×10.
public struct SpatializerSettings: Hashable, Sendable, Codable {
    public var isEnabled: Bool
    public var roomSize: Double
    public var width: Double
    public var wet: Double
    public var dry: Double
    public var damp: Double

    public init(isEnabled: Bool = false, roomSize: Double = 0.85, width: Double = 1, wet: Double = 0.4, dry: Double = 0.5, damp: Double = 0.5) {
        self.isEnabled = isEnabled
        self.roomSize = roomSize
        self.width = width
        self.wet = wet
        self.dry = dry
        self.damp = damp
    }
}

/// Stereo widener (VLC `stereo_widen` filter).
public struct StereoWidenerSettings: Hashable, Sendable, Codable {
    public var isEnabled: Bool
    /// ms, 1...100.
    public var delay: Double
    /// 0...0.9.
    public var feedback: Double
    /// 0...0.8.
    public var crossfeed: Double
    /// 0...1.
    public var dryMix: Double

    public init(isEnabled: Bool = false, delay: Double = 20, feedback: Double = 0.3, crossfeed: Double = 0.3, dryMix: Double = 0.8) {
        self.isEnabled = isEnabled
        self.delay = delay
        self.feedback = feedback
        self.crossfeed = crossfeed
        self.dryMix = dryMix
    }
}

/// Everything in the sidebar Audio tab's effects (S19), applied live to the aout.
public struct AudioEffects: Hashable, Sendable, Codable {
    public var stereoMode: StereoMode
    public var equalizer: EqualizerSettings
    public var compressor: CompressorSettings
    public var spatializer: SpatializerSettings
    public var stereoWidener: StereoWidenerSettings
    /// Pitch shift in semitones, -12...12 (`scaletempo_pitch`); 0 = off.
    public var pitch: Double

    public init(stereoMode: StereoMode = .unset, equalizer: EqualizerSettings = EqualizerSettings(), compressor: CompressorSettings = CompressorSettings(),
                spatializer: SpatializerSettings = SpatializerSettings(), stereoWidener: StereoWidenerSettings = StereoWidenerSettings(), pitch: Double = 0) {
        self.stereoMode = stereoMode
        self.equalizer = equalizer
        self.compressor = compressor
        self.spatializer = spatializer
        self.stereoWidener = stereoWidener
        self.pitch = pitch
    }

    /// The defaults (no filter active).
    public static let `default` = AudioEffects()
}

// MARK: - Subtitles

/// How subtitle size is given (segmented "Relative | Pixels").
public enum SubtitleSizeMode: String, Sendable, Codable, Hashable, CaseIterable {
    /// `freetype-rel-fontsize` / `sub-text-scale`.
    case relative
    /// `freetype-fontsize` in pixels.
    case pixels

    public var title: String { self == .relative ? "Relative" : "Pixels" }
}

/// Relative subtitle sizes (`freetype-rel-fontsize`: 0 auto, 20 smaller, 18 small, 16 normal, 12 large, 6 larger).
public enum SubtitleRelativeSize: Int, Sendable, Codable, Hashable, CaseIterable {
    case automatic = 0
    case smaller = 20
    case small = 18
    case normal = 16
    case large = 12
    case larger = 6

    public var title: String {
        switch self {
        case .automatic: "Auto" // 804:1331
        case .smaller: "Smaller"
        case .small: "Small"
        case .normal: "Normal"
        case .large: "Large"
        case .larger: "Larger"
        }
    }

    /// The Relative-mode Font Size slider's stops (owner decision on D033, Figma 804:1341): "Auto"
    /// where Figma draws the thumb (stop 3 of 0…5), the smaller sizes to its left and the larger to
    /// its right. The stored value stays VLC's `sub-text-scale` enum.
    public static let sliderOrder: [SubtitleRelativeSize] = [.smaller, .small, .normal, .automatic, .large, .larger]
}

/// Outline thickness (`freetype-outline-thickness`: 0, 2, 4, 6).
public enum SubtitleOutline: Int, Sendable, Codable, Hashable, CaseIterable {
    case none = 0
    case thin = 2
    case normal = 4
    case thick = 6

    public var title: String {
        switch self {
        case .none: "None"
        case .thin: "Thin"
        case .normal: "Normal"
        case .thick: "Thick"
        }
    }

    /// The preset nearest to a typed pixel thickness (Pixels mode field, 07m52.9); ties go thinner.
    public static func nearest(pixels: Int) -> SubtitleOutline {
        allCases.min { abs($0.rawValue - pixels) < abs($1.rawValue - pixels) } ?? .normal
    }
}

/// Shadow distance presets (`freetype-shadow-distance`, 0...1).
public enum SubtitleShadowDistance: String, Sendable, Codable, Hashable, CaseIterable {
    case small, medium, large

    public var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
    /// The VLC value.
    public var vlcValue: Double {
        switch self {
        case .small: 0.06
        case .medium: 0.12
        case .large: 0.2
        }
    }
}

/// Vertical subtitle placement.
public enum SubtitlePosition: String, Sendable, Codable, Hashable, CaseIterable {
    case bottom, top

    public var title: String { self == .bottom ? "Bottom" : "Top" }
}

/// Subtitle appearance (sidebar Subtitles tab "Appearance", Settings ▸ Subtitles). Maps to the
/// `freetype-*` and `sub-*` options and is applied live to the current vouts.
public struct SubtitleStyle: Hashable, Sendable, Codable {
    /// Font family; empty = system default ("System, sans-serif").
    public var fontFamily: String
    public var sizeMode: SubtitleSizeMode
    public var relativeSize: SubtitleRelativeSize
    /// Pixels (`freetype-fontsize`), used when `sizeMode == .pixels`.
    public var pixelSize: Int
    public var bold: Bool
    public var textColor: RGBColor
    /// 0...1 (`freetype-opacity` / 255).
    public var textOpacity: Double
    public var outline: SubtitleOutline
    public var outlineColor: RGBColor
    public var shadow: Bool
    public var shadowColor: RGBColor
    public var shadowDistance: SubtitleShadowDistance
    /// Whether a background box is drawn: derived from the opacity, the one control for it
    /// (Figma 848:1686). Never stored, so a preset or engine payload cannot disagree with it.
    public var background: Bool { backgroundOpacity > 0 }
    public var backgroundColor: RGBColor
    /// 0...1 (`freetype-background-opacity` / 255).
    public var backgroundOpacity: Double
    public var position: SubtitlePosition
    /// Extra offset in pixels from the edge (`sub-margin`; "Subtitle Offset").
    public var offset: Int
    /// Render embedded ASS/SSA styling ("Embedded Sub Format").
    public var useEmbeddedStyles: Bool

    public init(fontFamily: String = "", sizeMode: SubtitleSizeMode = .relative, relativeSize: SubtitleRelativeSize = .automatic,
                pixelSize: Int = 18, bold: Bool = false, textColor: RGBColor = .white, textOpacity: Double = 1,
                outline: SubtitleOutline = .normal, outlineColor: RGBColor = .black, shadow: Bool = true, shadowColor: RGBColor = .black,
                shadowDistance: SubtitleShadowDistance = .small, backgroundColor: RGBColor = .black,
                backgroundOpacity: Double = 0, position: SubtitlePosition = .bottom, offset: Int = 0, useEmbeddedStyles: Bool = true) {
        self.fontFamily = fontFamily
        self.sizeMode = sizeMode
        self.relativeSize = relativeSize
        self.pixelSize = pixelSize
        self.bold = bold
        self.textColor = textColor
        self.textOpacity = textOpacity
        self.outline = outline
        self.outlineColor = outlineColor
        self.shadow = shadow
        self.shadowColor = shadowColor
        self.shadowDistance = shadowDistance
        self.backgroundColor = backgroundColor
        self.backgroundOpacity = backgroundOpacity
        self.position = position
        self.offset = offset
        self.useEmbeddedStyles = useEmbeddedStyles
    }

    /// Opacity is the single control for the background box in both sidebar inputs.
    public mutating func setBackgroundOpacity(_ opacity: Double) {
        backgroundOpacity = min(max(opacity.isFinite ? opacity : 0, 0), 1)
    }

    private enum CodingKeys: String, CodingKey {
        case fontFamily, sizeMode, relativeSize, pixelSize, bold, textColor, textOpacity, outline, outlineColor
        case shadow, shadowColor, shadowDistance, background, backgroundColor, backgroundOpacity, position, offset, useEmbeddedStyles
    }

    /// A decoded `background` flag is ignored: the opacity alone decides (G-11).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(fontFamily: try c.decode(String.self, forKey: .fontFamily), sizeMode: try c.decode(SubtitleSizeMode.self, forKey: .sizeMode),
                  relativeSize: try c.decode(SubtitleRelativeSize.self, forKey: .relativeSize), pixelSize: try c.decode(Int.self, forKey: .pixelSize),
                  bold: try c.decode(Bool.self, forKey: .bold), textColor: try c.decode(RGBColor.self, forKey: .textColor),
                  textOpacity: try c.decode(Double.self, forKey: .textOpacity), outline: try c.decode(SubtitleOutline.self, forKey: .outline),
                  outlineColor: try c.decode(RGBColor.self, forKey: .outlineColor), shadow: try c.decode(Bool.self, forKey: .shadow),
                  shadowColor: try c.decode(RGBColor.self, forKey: .shadowColor), shadowDistance: try c.decode(SubtitleShadowDistance.self, forKey: .shadowDistance),
                  backgroundColor: try c.decode(RGBColor.self, forKey: .backgroundColor), backgroundOpacity: try c.decode(Double.self, forKey: .backgroundOpacity),
                  position: try c.decode(SubtitlePosition.self, forKey: .position), offset: try c.decode(Int.self, forKey: .offset),
                  useEmbeddedStyles: try c.decode(Bool.self, forKey: .useEmbeddedStyles))
    }

    /// Still writes `background` (derived) because the bridge reads it (MXREffectsServices.m).
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(fontFamily, forKey: .fontFamily); try c.encode(sizeMode, forKey: .sizeMode)
        try c.encode(relativeSize, forKey: .relativeSize); try c.encode(pixelSize, forKey: .pixelSize)
        try c.encode(bold, forKey: .bold); try c.encode(textColor, forKey: .textColor); try c.encode(textOpacity, forKey: .textOpacity)
        try c.encode(outline, forKey: .outline); try c.encode(outlineColor, forKey: .outlineColor); try c.encode(shadow, forKey: .shadow)
        try c.encode(shadowColor, forKey: .shadowColor); try c.encode(shadowDistance, forKey: .shadowDistance)
        try c.encode(background, forKey: .background); try c.encode(backgroundColor, forKey: .backgroundColor)
        try c.encode(backgroundOpacity, forKey: .backgroundOpacity); try c.encode(position, forKey: .position)
        try c.encode(offset, forKey: .offset); try c.encode(useEmbeddedStyles, forKey: .useEmbeddedStyles)
    }

    /// VLC defaults.
    public static let `default` = SubtitleStyle()
}
