import AppKit
import MXRCore
import MXRDesign
import SwiftUI
import UniformTypeIdentifiers

struct SettingsExtensionsView: View {
    @Environment(ExtensionsModel.self) private var extensions
    @State private var searchText = ""
    @State private var showsCatalog = false
    @State private var message: String?
    @State private var isWorking = false

    private var filteredExtensions: [ExtensionInfo] {
        extensions.extensions.filter { searchText.isEmpty || $0.title.localizedCaseInsensitiveContains(searchText) || ($0.summary?.localizedCaseInsensitiveContains(searchText) ?? false) }
    }

    private var isBusy: Bool { isWorking || extensions.isSearching }
    private var selectedExtension: ExtensionInfo? { extensions.extensions.first { $0.id == extensions.selection } }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: Theme.Spacing.gap2) {
                    ForEach(filteredExtensions) { item in
                        let activation = extensions.availability(for: .activate, extensionID: item.id)
                        let running = extensions.availability(for: .run, extensionID: item.id)
                        HStack(spacing: Theme.Spacing.gap10) {
                            Button { extensions.selection = item.id } label: {
                                VStack(alignment: .leading, spacing: Theme.Spacing.gap4) {
                                    Text(item.title).mxrTextStyle(Theme.Font.body).foregroundStyle(Theme.Color.fgA1)
                                    if let summary = item.summary { Text(summary).mxrTextStyle(Theme.Font.caption).foregroundStyle(Theme.Color.fgA3).lineLimit(1) }
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(.plain)
                            if running.isAvailable {
                                SettingsButton(title: "Run") { runExtension(item) }
                                    .disabled(isBusy)
                                    .accessibilityLabel("Run \(item.title)")
                                    .help("Run \(item.title) once")
                            } else if activation.isAvailable {
                                SettingsToggle(isOn: Binding(get: { item.isActivated }, set: { extensions.setActivated($0, item) }), label: "Enable \(item.title)")
                                    .disabled(isBusy)
                                    .help("Enable \(item.title)")
                            }
                            // D035/D045: a script the engine can neither enable nor run is listed for
                            // removal only, with no dead control.
                        }
                        .padding(Theme.Spacing.gap8)
                        .background(extensions.selection == item.id ? Theme.Color.bgA3 : Theme.Color.bgB2,
                                    in: .rect(cornerRadius: Theme.Radius.md))
                    }
                }.padding(Theme.Spacing.gap5)
            }
            .frame(maxWidth: .infinity)
            .frame(height: Theme.Metric.SettingsDetail.extensionsHeight)
            .background(Theme.Color.bgB2, in: .rect(cornerRadius: Theme.Radius.lg))
            .overlay { RoundedRectangle(cornerRadius: Theme.Radius.lg).strokeBorder(Theme.Color.bgA4, lineWidth: Theme.Spacing.gap2) }
            ScrollView(.horizontal) {
                HStack(spacing: Theme.Spacing.gap10) {
                    TextField("Search", text: $searchText, prompt: Text("Search").foregroundStyle(Theme.Color.fgA4))
                        .textFieldStyle(.plain).mxrTextStyle(Theme.Font.body).foregroundStyle(Theme.Color.fgA2)
                        .padding(.leading, Theme.Spacing.gap14).padding(.trailing, Theme.Metric.SettingsDetail.inputTrailingPadding + Theme.Spacing.gap2)
                        .frame(
                            width: Theme.Metric.SettingsDetail.controlWidth - Theme.Metric.buttonWidth - Theme.Spacing.gap10,
                            height: Theme.Metric.SettingsDetail.controlHeight
                        )
                        .background(Theme.Color.bgB2, in: .rect(cornerRadius: Theme.Radius.lg))
                        .overlay { RoundedRectangle(cornerRadius: Theme.Radius.lg).strokeBorder(Theme.Color.bgA4, lineWidth: Theme.Spacing.gap2) }
                        .accessibilityLabel("Search installed extensions")
                    Spacer(minLength: 0)
                    // D035: an operation this build cannot perform is not shown at all.
                    if extensions.availability(for: .searchCatalog).isAvailable {
                        SettingsButton(title: "Find more extensions", width: Theme.Metric.SettingsDetail.extensionsCatalogButtonWidth) {
                            showsCatalog = true
                        }
                        .disabled(isBusy)
                        .help("Search the online extension catalog")
                        .mxrPopup(isPresented: $showsCatalog, placement: .above(), surface: .contextMenu) {
                            ExtensionCatalogPanel(extensions: extensions, initialSearch: searchText)
                        }
                    }
                    if extensions.availability(for: .installLocal).isAvailable {
                        SettingsButton(title: "Add", action: addLocalExtension)
                            .disabled(isBusy)
                            .help("Add a local Lua extension")
                    }
                    if extensions.availability(for: .removeLocal).isAvailable {
                        // Disabled only while nothing removable is selected.
                        SettingsButton(title: "Remove", action: removeSelected)
                            .disabled(selectedExtension == nil || !canPerform(.removeLocal, id: selectedExtension?.id))
                            .help(selectedExtension == nil ? "Select an installed extension to remove" : "Remove the selected extension")
                    }
                }
                .frame(
                    width: Theme.Metric.Dialogs.settingsContent.width - Theme.Metric.Dialogs.settingsContent.padding.leading
                        - Theme.Metric.Dialogs.settingsContent.padding.trailing, height: Theme.Metric.Dialogs.advancedOptionsBar.height)
            }
            .frame(height: Theme.Metric.Dialogs.advancedOptionsBar.height)
            .padding(.top, Theme.Spacing.gap5).padding(.bottom, Theme.Spacing.gap10)
            if let message = message ?? extensions.actionError { Text(message).mxrTextStyle(Theme.Font.body).foregroundStyle(Theme.Color.fgA1).frame(maxWidth: .infinity, alignment: .leading) }
        }
        .frame(maxWidth: .infinity)
    }

    private func addLocalExtension() {
        guard permit(.installLocal) else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.init(filenameExtension: "lua") ?? .plainText]
        if panel.runModal() == .OK, let url = panel.url {
            isWorking = true
            Task {
                defer { isWorking = false }
                do { try await extensions.installExtension(at: url); message = "Added \(url.lastPathComponent)." }
                catch { message = error.localizedDescription }
            }
        }
    }

    private func removeSelected() {
        guard let item = selectedExtension, permit(.removeLocal, id: item.id) else { return }
        isWorking = true
        Task {
            defer { isWorking = false }
            do { try await extensions.removeExtension(item); extensions.selection = nil; message = "Removed \(item.title)." }
            catch { message = error.localizedDescription }
        }
    }

    private func runExtension(_ item: ExtensionInfo) {
        guard permit(.run, id: item.id) else { return }
        isWorking = true
        Task {
            defer { isWorking = false }
            do { try await extensions.runExtension(item); message = "Started \(item.title)." }
            catch { message = error.localizedDescription }
        }
    }

    private func canPerform(_ operation: ExtensionOperation, id: String? = nil) -> Bool {
        !isBusy && extensions.availability(for: operation, extensionID: id).isAvailable
    }

    private func permit(_ operation: ExtensionOperation, id: String? = nil) -> Bool {
        guard !isBusy else { return false }
        if let reason = extensions.availability(for: operation, extensionID: id).reason { message = reason; return false }
        return true
    }
}

