package io.github.cidy02.kudos.app

import java.io.File
import javax.xml.parsers.DocumentBuilderFactory
import org.junit.Assert.assertEquals
import org.junit.Test

class PredictiveBackManifestTest {
    @Test fun theApplicationExplicitlyOptsInAndNoActivityOptsOut() {
        val manifest = listOf(File("src/main/AndroidManifest.xml"), File("app/src/main/AndroidManifest.xml"),
            File("android/app/src/main/AndroidManifest.xml")).first { it.isFile }
        val factory = DocumentBuilderFactory.newInstance().apply { isNamespaceAware = true }
        val document = factory.newDocumentBuilder().parse(manifest)
        val android = "http://schemas.android.com/apk/res/android"
        val application = document.getElementsByTagName("application").item(0) as org.w3c.dom.Element
        assertEquals("true", application.getAttributeNS(android, "enableOnBackInvokedCallback"))
        val activities = document.getElementsByTagName("activity")
        for (index in 0 until activities.length) {
            val activity = activities.item(index) as org.w3c.dom.Element
            val activityFlag = activity.getAttributeNS(android, "enableOnBackInvokedCallback")
            assertEquals("An activity must not disable the application's back callbacks", true,
                activityFlag.isEmpty() || activityFlag == "true")
        }
    }
}
