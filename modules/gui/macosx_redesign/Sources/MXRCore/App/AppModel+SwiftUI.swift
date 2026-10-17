import SwiftUI

extension View {
    /// Injects the ``AppModel`` and every model it owns into the environment, so views can write
    /// `@Environment(PlayerModel.self) private var player`.
    public func appModel(_ app: AppModel) -> some View {
        self
            .environment(app)
            .environment(app.player)
            .environment(app.clock)
            .environment(app.queue)
            .environment(app.tracks)
            .environment(app.videoEffects)
            .environment(app.audioEffects)
            .environment(app.chapters)
            .environment(app.bookmarks)
            .environment(app.library)
            .environment(app.settings)
            .environment(app.shortcuts)
            .environment(app.osd)
            .environment(app.dialogs)
            .environment(app.extensions)
            .environment(app.seekPreview)
            .environment(app.interface)
            .environment(app.appearance)
            .environment(app.presets)
            .environment(app.recents)
            .environment(app.pins)
            .environment(app.profiles)
            .environment(app.layouts)
    }
}
