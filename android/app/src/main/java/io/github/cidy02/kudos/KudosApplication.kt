package io.github.cidy02.kudos

import android.app.Application
import io.github.cidy02.kudos.app.KudosAppContainer

class KudosApplication : Application() {
    lateinit var container: KudosAppContainer
        private set

    override fun onCreate() {
        super.onCreate()
        container = KudosAppContainer(this)
    }
}
