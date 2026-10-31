package io.github.cidy02.kudos.reader

import io.github.cidy02.kudos.ui.theme.ActiveAppAccent
import io.github.cidy02.kudos.ui.theme.SheetSystemBars
import io.github.cidy02.kudos.ui.theme.parseAccentColor
import io.github.cidy02.kudos.settings.SettingsGroupLabel
import androidx.compose.foundation.text.TextAutoSize
import android.util.Base64
import android.webkit.WebView
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
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
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalWindowInfo
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import io.github.cidy02.kudos.core.model.CustomFont
import io.github.cidy02.kudos.core.model.KudosSettings
import io.github.cidy02.kudos.core.model.ReaderFontCatalog
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.files.CustomFontRepository
import io.github.cidy02.kudos.reader.settings.backgroundColor
import io.github.cidy02.kudos.reader.settings.textColor
import io.github.cidy02.kudos.reader.settings.ReaderColorTheme
import io.github.cidy02.kudos.reader.settings.ReaderSettingsMapper
import io.github.cidy02.kudos.settings.SettingsActionRow
import io.github.cidy02.kudos.settings.SettingsSection
import io.github.cidy02.kudos.settings.SubjectSliderRow
import io.github.cidy02.kudos.ui.subject.KudosTokens
import io.github.cidy02.kudos.ui.subject.LocalSettingsFormGround
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.LocalSubjectPalette
import io.github.cidy02.kudos.ui.subject.ReaderTheme
import io.github.cidy02.kudos.ui.subject.SubjectFormRow
import io.github.cidy02.kudos.ui.subject.SubjectRowSeparator
import io.github.cidy02.kudos.ui.subject.SubjectToggle
import io.github.cidy02.kudos.ui.subject.ToolbarCircleButton
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Presentation is separate so the production content can be tested without a dialog window. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun CustomizeThemeSheet(repository: SettingsRepository, customFontRepository: CustomFontRepository? = null,
    onDismiss: () -> Unit) {
    val settings by repository.settings.collectAsState(initial = KudosSettings.Defaults)
    val theme = ReaderSettingsMapper().resolveTheme(settings.reader, settings.app)
    val tokens = customizeThemeTokens(theme, settings)
    ModalBottomSheet(onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = tokens.background, contentColor = tokens.primaryInk) {
        SheetSystemBars(tokens)
        CustomizeThemeContent(repository, customFontRepository, onDismiss)
    }
}

