/// Offers onboarding once at startup, and owns only the sheet it presented.
/// File panels and incoming media take precedence over that automatic offer.
struct MXRFirstLaunchOnboarding {
    enum Sheet { case none, onboarding, other }
    enum Action { case none, present, dismiss }

    struct State {
        var needsOnboarding: Bool
        var hasMediaOrQueue: Bool
        var hasFileRequest: Bool
        var sheet: Sheet
        var hasNativeSheet: Bool
    }

    private var evaluatedStartup = false
    private var ownsSheet = false

    mutating func update(_ state: State) -> Action {
        if ownsSheet {
            guard state.sheet == .onboarding else {
                ownsSheet = false
                return .none
            }
            if state.hasMediaOrQueue || state.hasFileRequest {
                ownsSheet = false
                return .dismiss
            }
            return .none
        }
        guard !evaluatedStartup else { return .none }
        evaluatedStartup = true
        guard state.needsOnboarding, !state.hasMediaOrQueue,
              !state.hasFileRequest, state.sheet == .none,
              !state.hasNativeSheet else { return .none }
        ownsSheet = true
        return .present
    }
}
