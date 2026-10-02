package io.github.cidy02.kudos.ui.subject

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.FilterList
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.Icon
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.ui.theme.DefaultAccentHex
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode

/** Debug catalog. Replaced by an empty stub in release builds. */
@Composable
fun DebugDestination(route: String?): Boolean {
    if (route != DebugRoutes.DESIGN_CATALOG) return false
    DesignCatalogScreen()
    return true
}

private val CatalogModes = listOf(
    KudosThemeMode.Light,
    KudosThemeMode.Dark,
    KudosThemeMode.Oled,
    KudosThemeMode.Sepia
)

private val PickedCatalogColor = Color(0xFFC47A8A)
private const val CatalogHue = 38.0 / 360.0

@Composable
fun DesignCatalogScreen() {
    var mode by remember { mutableStateOf(KudosThemeMode.Dark) }
    KudosTheme(themeMode = mode, accentColorHex = DefaultAccentHex) {
        val tokens = LocalKudosTokens.current
        val scope = LocalSubjectPalette.current
        val huePalette = remember(tokens.theme) { SubjectPalette.fromHue(CatalogHue, tokens.theme) }
        val pickedPalette = remember(tokens.theme) {
            SubjectPalette.fromColor(PickedCatalogColor, tokens.theme)
        }
        CompositionLocalProvider(LocalContentColor provides tokens.primaryInk) {
            Box(Modifier.fillMaxSize().subjectScreenWash(scope)) {
                Column(
                    Modifier
                        .verticalScroll(rememberScrollState())
                        .statusBarsPadding()
                        .navigationBarsPadding()
                        .padding(top = 12.dp, bottom = 28.dp),
                    verticalArrangement = Arrangement.spacedBy(20.dp)
                ) {
                    Text(
                        text = "Design catalog",
                        modifier = Modifier.padding(horizontal = SubjectMetrics.headerGutter),
                        fontSize = 13.sp,
                        color = tokens.secondaryInk
                    )
                    ThemeSwitcher(selected = mode, palette = scope, onSelect = { mode = it })
                    TokenSwatches()
                    PaletteSpecimen("Default accent", scope)
                    PaletteSpecimen("Hue 38°", huePalette)
                    PaletteSpecimen("Picked #C47A8A", pickedPalette)
                }
            }
        }
    }
}

@Composable
private fun ThemeSwitcher(
    selected: KudosThemeMode,
    palette: SubjectPalette,
    onSelect: (KudosThemeMode) -> Unit
) {
    Row(
        Modifier
            .horizontalScroll(rememberScrollState())
            .padding(horizontal = SubjectMetrics.gutter),
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        CatalogModes.forEach { mode ->
            SubjectChip(
                text = mode.label,
                style = SubjectChipStyle.Pill(isSelected = mode == selected),
                palette = palette,
                modifier = Modifier.clickable { onSelect(mode) }
            )
        }
    }
}

@Composable
private fun TokenSwatches() {
    val tokens = LocalKudosTokens.current
    val swatches = listOf(
        "Background" to tokens.background,
        "Panel" to tokens.panelFill,
        "Card" to tokens.cardFill,
        "Primary" to tokens.primaryInk,
        "Secondary" to tokens.secondaryInk,
        "Tertiary" to tokens.tertiaryInk,
        "Separator" to tokens.separator,
        "Accent" to tokens.accent
    )
    Row(
        Modifier
            .horizontalScroll(rememberScrollState())
            .padding(horizontal = SubjectMetrics.gutter),
        horizontalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        swatches.forEach { (name, color) ->
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Box(
                    Modifier
                        .size(36.dp)
                        .background(color, RoundedCornerShape(8.dp))
                        .border(0.5.dp, tokens.glassStroke(), RoundedCornerShape(8.dp))
                )
                Text(name, fontSize = 9.sp, color = tokens.secondaryInk)
            }
        }
    }
}

