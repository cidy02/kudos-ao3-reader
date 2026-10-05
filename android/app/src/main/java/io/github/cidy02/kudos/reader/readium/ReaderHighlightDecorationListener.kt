package io.github.cidy02.kudos.reader.readium

import org.readium.r2.navigator.DecorableNavigator
import org.readium.r2.shared.ExperimentalReadiumApi

/** A handled decoration tap must not fall through to the chrome’s content-tap listener. */
@OptIn(ExperimentalReadiumApi::class)
internal class ReaderHighlightDecorationListener(
    private val onHighlightTap: (String) -> Unit
) : DecorableNavigator.Listener {
    override fun onDecorationActivated(event: DecorableNavigator.OnActivatedEvent): Boolean {
        if (event.group != ReadiumNavigatorController.DECORATION_GROUP_HIGHLIGHTS) return false
        onHighlightTap(event.decoration.id)
        // Consume stale ids too: openHighlight ignores them, without toggling chrome.
        return true
    }
}
