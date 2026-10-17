import MXRCore
import MXRDesign
import SwiftUI

/// S68: the profile submenu, with native naming alerts and context actions. From the menu bar
/// (Profile ▸ Manage Profiles) it is shown as a small in-window card that closes like a menu:
/// after a choice, on Esc, ⌘W or a click outside (SD-15).
public struct MXRProfilesView: View {
    @Environment(AppModel.self) private var app
    @Environment(ProfileStore.self) private var profiles
    @State private var namingProfile: Profile?
    @State private var proposedName = ""
    @State private var isNaming = false
    @State private var hoveredID: String?
    /// The profile waiting for Delete to be confirmed (D035: destructive actions ask first).
    @State private var deleting: Profile?

    public init() {}
    public static var preferredSize: CGSize { Theme.Metric.Menus.profilesSubmenu.size }

    public var body: some View {
        let box = Theme.Metric.Menus.profilesSubmenu
        ViewThatFits(in: .vertical) {
            profileRows
            ScrollView(.vertical) { profileRows }
                .scrollIndicators(.automatic)
        }
        .padding(box.padding.edgeInsets)
        .frame(width: box.width)
        .background { MXRBackdropSurface(tint: Theme.Color.bgA3Transparent,
                                         cornerRadius: box.radius ?? Theme.Radius.lg) }
        .customizationShadow(Theme.Effect.menuShadow, cornerRadius: box.radius ?? Theme.Radius.lg)
        .alert(namingProfile == nil ? "New Profile" : "Rename Profile", isPresented: $isNaming) {
            TextField("Profile name", text: $proposedName)
            Button("Cancel", role: .cancel) {}
            Button(namingProfile == nil ? "Create" : "Save") {
                _ = MXRProfileEditing.save(name: proposedName, replacing: namingProfile, in: app)
            }
            .disabled(app.interface.isCustomizing || proposedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .alert("Delete Profile “\(deleting?.name ?? "")”?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
               presenting: deleting) { profile in
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { _ = MXRProfileEditing.delete(profile, in: app) }
        } message: { _ in
            Text("Its settings and player layout are removed.")
        }
    }

    private var profileRows: some View {
        VStack(spacing: 0) {
            ForEach(profiles.profiles) { profile in
                profileRow(profile)
            }
            Rectangle().fill(Theme.Color.dividerDim).frame(height: Theme.Stroke.hairline)
            Button {
                guard !app.interface.isCustomizing else { return }
                namingProfile = nil
                proposedName = ""
                isNaming = true
            } label: {
                rowLabel(icon: .add, title: "New")
            }
            .buttonStyle(.plain)
            .disabled(app.interface.isCustomizing)
            .accessibilityLabel("New profile")
        }
    }

    private func profileRow(_ profile: Profile) -> some View {
        Button {
            guard MXRProfileEditing.select(profile, in: app) else { return }
            if app.interface.sheet == .profiles { app.interface.dismissSheet() }
        } label: {
            rowLabel(icon: .check, title: profile.name, selected: profile.id == profiles.currentID)
                .background {
                    if profile.id == profiles.currentID || hoveredID == profile.id {
                        RoundedRectangle(cornerRadius: Theme.Metric.Menus.contextMenuRow.radius ?? Theme.Radius.lg)
                            .fill(Theme.Color.bgA2)
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(app.interface.isCustomizing)
        .onHover { hoveredID = $0 ? profile.id : nil }
        .accessibilityLabel(profile.name)
        .accessibilityAddTraits(profile.id == profiles.currentID ? .isSelected : [])
        .mxrContextMenu(style: .contextMenu) {
            MXRMenuItem("Rename…", isEnabled: !app.interface.isCustomizing) {
                guard !app.interface.isCustomizing else { return }
                namingProfile = profile
                proposedName = profile.name
                isNaming = true
            }
            MXRMenuItem("Delete…", isEnabled: !app.interface.isCustomizing && profiles.profiles.count > 1) {
                deleting = profile
            }
        }
        .accessibilityAction(named: "Rename") {
            guard !app.interface.isCustomizing else { return }
            namingProfile = profile
            proposedName = profile.name
            isNaming = true
        }
        .accessibilityAction(named: "Delete") {
            guard !app.interface.isCustomizing, profiles.profiles.count > 1 else { return }
            deleting = profile
        }
    }

    private func rowLabel(icon: MXRIcon.Name, title: String, selected: Bool = false) -> some View {
        let row = Theme.Metric.Menus.contextMenuRow
        return HStack(spacing: row.gap) {
            MXRIcon(icon, state: selected ? .active : .default)
            Text(title).mxrTextStyle(.body).foregroundStyle(Theme.Color.fgA1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Color.clear.frame(width: Theme.Metric.iconSize)
        }
        .padding(row.padding.edgeInsets)
        .frame(height: row.height)
        .contentShape(Rectangle())
    }
}

enum MXRProfileEditing {
    @MainActor @discardableResult
    static func select(_ profile: Profile, in app: AppModel) -> Bool {
        guard !app.interface.isCustomizing else { return false }
        app.profiles.select(profile)
        return true
    }

    @MainActor @discardableResult
    static func delete(_ profile: Profile, in app: AppModel) -> Bool {
        guard !app.interface.isCustomizing, app.profiles.profiles.count > 1 else { return false }
        app.profiles.delete(profile)
        app.layouts.removeLayouts(profileID: profile.id)
        return true
    }

    @MainActor @discardableResult
    static func save(name: String, replacing profile: Profile?, in app: AppModel) -> Profile? {
        guard !app.interface.isCustomizing else { return nil }
        return save(name: name, replacing: profile, in: app.profiles)
    }

    @MainActor @discardableResult
    static func save(name: String, replacing profile: Profile?, in store: ProfileStore) -> Profile? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        if let profile {
            store.rename(profile, to: name)
            return store.profiles.first { $0.id == profile.id }
        }
        let created = store.create(name: name)
        store.select(created)
        return created
    }
}
