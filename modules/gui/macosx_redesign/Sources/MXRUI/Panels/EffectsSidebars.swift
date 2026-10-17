import MXRCore
import MXRDesign
import SwiftUI

struct VideoSidebarContent: View {
    @Environment(VideoEffectsModel.self) private var video
    @Environment(AppModel.self) private var app
    var body: some View {
        VStack(spacing: 0) {
            PanelSectionTitle(title: "Defaults")
            VStack(spacing: 0) {
                Text("Flip").foregroundStyle(Theme.Color.fgA3)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, PanelSpace.xs)
                    .frame(height: PanelMetric.flipLabelHeight) // 498:2984
                HStack(spacing: Theme.Spacing.gap2) {
                    ForEach(VideoFlip.allCases, id: \.self) { value in
                        Button { video.update { $0.flip = value } } label: {
                            Text(value.title).frame(maxWidth: .infinity).frame(height: PanelMetric.segmentHeight) // I6114:13499;999:4559
                                .foregroundStyle(video.effects.flip == value ? Theme.Color.accentMain : Theme.Color.fgA3)
                                .background(video.effects.flip == value ? Theme.Color.bgAccentBright : Theme.Color.bgA4,
                                            in: .rect(cornerRadius: Theme.Radius.md))
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        .accessibilityLabel("Flip \(value.title)")
                        .accessibilityAddTraits(video.effects.flip == value ? .isSelected : [])
                    }
                }.padding(Theme.Spacing.gap2).background(Theme.Color.bgB2, in: .rect(cornerRadius: Theme.Radius.lg))
                    .padding(.top, Theme.Spacing.gap5).padding(.bottom, Theme.Spacing.gap10 + Theme.Spacing.gap1)
                // 6114:13491, 09m01.0: a field-only "0 deg" row; typed angles wrap (-90 → 270).
                PanelFieldRow(title: "Rotate", value: String(format: "%.0f deg", video.effects.rotation), commit: { text in
                    if let number = panelNumber(text) { video.update { $0.rotation = (number.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) } }
                }, height: PanelMetric.wideRowHeight)
                PanelDropdownRow(title: "Zoom", selected: video.effects.zoom.title, choices: VideoZoom.allCases.map { value in
                    PanelChoice(id: value.rawValue, title: value.title) { video.update { $0.zoom = value } }
                })
                // 498:2965, 09m01.0: an ordinary "Auto" dropdown. D039: the output picks HDR itself,
                // so Auto is the only choice offered.
                PanelDropdownRow(title: "HDR", selected: HDRMode.auto.title, choices: [
                    PanelChoice(id: HDRMode.auto.rawValue, title: HDRMode.auto.title) { video.update { $0.hdr = .auto } },
                ])
                    .help("HDR is selected automatically by the video output. Manual overrides are unavailable.")
                PanelDropdownRow(title: "Resolution", selected: video.effects.resolution ?? "Best Available", choices: VideoEffects.resolutionChoices.map { value in
                    PanelChoice(id: value ?? "auto", title: value ?? "Best Available") { video.update { $0.resolution = value } }
                })
                    .help("Preferred stream resolution applies to the next media opened.")
                PanelDropdownRow(title: "Aspect Ratio", selected: video.effects.aspectRatio ?? "Default", choices: VideoEffects.aspectRatioChoices.map { value in
                    PanelChoice(id: value ?? "auto", title: value ?? "Default") { video.update { $0.aspectRatio = value } }
                })
                PanelDropdownRow(title: "Crop", selected: video.effects.crop ?? "Default", choices: VideoEffects.cropChoices.map { value in
                    PanelChoice(id: value ?? "auto", title: value ?? "Default") { video.update { $0.crop = value } }
                })
                PanelDropdownRow(title: "Render", selected: app.renderers.items.first(where: { $0.id == app.renderers.selectedID })?.name ?? "Local", choices: rendererChoices)
                    .disabled(!app.capabilities.hasRenderers)
            }.padding(.horizontal, PanelSpace.xl).padding(.top, PanelMetric.settingsSectionPadding).padding(.bottom, Theme.Spacing.gap10)
            PanelDivider(consumesHeight: false)
            PanelSectionTitle(title: "Filters")
            videoCard("Essential") { VideoFilterCardRows(card: .essential) }
            videoCard("Crop") { VideoFilterCardRows(card: .crop) }
            videoCard("Colors") { VideoFilterCardRows(card: .colors) }
            MXRVideoFilterOptionsView()
            videoCard("Deinterlace") {
                PanelDropdown(title: "Deinterlace", selected: video.effects.deinterlace.title, choices: DeinterlaceMode.allCases.map { value in
                    PanelChoice(id: value.rawValue, title: value.title) { video.update { $0.deinterlace = value } }
                })
            }
        }
        .alert("Renderer", isPresented: Binding(get: { app.renderers.errorMessage != nil }, set: { if !$0 { app.renderers.errorMessage = nil } })) {
            Button("OK") { app.renderers.errorMessage = nil }
        } message: { Text(app.renderers.errorMessage ?? "") }
    }
    private var rendererChoices: [PanelChoice] {
        var choices = [PanelChoice(id: "local", title: "Local") { try? app.renderers.select(id: nil) }]
        choices += app.renderers.items.filter(\.canVideo).map { renderer in
            PanelChoice(id: renderer.id, title: renderer.name) { try? app.renderers.select(id: renderer.id) }
        }
        choices.append(PanelChoice(id: "discover", title: app.renderers.isDiscovering ? "Discovering Cast Devices…" : "Discover Cast Devices") {
            Task { try? await app.renderers.discover() }
        })
        return choices
    }
    private func binding<Value>(_ path: WritableKeyPath<VideoEffects, Value>) -> Binding<Value> {
        Binding(get: { video.effects[keyPath: path] }, set: { value in video.update { $0[keyPath: path] = value } })
    }
    private func videoCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: Theme.Spacing.gap10) {
            Text(title).foregroundStyle(Theme.Color.fgA3).frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, PanelSpace.xs).frame(height: PanelMetric.cardTitleHeight) // 498:3034
            PanelExpand(title: title, content: content)
        }.padding(.horizontal, PanelSpace.xl).padding(.top, Theme.Spacing.gap10).padding(.bottom, PanelSpace.xl)
        .overlay(alignment: .bottom) { PanelDivider(consumesHeight: false) }
    }
}