@Composable
private fun PaletteSpecimen(title: String, palette: SubjectPalette) {
    val tokens = LocalKudosTokens.current
    var collapsed by remember(title) { mutableStateOf(false) }
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(
            text = title,
            modifier = Modifier.padding(horizontal = SubjectMetrics.headerGutter),
            fontSize = 13.sp,
            fontWeight = FontWeight.SemiBold,
            color = tokens.secondaryInk
        )
        Box(
            Modifier
                .padding(horizontal = SubjectMetrics.panelGutter)
                .fillMaxWidth()
                .height(96.dp)
                .clip(RoundedCornerShape(SubjectMetrics.rowRadius))
                .subjectScreenWash(palette, washHeight = 96.dp)
        )
        SubjectHeaderBlock(
            kicker = "Home",
            kickerTrailingCount = 2,
            title = title,
            subtitle = "4 works",
            palette = palette
        )
        SectionRuleHeader(
            title = "Reading",
            count = 1280,
            note = "Drag to reorder",
            isCollapsed = collapsed,
            onToggleCollapse = { collapsed = !collapsed },
            onSeeAll = {}
        )
        Column(
            Modifier
                .padding(horizontal = SubjectMetrics.panelGutter)
                .subjectPanel()
        ) {
            Text(
                "Rating",
                modifier = Modifier.padding(horizontal = 14.dp, vertical = 12.dp),
                color = tokens.primaryInk,
                fontSize = 15.sp
            )
            SubjectRowSeparator()
            Text(
                "Warnings",
                modifier = Modifier.padding(horizontal = 14.dp, vertical = 12.dp),
                color = tokens.primaryInk,
                fontSize = 15.sp
            )
        }
        Row(
            Modifier
                .horizontalScroll(rememberScrollState())
                .padding(horizontal = SubjectMetrics.gutter),
            horizontalArrangement = Arrangement.spacedBy(7.dp)
        ) {
            SubjectChip(text = "Neutral", palette = palette)
            SubjectChip(
                text = "Tinted",
                style = SubjectChipStyle.Tinted,
                palette = palette,
                leadingIcon = Icons.Filled.Star,
                trailingIcon = Icons.Filled.Close
            )
            SubjectChip(text = "Add", style = SubjectChipStyle.Dashed, palette = palette)
            SubjectChip(text = "All", style = SubjectChipStyle.Pill(isSelected = false), palette = palette)
            SubjectChip(text = "All", style = SubjectChipStyle.Pill(isSelected = true), palette = palette)
        }
        SubjectStatStrip(
            cells = listOf(
                SubjectStatCell("12", "Works"),
                SubjectStatCell("3", "Filters", isHighlighted = true),
                SubjectStatCell("40", "Pages"),
                SubjectStatCell("2", "Comments", onClick = {})
            ),
            palette = palette,
            modifier = Modifier.padding(horizontal = SubjectMetrics.panelGutter)
        )
        Row(
            Modifier
                .horizontalScroll(rememberScrollState())
                .padding(horizontal = SubjectMetrics.gutter),
            horizontalArrangement = Arrangement.spacedBy(16.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            WorkProgressRing(progress = 0.0)
            WorkProgressRing(progress = 0.62, state = "Reading", tint = palette.accent)
            WorkProgressRing(progress = 1.0, state = "Finished")
            AccentIconSquare(icon = Icons.Filled.Star, contentDescription = "History", accent = palette.tint)
            GlassCircleButton(onClick = {}, accessibilityName = "Back") {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null, modifier = Modifier.fillMaxSize())
            }
            GlassCircleButton(
                onClick = {},
                accessibilityName = "Filter",
                isAccented = true,
                palette = palette,
                badge = "3"
            ) {
                Icon(Icons.Filled.FilterList, contentDescription = null, modifier = Modifier.fillMaxSize())
            }
            FilterButton(filtersActive = false, onClick = {})
            FilterButton(filtersActive = true, onClick = {}, badgeCount = 3, onClearFilters = {})
        }
    }
}
