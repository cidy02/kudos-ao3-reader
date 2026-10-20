package io.github.cidy02.kudos.reader

import android.util.Base64
import android.webkit.WebView
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import io.github.cidy02.kudos.core.model.CustomFont
import io.github.cidy02.kudos.core.model.KudosSettings
import io.github.cidy02.kudos.core.model.ReaderFontCatalog
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.files.CustomFontRepository
import io.github.cidy02.kudos.reader.settings.ReaderColorTheme
import io.github.cidy02.kudos.reader.settings.ReaderSettingsMapper
import io.github.cidy02.kudos.settings.SettingsActionRow
import io.github.cidy02.kudos.settings.SettingsSection
import io.github.cidy02.kudos.settings.SubjectSliderRow
import io.github.cidy02.kudos.ui.subject.KudosTokens
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.LocalSubjectPalette
import io.github.cidy02.kudos.ui.subject.ReaderTheme
import io.github.cidy02.kudos.ui.subject.SectionRuleHeader
import io.github.cidy02.kudos.ui.subject.SubjectFormRow
import io.github.cidy02.kudos.ui.subject.SubjectRowSeparator
import io.github.cidy02.kudos.ui.subject.SubjectSegmentedControl
import io.github.cidy02.kudos.ui.subject.SubjectToggle
import io.github.cidy02.kudos.ui.subject.ToolbarCircleButton
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Both Customize Theme entries use this sheet and the same saved reader preferences. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun CustomizeThemeSheet(
    repository: SettingsRepository,
    customFontRepository: CustomFontRepository? = null,
    onDismiss: () -> Unit
) {
    val settings by repository.settings.collectAsState(initial = KudosSettings.Defaults)
    val fonts by remember(customFontRepository) {
        customFontRepository?.observeImported() ?: flowOf(emptyList<CustomFont>())
    }.collectAsState(initial = emptyList())
    val scope = rememberCoroutineScope()
    val reader = settings.reader
    val theme = ReaderSettingsMapper().resolveTheme(reader, settings.app)
    val tokens = KudosTokens.of(ReaderTheme.valueOf(theme.name), LocalKudosTokens.current.accent)
    var choosingFont by remember { mutableStateOf(false) }
    val selectedFont = fonts.firstOrNull { it.selectionId == reader.readerFontId }
    // Embed the selected local font; the preview has no file/content or network access.
    val fontData by produceState<String?>(null, selectedFont?.fileName, customFontRepository) {
        value = withContext(Dispatchers.IO) {
            selectedFont?.let { font -> runCatching {
                val bytes = java.nio.file.Files.readAllBytes(checkNotNull(customFontRepository).fontPath(font.fileName))
                val type = if (font.fileName.endsWith(".otf", true)) "otf" else "ttf"
                "data:font/$type;base64," + Base64.encodeToString(bytes, Base64.NO_WRAP)
            }.getOrNull() }
        }
    }
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = tokens.background,
        contentColor = tokens.primaryInk
    ) {
        CompositionLocalProvider(LocalKudosTokens provides tokens, LocalSubjectPalette provides tokens.scopePalette) {
            Column(Modifier.fillMaxWidth().fillMaxHeight(0.95f).navigationBarsPadding()) {
                Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp), verticalAlignment = Alignment.CenterVertically) {
                    if (choosingFont) TextButton(onClick = { choosingFont = false }) { Text("Back") }
                    Text(if (choosingFont) "Font" else "Customize Theme", color = tokens.primaryInk,
                        fontSize = 17.sp, modifier = Modifier.weight(1f))
                    ToolbarCircleButton(onClick = onDismiss, accessibilityName = "Done") {
                        Icon(Icons.Filled.Check, contentDescription = null, tint = tokens.scopePalette.accent)
                    }
                }
                if (choosingFont) {
                    Column(Modifier.weight(1f).verticalScroll(rememberScrollState())) {
                        SettingsSection(label = "Font", footnote = null) {
                            ReaderFontCatalog.options(fonts).forEachIndexed { index, option ->
                                if (index > 0) SubjectRowSeparator()
                                SubjectFormRow(option.name,
                                    onClick = {
                                        scope.launch { repository.updateReaderFontId(option.id) }
                                        choosingFont = false
                                    },
                                    trailing = {
                                        if (reader.readerFontId == option.id) Icon(Icons.Filled.Check,
                                            contentDescription = "Selected", tint = tokens.scopePalette.accent)
                                    })
                            }
                        }
                    }
                } else {
                    val windowHeight = LocalConfiguration.current.screenHeightDp
                    // Leave room for reachable form rows in Android's compact landscape window.
                    val previewHeight = if (windowHeight < 600) (windowHeight * 0.28f).dp
                        else (windowHeight * 0.42f).coerceIn(240f, 380f).dp
                    val html = readerThemePreviewHTML(settings, fontData)
                    AndroidView(
                        factory = { context -> WebView(context).apply {
                            this.settings.javaScriptEnabled = false
                            this.settings.allowFileAccess = false
                            this.settings.allowContentAccess = false
                            this.settings.blockNetworkLoads = true
                            isVerticalScrollBarEnabled = false
                            isHorizontalScrollBarEnabled = false
                        } },
                        update = { web ->
                            if (web.tag != html) {
                                web.tag = html
                                web.loadDataWithBaseURL(null, html, "text/html", "UTF-8", null)
                            }
                        },
                        onReset = null,
                        onRelease = { it.destroy() },
                        modifier = Modifier.fillMaxWidth().height(previewHeight).padding(horizontal = 20.dp, vertical = 10.dp)
                    )
                    SubjectSegmentedControl(
                        options = ReaderColorTheme.entries, selected = theme,
                        onSelect = { scope.launch {
                            repository.updateEffectiveReaderTheme(ReaderSettingsMapper.toReaderThemeSetting(it))
                        } },
                        title = { if (it == ReaderColorTheme.Oled) "OLED" else it.name },
                        contentDescription = "Theme",
                        modifier = Modifier.padding(horizontal = 20.dp, vertical = 10.dp)
                    )
                    Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(bottom = 24.dp)) {
                        SectionRuleHeader("Text", Modifier.padding(horizontal = 20.dp, vertical = 10.dp))
                        SettingsSection(footnote = null, top = 0.dp) {
                            SubjectFormRow("Font", value = ReaderFontCatalog.name(reader.readerFontId, fonts),
                                onClick = { choosingFont = true })
                            SubjectRowSeparator()
                            SubjectFormRow("Bold Text", trailing = {
                                SubjectToggle(reader.readerBoldText,
                                    onCheckedChange = { scope.launch { repository.updateReaderBoldText(it) } },
                                    contentDescription = "Bold Text")
                            })
                        }
                        SectionRuleHeader("Accessibility & Layout", Modifier.padding(horizontal = 20.dp, vertical = 10.dp))
                        SettingsSection(top = 0.dp,
                            footnote = "Turn Customize off to use comfortable defaults. Your Bold Text and font choices still apply.") {
                            SubjectFormRow("Customize", trailing = {
                                SubjectToggle(reader.readerCustomize,
                                    onCheckedChange = { scope.launch { repository.updateReaderCustomize(it) } },
                                    contentDescription = "Customize")
                            })
                            SubjectRowSeparator()
                            ThemeSlider("Line Spacing", reader.readerLineHeight, 1.2f..2.4f, reader.readerCustomize) {
                                scope.launch { repository.updateReaderLineHeight(it) }
                            }
                            SubjectRowSeparator()
                            ThemeSlider("Character Spacing", reader.readerLetterSpacing, 0f..0.12f, reader.readerCustomize) {
                                scope.launch { repository.updateReaderLetterSpacing(it) }
                            }
                            SubjectRowSeparator()
                            ThemeSlider("Word Spacing", reader.readerWordSpacing, 0f..0.6f, reader.readerCustomize) {
                                scope.launch { repository.updateReaderWordSpacing(it) }
                            }
                            SubjectRowSeparator()
                            ThemeSlider("Margins", reader.readerMargin, 8f..64f, reader.readerCustomize) {
                                scope.launch { repository.updateReaderMargin(it) }
                            }
                            SubjectRowSeparator()
                            SubjectFormRow("Justify Text", trailing = {
                                SubjectToggle(reader.readerJustify, enabled = reader.readerCustomize,
                                    onCheckedChange = { scope.launch { repository.updateReaderJustify(it) } },
                                    contentDescription = "Justify Text")
                            })
                        }
                        SettingsSection(footnote = null) {
                            SettingsActionRow("Reset Theme", destructive = true,
                                onClick = { scope.launch { repository.resetReaderTheme() } })
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun ThemeSlider(label: String, value: Double, range: ClosedFloatingPointRange<Float>,
                        enabled: Boolean, onChange: (Double) -> Unit) {
    SubjectSliderRow(label, value.toFloat().coerceIn(range), range, steps = 0,
        formatValue = { "%.2f".format(it) }, onValueChangeFinished = {}, enabled = enabled,
        onValueChange = { onChange(it.toDouble()) })
}