struct AudioSidebarContent: View {
    @Environment(AudioEffectsModel.self) private var audio
    @Environment(TracksModel.self) private var tracks
    @Environment(AppModel.self) private var app
    @State private var showsTestError = false
    @State private var outputTestTask: Task<Void, Never>?
    var body: some View {
        VStack(spacing: 0) {
            PanelSectionTitle(title: "Defaults")
            defaults
            PanelDivider(consumesHeight: false)
            PanelSectionTitle(title: "Synchronization")
            delayControl(title: "Audio Track Delay", value: tracks.audioDelay.seconds, trackHeight: PanelMetric.audioDelayTrackHeight) { tracks.setAudioDelay(.seconds($0)) } // 1905:7353
                .padding(.horizontal, PanelSpace.xl).padding(.top, Theme.Spacing.gap10).padding(.bottom, PanelSpace.xl)
            PanelDivider(consumesHeight: false)
            PanelSectionTitle(title: "Filters")
            equalizer
            filterCard("Compressor", enabled: binding(\.compressor.isEnabled)) { AudioFilterCardRows(card: .compressor) }
            filterCard("Spatializer", enabled: binding(\.spatializer.isEnabled)) { AudioFilterCardRows(card: .spatializer) }
            filterCard("Stereo Widener", enabled: binding(\.stereoWidener.isEnabled)) { AudioFilterCardRows(card: .stereoWidener) }
            slider("Adjust Pitch", path: \.pitch, range: -12...12, unit: " semitones", center: 0)
                .padding(.horizontal, PanelSpace.xl).padding(.vertical, Theme.Spacing.gap10)
        }
        .onChange(of: audio.testOutputError) { _, error in if error != nil { showsTestError = true } }
        .onDisappear { outputTestTask?.cancel() }
        .alert("Audio Output Test", isPresented: $showsTestError) {
            Button("OK") { showsTestError = false }
        } message: { Text(audio.testOutputError ?? "The output test could not start.") }
    }
    private var defaults: some View {
        VStack(spacing: 0) {
            VStack(spacing: PanelMetric.settingsRowGap) {
                PanelFieldRow(title: "Audio Track", value: tracks.trackDefaults.audioTrack.map(String.init) ?? "Automatic") { text in
                    tracks.updateTrackDefaults { $0.audioTrack = Int(text).flatMap { $0 > 0 ? $0 : nil } }
                }
                PanelFieldRow(title: "Audio Language", value: tracks.trackDefaults.audioLanguage ?? "Automatic") { text in
                    tracks.updateTrackDefaults { $0.audioLanguage = text.isEmpty || text == "Automatic" ? nil : text }
                }
            }.padding(.vertical, Theme.Spacing.gap10)
            VStack(spacing: Theme.Spacing.gap10) {
                HStack {
                    Text("Stereo Mode").foregroundStyle(Theme.Color.fgA3)
                    Spacer()
                    Button {
                        outputTestTask = Task { await audio.testStereoOutput() }
                    } label: {
                        HStack(spacing: Theme.Spacing.gap4) {
                            if audio.isTestingOutput { ProgressView().controlSize(.small) }
                            Text("Test").foregroundStyle(Theme.Color.accentDim)
                        }
                    }
                        .buttonStyle(.plain).disabled(!app.capabilities.hasStereoTest || audio.isTestingOutput)
                        .frame(width: PanelMetric.stereoTestSize.width, height: PanelMetric.stereoTestSize.height) // 536:1187
                        .background(Theme.Color.bgAccentDark, in: .rect(cornerRadius: Theme.Radius.md))
                        .accessibilityLabel(audio.isTestingOutput ? "Stereo output test in progress" : "Test stereo output")
                        .help(app.capabilities.hasStereoTest ? "Play a short left and right channel test on the selected audio output." : "Stereo output testing is unavailable in this VLC build.")
                }.padding(.leading, PanelSpace.xs).frame(height: PanelMetric.stereoRowHeight) // 1052:2921
                PanelDropdown(title: "Stereo Mode", selected: audio.effects.stereoMode.title, choices: StereoMode.allCases.map { value in
                    PanelChoice(id: String(value.rawValue), title: value.title) { audio.update { $0.stereoMode = value } }
                }, trailingInset: PanelSpace.md + Theme.Spacing.gap1) // I1052:2923;536:1046: 13 pt right inset.
            }.padding(.bottom, PanelSpace.xl)
        }.padding(.horizontal, PanelSpace.xl)
    }
    private var equalizer: some View {
        VStack(spacing: Theme.Spacing.gap10) {
            Text("Equalizer").foregroundStyle(Theme.Color.fgA3).frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, PanelSpace.xs).frame(height: PanelMetric.cardTitleHeight) // 536:1203
            PanelDropdown(title: "Equalizer preset", selected: audio.selectedEqualizerPreset?.title ?? "Custom", choices: audio.equalizerPresets.map { value in
                PanelChoice(id: value.id, title: value.title, icon: equalizerIcon(value.id)) { audio.applyEqualizerPreset(value) }
            }, leadingInset: PanelSpace.lg, trailingInset: PanelSpace.lg) // 2372:8624: nested option uses 2 + 14 pt insets.
            PanelExpand(title: "Equalizer") { AudioFilterCardRows(card: .equalizer) }
            PanelToggleRow(title: "2 Pass", isOn: binding(\.equalizer.twoPass))
        }.padding(.horizontal, PanelSpace.xl).padding(.top, Theme.Spacing.gap10).padding(.bottom, PanelSpace.xl)
        .overlay(alignment: .bottom) { PanelDivider(consumesHeight: false) }
    }
    private func binding<Value>(_ path: WritableKeyPath<AudioEffects, Value>) -> Binding<Value> {
        Binding(get: { audio.effects[keyPath: path] }, set: { value in audio.update { $0[keyPath: path] = value } })
    }
    private func filterCard<Content: View>(_ title: String, enabled: Binding<Bool>, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: Theme.Spacing.gap10) {
            PanelToggleRow(title: title, isOn: enabled, height: PanelMetric.cardTitleHeight) // 536:1363
            PanelExpand(title: title, content: content)
        }.padding(.horizontal, PanelSpace.xl).padding(.top, Theme.Spacing.gap10).padding(.bottom, PanelSpace.xl)
        .overlay(alignment: .bottom) { PanelDivider(consumesHeight: false) }
    }
    private func slider(_ title: String, path: WritableKeyPath<AudioEffects, Double>, range: ClosedRange<Double>, unit: String = "", center: Double? = nil, scale: Double = 1) -> some View {
        VStack(spacing: PanelMetric.settingsRowGap) {
            PanelFieldRow(title: title, value: String(format: "%.1f", audio.effects[keyPath: path] * scale) + unit) { text in
                if let number = panelNumber(text) { audio.update { $0[keyPath: path] = min(max(number / scale, range.lowerBound), range.upperBound) } }
            }
            PanelSlider(title: title, value: binding(path), range: range, center: center)
        }
    }
    private func equalizerIcon(_ id: String) -> MXRIcon.Name {
        switch id {
        case "classical": .eqClassical; case "club": .eqClub; case "dance": .eqDance
        case "fullbass": .eqFullBass; case "fullbasstreble": .eqFullBassAndTreble; case "fulltreble": .eqFullTreble
        case "headphones": .eqHeadphones; case "largehall": .eqLargeHall; case "live": .eqLive
        case "party": .eqParty; case "pop": .eqPop; case "reggae": .eqReggae; case "rock": .eqRock
        case "ska": .eqSka; case "soft": .eqSoft; case "softrock": .eqSoftRock; case "techno": .eqTechno
        default: .eq
        }
    }
}