/// "Find more extensions": the online catalog in a design popup (D024, no arrow). It owns its
/// own search and progress, since a popup's content is built once when it opens.
private struct ExtensionCatalogPanel: View {
    let extensions: ExtensionsModel
    @State private var searchText: String
    @State private var message: String?
    @State private var isWorking = false

    init(extensions: ExtensionsModel, initialSearch: String) {
        self.extensions = extensions
        _searchText = State(initialValue: initialSearch)
    }

    private var isBusy: Bool { isWorking || extensions.isSearching }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.gap14) {
            Text("Find more extensions").mxrTextStyle(Theme.Font.sectionHeader).foregroundStyle(Theme.Color.fg2)
            HStack {
                SettingsSearch(text: $searchText)
                    .onSubmit(search)
                SettingsButton(title: "Search", action: search).disabled(isBusy)
            }
            if let message { Text(message).mxrTextStyle(Theme.Font.body).foregroundStyle(Theme.Color.fgA1) }
            if let error = extensions.catalogError { Text(error).mxrTextStyle(Theme.Font.body).foregroundStyle(Theme.Color.fgA1) }
            if isBusy { ProgressView().frame(maxWidth: .infinity) }
            else if extensions.catalogError != nil { EmptyView() }
            else if extensions.addonResults.isEmpty {
                Text("No add-ons found. Try another search.").mxrTextStyle(Theme.Font.body).foregroundStyle(Theme.Color.fgA1)
            }
            ScrollView {
                VStack(spacing: Theme.Spacing.gap14) {
                    ForEach(extensions.addonResults) { addon in
                        let operation: ExtensionOperation = addon.isInstalled ? .removeAddon : .installAddon
                        HStack(spacing: Theme.Spacing.gap10) {
                            VStack(alignment: .leading, spacing: Theme.Spacing.gap4) {
                                Text(addon.name).mxrTextStyle(Theme.Font.body).foregroundStyle(Theme.Color.fgA1)
                                Text(addon.summary).mxrTextStyle(Theme.Font.caption).foregroundStyle(Theme.Color.fgA3)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            if extensions.availability(for: operation, extensionID: addon.id).isAvailable {
                                SettingsButton(title: addon.isInstalled ? "Remove" : "Install") { toggleInstall(addon) }
                                    .disabled(isBusy)
                                    .help(addon.isInstalled ? "Remove \(addon.name)" : "Install \(addon.name)")
                            }
                        }
                    }
                }
            }.frame(height: Theme.Metric.SettingsDetail.extensionsHeight)
        }
        .padding(Theme.Spacing.gap20)
        .frame(width: Theme.Metric.Dialogs.settingsContent.width)
        .task { await extensions.searchAddons(searchText) }
    }

    private func search() {
        guard !isBusy else { return }
        isWorking = true
        Task {
            defer { isWorking = false }
            await extensions.searchAddons(searchText)
        }
    }

    private func toggleInstall(_ addon: AddonInfo) {
        guard !isBusy else { return }
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                if addon.isInstalled { try await extensions.remove(addon) }
                else { try await extensions.install(addon) }
                message = "\(addon.isInstalled ? "Removed" : "Installed") \(addon.name)."
                await extensions.searchAddons(searchText)
            } catch { message = error.localizedDescription }
        }
    }
}
