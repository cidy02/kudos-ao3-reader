import SwiftUI

/// Artboard **1ab**'s "Keep screen awake": while a book is open, stop iOS
/// dimming and locking the screen.
///
/// Reading is the one thing this app does where the reader can go minutes
/// without touching the screen, which is exactly what the idle timer counts as
/// idle. Applied at `BookReaderView` — the single place that chooses between
/// the two readers — so it covers both without either knowing about it.
///
/// The flag is process-wide and nothing else in the app touches it, so this
/// owns it outright: set on the way in, cleared on the way out, and kept in
/// step if the reader changes the setting while a book is open.
struct KeepScreenAwakeModifier: ViewModifier {
    @AppStorage("keepScreenAwake") private var keepScreenAwake = false

    func body(content: Content) -> some View {
        content
            #if os(iOS)
            .onAppear { apply(keepScreenAwake) }
            .onDisappear { apply(false) }
            .onChange(of: keepScreenAwake) { _, isOn in apply(isOn) }
            #endif
    }

    #if os(iOS)
    private func apply(_ isOn: Bool) {
        UIApplication.shared.isIdleTimerDisabled = isOn
    }
    #endif
}

extension View {
    /// Keeps the screen lit while this view is on screen, if the reader asked
    /// for it in Settings. No-op on macOS, which has no idle timer to disable.
    func keepScreenAwakeWhileReading() -> some View {
        modifier(KeepScreenAwakeModifier())
    }
}
