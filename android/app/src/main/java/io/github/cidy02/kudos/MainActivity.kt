package io.github.cidy02.kudos

import android.content.Intent
import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.fragment.app.FragmentActivity
import io.github.cidy02.kudos.app.KudosApp
import io.github.cidy02.kudos.works.ExternalFileImport

// FragmentActivity (not bare ComponentActivity) so Readium's Fragment-based EPUB
// navigator can be hosted via supportFragmentManager (see ReadiumNavigatorHost).
class MainActivity : FragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        // "Open with Kudos" / "Share to Kudos" — the manifest advertises these
        // mime types, so something has to actually read the incoming Intent.
        ExternalFileImport.offer(intent)
        val container = (application as KudosApplication).container
        setContent {
            KudosApp(container = container)
        }
    }

    // Already-running app: a second "Open with" arrives here, not in onCreate.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        ExternalFileImport.offer(intent)
    }
}
