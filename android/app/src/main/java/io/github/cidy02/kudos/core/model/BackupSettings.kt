package io.github.cidy02.kudos.core.model

data class BackupSettings(
    val readerFontID: String = "system",
    val readerMode: String = ReaderMode.Scroll.storageValue,
    val readerTwoPage: Boolean = false,
    val readerCustomize: Boolean = false,
    val readerBoldText: Boolean = false,
    val readerFontPt: Double = 18.0,
    val readerLineHeight: Double = 1.65,
    val readerLetterSpacing: Double = 0.0,
    val readerWordSpacing: Double = 0.0,
    val readerMargin: Double = 28.0,
    val readerJustify: Boolean = false,
    val confirmBeforeDelete: Boolean = true,
    val hideMatureContent: Boolean = true,
    val matureContentMode: String = MatureContentMode.Obscure.storageValue,
    val requireBiometricToReveal: Boolean = false,
    val appTheme: String = AppThemeSetting.Light.storageValue,
    val readerTheme: String = ReaderThemeSetting.Light.storageValue,
    val matchAppReaderTheme: Boolean = true,
    val accentColorHex: String = "#990000"
) {
    fun toSettings(): KudosSettings {
        return KudosSettings(
            reader = ReaderSettings(
                readerFontId = readerFontID,
                readerMode = ReaderMode.fromStorage(readerMode),
                readerTwoPage = readerTwoPage,
                readerCustomize = readerCustomize,
                readerBoldText = readerBoldText,
                readerFontPt = readerFontPt,
                readerLineHeight = readerLineHeight,
                readerLetterSpacing = readerLetterSpacing,
                readerWordSpacing = readerWordSpacing,
                readerMargin = readerMargin,
                readerJustify = readerJustify,
                readerTheme = ReaderThemeSetting.fromStorage(readerTheme),
                matchAppReaderTheme = matchAppReaderTheme
            ),
            app = AppSettings(
                confirmBeforeDelete = confirmBeforeDelete,
                appTheme = AppThemeSetting.fromStorage(appTheme),
                accentColorHex = accentColorHex
            ),
            privacy = PrivacySettings(
                hideMatureContent = hideMatureContent,
                matureContentMode = MatureContentMode.fromStorage(matureContentMode),
                requireBiometricToReveal = requireBiometricToReveal
            )
        )
    }

    companion object {
        fun fromSettings(settings: KudosSettings): BackupSettings {
            return BackupSettings(
                readerFontID = settings.reader.readerFontId,
                readerMode = settings.reader.readerMode.storageValue,
                readerTwoPage = settings.reader.readerTwoPage,
                readerCustomize = settings.reader.readerCustomize,
                readerBoldText = settings.reader.readerBoldText,
                readerFontPt = settings.reader.readerFontPt,
                readerLineHeight = settings.reader.readerLineHeight,
                readerLetterSpacing = settings.reader.readerLetterSpacing,
                readerWordSpacing = settings.reader.readerWordSpacing,
                readerMargin = settings.reader.readerMargin,
                readerJustify = settings.reader.readerJustify,
                confirmBeforeDelete = settings.app.confirmBeforeDelete,
                hideMatureContent = settings.privacy.hideMatureContent,
                matureContentMode = settings.privacy.matureContentMode.storageValue,
                requireBiometricToReveal = settings.privacy.requireBiometricToReveal,
                appTheme = settings.app.appTheme.storageValue,
                readerTheme = settings.reader.readerTheme.storageValue,
                matchAppReaderTheme = settings.reader.matchAppReaderTheme,
                accentColorHex = settings.app.accentColorHex
            )
        }
    }
}
