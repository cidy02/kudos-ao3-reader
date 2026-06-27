package io.github.cidy02.kudos

import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.fragment.app.FragmentActivity
import io.github.cidy02.kudos.app.KudosApp

// FragmentActivity (not bare ComponentActivity) so Readium's Fragment-based EPUB
// navigator can be hosted via supportFragmentManager (see ReadiumNavigatorHost).
class MainActivity : FragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val container = (application as KudosApplication).container
        setContent {
            KudosApp(container = container)
        }
    }
}
