package io.github.cidy02.kudos.reader

import android.app.Application
import android.os.Bundle
import androidx.fragment.app.FragmentActivity
import io.github.cidy02.kudos.reader.readium.ReaderFragmentRestore
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.readium.r2.navigator.epub.EpubNavigatorFragment
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class)
class ReaderFragmentRestoreTest {
    class Host : FragmentActivity() {
        override fun onCreate(savedInstanceState: Bundle?) {
            if (guarded) ReaderFragmentRestore.before(this)
            super.onCreate(savedInstanceState)
            if (guarded) ReaderFragmentRestore.after(this, savedInstanceState)
        }
    }

    /**
     * Readium's dummy stands for the open reader: it is the same class, and all a restart keeps
     * of a fragment is its class. It is added before the activity resumes because the dummy
     * refuses to be resumed, which is Readium's own rule for it.
     */
    private fun restartWithTheReaderOpen(): FragmentActivity {
        val first = Robolectric.buildActivity(Host::class.java).create()
        val fm = first.get().supportFragmentManager
        fm.fragmentFactory = EpubNavigatorFragment.createDummyFactory()
        fm.beginTransaction().add(EpubNavigatorFragment::class.java, null, "reader").commitNow()
        assertEquals(1, fm.fragments.size)
        val state = Bundle().also { first.saveInstanceState(it) }
        return Robolectric.buildActivity(Host::class.java).create(state).start().resume().get()
    }

    @Test fun aRestartWithTheReaderOpenRebuildsNothingForComposeToTripOver() {
        guarded = true
        assertTrue(restartWithTheReaderOpen().supportFragmentManager.fragments.isEmpty())
    }

    /** What the app did: Android cannot build Readium's fragment by itself. */
    @Test fun withoutTheGuardTheRestartThrows() {
        guarded = false
        assertThrows(RuntimeException::class.java) { restartWithTheReaderOpen() }
    }

    private companion object { var guarded = true }
}
