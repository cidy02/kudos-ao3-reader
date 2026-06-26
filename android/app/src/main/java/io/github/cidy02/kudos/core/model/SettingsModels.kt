package io.github.cidy02.kudos.core.model

enum class ReaderMode(val storageValue: String) {
    Scroll("scroll"),
    Paged("paged");

    companion object {
        fun fromStorage(value: String?): ReaderMode {
            return entries.firstOrNull { it.storageValue == value } ?: Scroll
        }
    }
}

enum class ReaderThemeSetting(val storageValue: String) {
    Light("light"),
    Sepia("sepia"),
    Dark("dark");

    companion object {
        fun fromStorage(value: String?): ReaderThemeSetting {
            return entries.firstOrNull { it.storageValue == value } ?: Light
        }
    }
}

enum class AppThemeSetting(val storageValue: String) {
    Light("light"),
    Sepia("sepia"),
    Dark("dark"),
    System("system");

    companion object {
        fun fromStorage(value: String?): AppThemeSetting {
            return entries.firstOrNull { it.storageValue == value } ?: Light
        }
    }
}

enum class MatureContentMode(val storageValue: String) {
    Obscure("obscure"),
    Hide("hide");

    companion object {
        fun fromStorage(value: String?): MatureContentMode {
            return entries.firstOrNull { it.storageValue == value } ?: Obscure
        }
    }
}

data class ReaderSettings(
    val readerFontId: String = "system",
    val readerMode: ReaderMode = ReaderMode.Scroll,
    val readerTwoPage: Boolean = false,
    val readerCustomize: Boolean = false,
    val readerBoldText: Boolean = false,
    val readerFontPt: Double = 18.0,
    val readerLineHeight: Double = 1.65,
    val readerLetterSpacing: Double = 0.0,
    val readerWordSpacing: Double = 0.0,
    val readerMargin: Double = 28.0,
    val readerJustify: Boolean = false,
    val readerTheme: ReaderThemeSetting = ReaderThemeSetting.Light,
    val matchAppReaderTheme: Boolean = true
)

data class AppSettings(
    val confirmBeforeDelete: Boolean = true,
    val appTheme: AppThemeSetting = AppThemeSetting.Light,
    val accentColorHex: String = "#990000"
)

data class PrivacySettings(
    val hideMatureContent: Boolean = true,
    val matureContentMode: MatureContentMode = MatureContentMode.Obscure,
    val requireBiometricToReveal: Boolean = false
)

data class KudosSettings(
    val reader: ReaderSettings = ReaderSettings(),
    val app: AppSettings = AppSettings(),
    val privacy: PrivacySettings = PrivacySettings()
) {
    companion object {
        val Defaults = KudosSettings()
    }
}