// MARK: - Filter cards

/// The sidebar's filter cards with their own Figma component sets (open variant in brackets):
/// Essential 536:1855 (536:1860), Crop 543:990 (543:995), Colors 614:1430 (614:1435), Equalizer
/// 6114:13610 (6114:13615), Compressor 536:1513 (536:1514), Spatializer 536:1703 (536:1708) and
/// Stereo Widener 612:1223 (612:1228).
public enum MXRFilterCard: String, CaseIterable, Sendable {
    case essential, crop, colors, equalizer, compressor, spatializer, stereoWidener

    var title: String {
        switch self {
        case .essential: "Essential"
        case .crop: "Crop"
        case .colors: "Colors"
        case .equalizer: "Equalizer"
        case .compressor: "Compressor"
        case .spatializer: "Spatializer"
        case .stereoWidener: "Stereo Widener"
        }
    }
}

/// One filter card on its own, open or closed, as the component sets draw it (gallery and tests).
public struct MXRFilterCardPreview: View {
    let card: MXRFilterCard
    let expanded: Bool
    public init(_ card: MXRFilterCard, expanded: Bool = true) {
        self.card = card
        self.expanded = expanded
    }
    public var body: some View {
        Group {
            switch card {
            case .essential, .crop, .colors:
                PanelExpand(title: card.title, expanded: expanded) { VideoFilterCardRows(card: card) }
            case .equalizer, .compressor, .spatializer, .stereoWidener:
                PanelExpand(title: card.title, expanded: expanded) { AudioFilterCardRows(card: card) }
            }
        }
        .mxrTextStyle(Theme.Font.body).foregroundStyle(Theme.Color.fgA2)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// The rows of an open video filter card.
struct VideoFilterCardRows: View {
    let card: MXRFilterCard
    @Environment(VideoEffectsModel.self) private var video
    /// 774:1081: the link buttons apply one value to both opposite edges.
    @State private var linksVertical = false
    @State private var linksHorizontal = false

    var body: some View {
        switch card {
        case .essential: essential
        case .crop: crop
        default: colors
        }
    }

    // 536:1860: label-only rows; the ticks are the Figma "degrees" marks of each slider.
    @ViewBuilder private var essential: some View {
        essentialSlider("Hue", \.hue, range: -180...180, stops: 3)
        essentialSlider("Brightness", \.brightness, range: 0...2, stops: 3)
        essentialSlider("Contrast", \.contrast, range: 0...2, stops: 3)
        essentialSlider("Saturation", \.saturation, range: 0...3, stops: 4)
        essentialSlider("Gamma", \.gamma, range: 0.01...10, stops: 11)
        essentialSlider("Sharpen Sigma", \.sharpenSigma, range: 0...2, stops: 5)
        PanelCardSliderRow(title: "Banding Removal Radius", number: Binding(
            get: { Double(video.effects.essential.bandingRemovalRadius) },
            set: { value in video.updateEssential { $0.bandingRemovalRadius = Int(value.rounded()) } }),
            range: 0...32, step: 1, stops: 8)
        essentialSlider("Film Grain Variance", \.filmGrainVariance, range: 0...10, stops: 11)
    }

    private func essentialSlider(_ title: String, _ path: WritableKeyPath<EssentialVideoFilters, Double>,
                                 range: ClosedRange<Double>, stops: Int) -> some View {
        PanelCardSliderRow(title: title, number: Binding(
            get: { video.effects.essential[keyPath: path] },
            set: { value in video.updateEssential { $0[keyPath: path] = min(max(value, range.lowerBound), range.upperBound) } }),
            range: range, stops: stops)
    }

    // 543:995: two rows of paired pixel fields, each pair with a link button.
    private var crop: some View {
        VStack(spacing: 0) {
            cropPair(\.top, "Top", \.bottom, "Bottom", linked: $linksVertical, name: "top and bottom")
                .padding(.top, Theme.Spacing.gap6).padding(.bottom, Theme.Spacing.gap10) // 774:995
            cropPair(\.left, "Left", \.right, "Right", linked: $linksHorizontal, name: "left and right")
                .padding(.vertical, Theme.Spacing.gap6) // 774:1031
        }
        .padding(.horizontal, PanelSpace.lg)
    }

    private func cropPair(_ first: WritableKeyPath<CropInsets, Int>, _ firstTitle: String,
                          _ second: WritableKeyPath<CropInsets, Int>, _ secondTitle: String,
                          linked: Binding<Bool>, name: String) -> some View {
        HStack(spacing: PanelSpace.sm) {
            PanelCropField(title: firstTitle, value: video.effects.cropInsets[keyPath: first]) { value in
                video.update { $0.cropInsets[keyPath: first] = value; if linked.wrappedValue { $0.cropInsets[keyPath: second] = value } }
            }
            PanelCropField(title: secondTitle, value: video.effects.cropInsets[keyPath: second]) { value in
                video.update { $0.cropInsets[keyPath: second] = value; if linked.wrappedValue { $0.cropInsets[keyPath: first] = value } }
            }
            Button {
                linked.wrappedValue.toggle()
                // Linking evens the pair out at the first edge's value.
                if linked.wrappedValue { video.update { $0.cropInsets[keyPath: second] = $0.cropInsets[keyPath: first] } }
            } label: {
                MXRIcon(.link, state: linked.wrappedValue ? .active : .default)
                    .frame(width: PanelMetric.cropLinkSize.width, height: PanelMetric.cropLinkSize.height)
            }
            .buttonStyle(PanelButtonStyle(kind: .icon))
            .help(linked.wrappedValue ? "Crop \(name) separately" : "Crop \(name) by the same amount")
            .accessibilityLabel("Link \(name)")
            .accessibilityValue(linked.wrappedValue ? "On" : "Off")
        }
    }

    // 614:1435: sections divided edge to edge.
    @ViewBuilder private var colors: some View {
        PanelCardToggleRow(title: "Color Extraction", isOn: binding(\.colors.colorExtraction)) {
            PanelCompactColorField(title: "Extraction Color", color: binding(\.colors.extractionColor))
        }
        .padding(.horizontal, PanelSpace.lg).padding(.top, Theme.Spacing.gap6).padding(.bottom, PanelSpace.xl) // 614:1567
        PanelDivider(consumesHeight: false)
        VStack(spacing: 0) { // 673:1661
            PanelCardToggleRow(title: "Color Threshold", isOn: binding(\.colors.colorThreshold)) {
                PanelCompactColorField(title: "Threshold Color", color: binding(\.colors.thresholdColor))
            }
            .padding(.horizontal, PanelSpace.lg).padding(.bottom, Theme.Spacing.gap6)
            Group {
                PanelCardSliderRow(title: "Saturation", number: intBinding(\.colors.thresholdSaturation), range: 0...255, step: 1)
                PanelCardSliderRow(title: "Similarity", number: intBinding(\.colors.thresholdSimilarity), range: 0...255, step: 1, bottomPadding: 0)
            }
            .disabled(!video.effects.colors.colorThreshold)
        }
        .padding(.vertical, PanelSpace.xl)
        PanelDivider(consumesHeight: false)
        PanelCardToggleRow(title: "Negate Colors", isOn: binding(\.colors.negate))
            .padding(.horizontal, PanelSpace.lg).padding(.top, PanelSpace.xl).padding(.bottom, Theme.Spacing.gap10) // 673:1621
        PanelDivider(consumesHeight: false)
        VStack(spacing: 0) { // 673:1631
            PanelCardToggleRow(title: "Posterize", isOn: binding(\.colors.posterize))
                .padding(.horizontal, PanelSpace.lg).padding(.vertical, Theme.Spacing.gap10)
            // Figma draws Posterize off; once on, VLC's level (2–256) appears under it.
            if video.effects.colors.posterize {
                PanelCardSliderRow(title: "Posterize Levels", value: String(video.effects.colors.posterizeLevel),
                                   number: intBinding(\.colors.posterizeLevel), range: 2...256, step: 1)
            }
        }
        PanelDivider(consumesHeight: false)
        VStack(spacing: PanelMetric.gradientSectionGap) { // 673:1662
            PanelCardToggleRow(title: "Gradient", isOn: binding(\.colors.gradient))
            PanelDropdown(title: "Gradient mode",
                          selected: ColorVideoFilters.gradientModes.first { $0.value == video.effects.colors.gradientMode }?.title ?? video.effects.colors.gradientMode,
                          choices: ColorVideoFilters.gradientModes.map { mode in
                              PanelChoice(id: mode.value, title: mode.title) { video.update { $0.colors.gradientMode = mode.value } }
                          }, valueColor: video.effects.colors.gradient ? Theme.Color.fgA2 : Theme.Color.fgA3, frameColor: Theme.Color.bgB1)
            PanelCardToggleRow(title: "Color", isOn: binding(\.colors.gradientColor))
            PanelCardToggleRow(title: "Cartoon", isOn: binding(\.colors.cartoon))
        }
        .padding(.horizontal, PanelSpace.lg).padding(.vertical, PanelMetric.gradientSectionGap)
        PanelDivider(consumesHeight: false)
        PanelCardSliderRow(title: "Sepia Intensity", number: Binding(get: { Double(video.sepiaIntensity) },
                                                                     set: { video.setSepiaIntensity(Int($0.rounded())) }),
                           range: 0...255, step: 1, stops: 4)
            .padding(.top, Theme.Spacing.gap10) // 673:1691
    }

    private func binding<Value>(_ path: WritableKeyPath<VideoEffects, Value>) -> Binding<Value> {
        Binding(get: { video.effects[keyPath: path] }, set: { value in video.update { $0[keyPath: path] = value } })
    }
    private func intBinding(_ path: WritableKeyPath<VideoEffects, Int>) -> Binding<Double> {
        Binding(get: { Double(video.effects[keyPath: path]) }, set: { value in video.update { $0[keyPath: path] = Int(value.rounded()) } })
    }
}

/// A Crop card field (774:1024): "Top" in FG/A3, the editable number in FG/A2 and "px" in FG/A4 on
/// a 33 pt BG/B2 box; the number starts 72 pt in.
private struct PanelCropField: View {
    let title: String
    let value: Int
    let commit: (Int) -> Void
    @State private var draft = ""
    @FocusState private var focused: Bool
    var body: some View {
        HStack(spacing: 0) {
            Text(title).foregroundStyle(Theme.Color.fgA3).lineLimit(1)
                .frame(width: PanelMetric.cropLabelWidth, alignment: .leading)
            // The hidden text sizes the field to its digits, so "px" follows the number.
            Text(draft.isEmpty ? "0" : draft).hidden()
                .overlay(alignment: .leading) {
                    TextField(title, text: $draft).textFieldStyle(.plain).labelsHidden()
                        .foregroundStyle(Theme.Color.fgA2)
                        .focused($focused)
                }
                .padding(.trailing, Theme.Spacing.gap1)
            Text(" px").foregroundStyle(Theme.Color.fgA4).accessibilityHidden(true)
            Spacer(minLength: 0)
        }
        .lineLimit(1)
        .padding(.leading, PanelSpace.md)
        .frame(maxWidth: .infinity)
        .frame(height: PanelMetric.cropFieldHeight)
        .background(Theme.Color.bgB2, in: .rect(cornerRadius: Theme.Radius.lg))
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
        .onAppear { draft = String(value) }
        .onChange(of: value) { _, new in if !focused { draft = String(new) } }
        .onSubmit(apply)
        .onChange(of: focused) { old, new in if old && !new { apply() } }
        .onExitCommand { draft = String(value); focused = false }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Crop \(title.lowercased()), pixels")
    }
    private func apply() {
        if let number = Int(draft.trimmingCharacters(in: .whitespaces)) { commit(max(0, number)) }
        draft = String(value)
    }
}

/// The rows of an open audio filter card.
struct AudioFilterCardRows: View {
    let card: MXRFilterCard
    @Environment(AudioEffectsModel.self) private var audio

    var body: some View {
        switch card {
        case .equalizer: equalizer
        case .compressor:
            // 536:1514: label and value text over each slider.
            slider("RMS / Peak", \.compressor.rmsPeak, range: 0...1, format: "%.1f")
            slider("Attack", \.compressor.attack, range: 1.5...400, format: "%.1f ms")
            slider("Release", \.compressor.release, range: 2...800, format: "%.1f ms")
            slider("Threshold", \.compressor.threshold, range: -30...0, format: "%.1f dB")
            slider("Ratio", \.compressor.ratio, range: 1...20, format: "%.1f : 1")
            slider("Knee Radius", \.compressor.kneeRadius, range: 1...10, format: "%.1f dB")
            slider("Makeup Gain", \.compressor.makeupGain, range: 0...24, format: "%.1f dB")
        case .spatializer:
            // 536:1708: values shown ×10 (536:1715 "8.0"); one tick per 0.1 of VLC's range.
            slider("Size", \.spatializer.roomSize, range: 0...1.1, format: "%.1f", scale: 10, stops: 12)
            slider("Width", \.spatializer.width, range: 0...1, format: "%.1f", scale: 10, stops: 11)
            slider("Wet", \.spatializer.wet, range: 0...1, format: "%.1f", scale: 10, stops: 11)
            slider("Dry", \.spatializer.dry, range: 0...1, format: "%.1f", scale: 10, stops: 11)
            slider("Damp", \.spatializer.damp, range: 0...1, format: "%.1f", scale: 10, stops: 11)
        default:
            // 612:1228; the gains are VLC's 0–1 factors (D048: Figma's "%" is not their unit).
            slider("Delay Time", \.stereoWidener.delay, range: 1...100, format: "%.1f ms")
            slider("Feedback Gain", \.stereoWidener.feedback, range: 0...0.9, format: "%.1f", stops: 10)
            slider("Crossfeed", \.stereoWidener.crossfeed, range: 0...0.8, format: "%.1f", stops: 9)
            slider("Dry Mix", \.stereoWidener.dryMix, range: 0...1, format: "%.1f", stops: 11)
        }
    }

    // 6114:13615: Preamp and the ten bands, each a value field over its slider.
    @ViewBuilder private var equalizer: some View {
        PanelCardFieldSliderRow(title: "Preamp", value: String(format: "%.1f dB", audio.effects.equalizer.preamp),
                                commit: { text in if let number = panelNumber(text) { audio.setEqualizerPreamp(number) } },
                                number: Binding(get: { audio.effects.equalizer.preamp }, set: { audio.setEqualizerPreamp($0) }),
                                range: -20...20, step: 0.1)
        ForEach(EqualizerSettings.bandLabels.indices, id: \.self) { index in
            let value = audio.effects.equalizer.bands.indices.contains(index) ? audio.effects.equalizer.bands[index] : 0
            PanelCardFieldSliderRow(title: EqualizerSettings.bandLabels[index], value: String(format: "%.1f dB", value),
                                    commit: { text in if let number = panelNumber(text) { audio.setEqualizerBand(index, gain: number) } },
                                    number: Binding(get: { value }, set: { audio.setEqualizerBand(index, gain: $0) }),
                                    range: -20...20, step: 0.1)
        }
    }

    private func slider(_ title: String, _ path: WritableKeyPath<AudioEffects, Double>, range: ClosedRange<Double>,
                        format: String, scale: Double = 1, stops: Int? = nil) -> some View {
        PanelCardSliderRow(title: title, value: String(format: format, audio.effects[keyPath: path] * scale),
                           number: Binding(get: { audio.effects[keyPath: path] },
                                           set: { value in audio.update { $0[keyPath: path] = min(max(value, range.lowerBound), range.upperBound) } }),
                           range: range, stops: stops)
    }
}