/** Both Customize Theme entries use this sheet and the same saved reader preferences. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun CustomizeThemeContent(
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
    val tokens = customizeThemeTokens(theme, settings)
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
        CompositionLocalProvider(LocalKudosTokens provides tokens, LocalSubjectPalette provides tokens.scopePalette,
            LocalSettingsFormGround provides true) {
            Column(Modifier.fillMaxWidth().fillMaxHeight(0.95f).navigationBarsPadding()) {
                Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp), verticalAlignment = Alignment.CenterVertically) {
                    if (choosingFont) TextButton(onClick = { choosingFont = false }) { Text("Back") }
                    Text(if (choosingFont) "Font" else "Customize Theme", color = tokens.primaryInk,
                        fontSize = 17.sp, modifier = Modifier.weight(1f))
                    ToolbarCircleButton(onClick = onDismiss, accessibilityName = "Done") {
                        Icon(Icons.Filled.Check, contentDescription = null, tint = tokens.scopePalette.controlInk)
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
                                            contentDescription = "Selected", tint = tokens.scopePalette.controlInk)
                                    })
                            }
                        }
                    }
                } else {
                    val windowHeight = with(LocalDensity.current) {
                        LocalWindowInfo.current.containerSize.height.toDp().value
                    }
                    // Leave room for reachable form rows in Android's compact landscape window.
                    val previewHeight = if (windowHeight < 600) (windowHeight * 0.28f).dp
                        else (windowHeight * 0.42f).coerceIn(240f, 380f).dp
                    val html = readerThemePreviewHTML(settings, fontData)
                    Box(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 10.dp)
                        .clip(androidx.compose.foundation.shape.RoundedCornerShape(16.dp))) {
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
                                web.settings.textZoom = 100
                                if (web.tag != html) {
                                    web.tag = html
                                    web.loadDataWithBaseURL(null, html, "text/html", "UTF-8", null)
                                }
                            },
                            onReset = null,
                            onRelease = { it.destroy() },
                            modifier = Modifier.fillMaxWidth().height(previewHeight)
                        )
                        Box(Modifier.fillMaxWidth().height(36.dp).align(Alignment.BottomCenter)
                            .background(Brush.verticalGradient(listOf(theme.backgroundColor().copy(alpha = 0f), theme.backgroundColor()))))
                    }
                    Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 10.dp),
                        horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.Top) {
                        ReaderColorTheme.entries.forEach { option ->
                            val selected = option == theme
                            val title = if (option == ReaderColorTheme.Oled) "OLED" else option.name
                            Column(Modifier.weight(1f)
                                .selectable(selected = selected, role = Role.RadioButton) {
                                    scope.launch { repository.updateEffectiveReaderTheme(ReaderSettingsMapper.toReaderThemeSetting(option)) }
                                }.semantics { contentDescription = title },
                                horizontalAlignment = Alignment.CenterHorizontally,
                                verticalArrangement = Arrangement.spacedBy(7.dp)) {
                                Box(Modifier.padding(4.dp).size(54.dp), contentAlignment = Alignment.Center) {
                                    Box(Modifier.size(54.dp).background(option.backgroundColor(), CircleShape)
                                        .border(if (selected) 3.dp else 1.dp,
                                            if (selected) tokens.accent else tokens.primaryInk.copy(alpha = 0.12f), CircleShape),
                                        contentAlignment = Alignment.Center) {
                                        Text("Aa", color = option.textColor(), fontSize = 18.sp,
                                            fontWeight = FontWeight.SemiBold, fontFamily = FontFamily.Serif,
                                            modifier = Modifier.clearAndSetSemantics {})
                                    }
                                    if (selected) Icon(Icons.Filled.Check, contentDescription = null,
                                        tint = tokens.scopePalette.labelOnTint,
                                        modifier = Modifier.align(Alignment.TopEnd).size(16.dp).background(tokens.scopePalette.tint, CircleShape))
                                }
                                Text(title, color = if (selected) tokens.primaryInk else tokens.secondaryInk,
                                    fontSize = 11.sp, fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
                                    maxLines = 1, autoSize = TextAutoSize.StepBased(minFontSize = 6.sp, maxFontSize = 11.sp),
                                    modifier = Modifier.clearAndSetSemantics {})
                            }
                        }
                    }
                    Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(bottom = 24.dp)) {
                        SettingsGroupLabel("Text", Modifier.padding(vertical = 10.dp))
                        SettingsSection(footnote = null, top = 0.dp) {
                            SubjectFormRow("Font", modifier = Modifier.testTag("Theme font row"),
                                value = ReaderFontCatalog.name(reader.readerFontId, fonts), showsDisclosure = true,
                                onClick = { choosingFont = true })
                            SubjectRowSeparator()
                            SubjectFormRow("Bold Text", trailing = {
                                SubjectToggle(reader.readerBoldText,
                                    onCheckedChange = { scope.launch { repository.updateReaderBoldText(it) } },
                                    contentDescription = "Bold Text")
                            })
                        }
                        SettingsGroupLabel("Accessibility & Layout", Modifier.padding(vertical = 10.dp))
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

@Composable
private fun ThemeSlider(label: String, value: Double, range: ClosedFloatingPointRange<Float>,
                        enabled: Boolean, onChange: (Double) -> Unit) {
    SubjectSliderRow(label, value.toFloat().coerceIn(range), range, steps = 0,
        formatValue = { "%.2f".format(it) }, onValueChangeFinished = {}, enabled = enabled,
        onValueChange = { onChange(it.toDouble()) })
}

internal fun customizeThemeTokens(theme: ReaderColorTheme, settings: KudosSettings): KudosTokens {
    val userAccent = settings.app.chosenAccentColorHex?.let(::parseAccentColor) ?: ActiveAppAccent.value
    return KudosTokens.of(ReaderTheme.valueOf(theme.name), userAccent)
}
