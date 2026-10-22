package io.github.cidy02.kudos.ui.subject

import android.database.ContentObserver
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/** iOS SkeletonShimmer: a single announcement, decorative children, no animation when disabled. */
@Composable
fun SubjectSkeletonLoading(
    label: String,
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit
) {
    val alpha = subjectSkeletonAlpha()
    Box(modifier.clearAndSetSemantics {
        contentDescription = label
        liveRegion = LiveRegionMode.Polite
    }) {
        Box(Modifier.graphicsLayer { this.alpha = alpha }) { content() }
    }
}

@Composable
internal fun subjectSkeletonAlpha(animationsEnabled: Boolean = systemAnimationsEnabled()): Float {
    // Do not create an infinite transition at all with Remove animations enabled.
    if (!animationsEnabled) return 0.85f
    val alpha by rememberInfiniteTransition(label = "list skeleton").animateFloat(
        initialValue = 0.5f,
        targetValue = 0.9f,
        animationSpec = infiniteRepeatable(tween(1100), RepeatMode.Reverse),
        label = "list skeleton opacity"
    )
    return alpha
}

@Composable
private fun systemAnimationsEnabled(): Boolean {
    val resolver = LocalContext.current.contentResolver
    fun animationsEnabled() = Settings.Global.getFloat(resolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) > 0f
    var enabled by remember(resolver) { mutableStateOf(animationsEnabled()) }
    DisposableEffect(resolver) {
        val observer = object : ContentObserver(Handler(Looper.getMainLooper())) {
            override fun onChange(selfChange: Boolean) {
                enabled = animationsEnabled()
            }
        }
        resolver.registerContentObserver(Settings.Global.getUriFor(Settings.Global.ANIMATOR_DURATION_SCALE), false, observer)
        enabled = animationsEnabled()
        onDispose { resolver.unregisterContentObserver(observer) }
    }
    return enabled
}

/** Text dimensions use sp, including Android's font scaling; a narrow parent may shrink widths. */
// Callers pass the sizes by position; modifier stays after them.
@Suppress("ModifierParameter")
@Composable
fun SubjectSkeletonBlock(
    height: Int = 13,
    width: Int? = null,
    modifier: Modifier = Modifier,
    round: Boolean = false
) {
    val density = LocalDensity.current
    val lineHeight = with(density) { height.sp.toDp() }
    val lineWidth = width?.let { with(density) { it.sp.toDp() } }
    Box(
        modifier
            .then(if (lineWidth == null) Modifier.fillMaxWidth() else Modifier.widthIn(max = lineWidth).fillMaxWidth())
            .height(lineHeight)
            .background(LocalKudosTokens.current.primaryInk.copy(alpha = 0.12f), RoundedCornerShape(if (round) 50 else 25))
    )
}

enum class SubjectSkeletonShape { Work, Fandom, Category, Inbox }

/** Counts follow SkeletonLoading.swift and AccountInboxViews.loadingRows. */
// Callers pass the sizes by position; modifier stays after them.
@Suppress("ModifierParameter")
@Composable
fun SubjectSkeletonList(
    label: String,
    count: Int = 6,
    shape: SubjectSkeletonShape = SubjectSkeletonShape.Work,
    modifier: Modifier = Modifier,
    scrollable: Boolean = true
) {
    SubjectSkeletonLoading(label, modifier.fillMaxWidth()) {
        Column(
            Modifier.fillMaxWidth()
                .then(if (scrollable) Modifier.verticalScroll(rememberScrollState()) else Modifier)
                .padding(horizontal = 16.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(if (shape == SubjectSkeletonShape.Category) 18.dp else 12.dp)
        ) {
            repeat(count) { index ->
                when (shape) {
                    SubjectSkeletonShape.Work -> SubjectWorkRowSkeleton()
                    SubjectSkeletonShape.Fandom -> FandomSkeleton()
                    SubjectSkeletonShape.Category -> CategorySkeleton(listOf(8, 12, 5, 10, 3, 12, 7, 9)[index % 8])
                    SubjectSkeletonShape.Inbox -> InboxSkeleton()
                }
            }
        }
    }
}

@Composable
fun SubjectAuthorProfileSkeleton() {
    SubjectSkeletonLoading("Loading author profile") {
        Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Row(Modifier.fillMaxWidth().cardRow().padding(14.dp), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                Box(Modifier.size(72.dp)) { SubjectSkeletonBlock(72, 72) }
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(9.dp)) {
                    SubjectSkeletonBlock(20, 150)
                    SubjectSkeletonBlock(width = 110)
                    SubjectSkeletonBlock(width = 180)
                }
            }
            SubjectSkeletonBlock(34)
            repeat(4) { SubjectWorkRowSkeleton() }
        }
    }
}

/** AO3WorkRowSkeleton: title/byline beside four status tiles, fandom, summary, stats, date. */
@Composable
fun SubjectWorkRowSkeleton() {
    Column(
        Modifier.fillMaxWidth().cardRow().padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                SubjectSkeletonBlock(17, 200)
                SubjectSkeletonBlock(17, 140)
                SubjectSkeletonBlock(14, 110)
            }
            StatusSkeleton()
        }
        SubjectSkeletonBlock(12, 190)
        SubjectSkeletonBlock()
        SubjectSkeletonBlock()
        SubjectSkeletonBlock(width = 210)
        SkeletonStats()
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Box(Modifier.weight(1f)) { SubjectSkeletonBlock(24, 96, round = true) }
            Box(Modifier.size(24.dp)) { SubjectSkeletonBlock(24, 24, round = true) }
        }
    }
}

@Composable
internal fun SubjectCoverSkeletonContent() {
    Column(Modifier.fillMaxSize().padding(12.dp), verticalArrangement = Arrangement.spacedBy(7.dp)) {
        SubjectSkeletonBlock(15, 132)
        SubjectSkeletonBlock(15, 84)
        Spacer(Modifier.weight(1f))
        Box(Modifier.align(Alignment.CenterHorizontally)) { StatusSkeleton() }
        Spacer(Modifier.weight(1f))
        SubjectSkeletonBlock(12, 92)
        SubjectSkeletonBlock(10, 118)
        SubjectSkeletonBlock(10, 60)
        SubjectSkeletonBlock(5, 140)
    }
}

@Composable
private fun StatusSkeleton() {
    Column(verticalArrangement = Arrangement.spacedBy(4.5.dp)) {
        repeat(2) {
            Row(horizontalArrangement = Arrangement.spacedBy(4.5.dp)) {
                repeat(2) { Box(Modifier.size(27.dp)) { SubjectSkeletonBlock(27, 27) } }
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun SkeletonStats(widths: List<Int> = listOf(46, 58, 40, 52)) {
    FlowRow(horizontalArrangement = Arrangement.spacedBy(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        widths.forEach { width ->
            Box(Modifier.width(with(LocalDensity.current) { width.sp.toDp() })) { SubjectSkeletonBlock(11, width) }
        }
    }
}

@Composable
private fun FandomSkeleton() {
    Row(Modifier.fillMaxWidth().cardRow().padding(14.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Box(Modifier.size(24.dp)) { SubjectSkeletonBlock(22, 24) }
        Box(Modifier.weight(1f)) { SubjectSkeletonBlock(15, 200) }
        Box(Modifier.weight(0.35f)) { SubjectSkeletonBlock(12, 56) }
        Box(Modifier.size(14.dp)) { SubjectSkeletonBlock(12, 14) }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun CategorySkeleton(chipCount: Int) {
    Column(Modifier.fillMaxWidth().cardRow().padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        // CategoryPanel's leading icon, two-line title and count line above its chip cluster.
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Box(Modifier.size(32.dp)) { SubjectSkeletonBlock(32, 32) }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                SubjectSkeletonBlock(15, 160)
                SubjectSkeletonBlock(15, 96)
                SkeletonStats(listOf(96, 78, 88))
            }
        }
        FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            repeat(chipCount) { index ->
                val width = if (index % 2 == 0) 116 else 82
                Box(Modifier.widthIn(max = with(LocalDensity.current) { width.sp.toDp() })) {
                    SubjectSkeletonBlock(28, width, round = true)
                }
            }
        }
    }
}

@Composable
private fun InboxSkeleton() {
    Row(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 2.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Box(Modifier.size(40.dp)) { SubjectSkeletonBlock(40, 40, round = true) }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            SubjectSkeletonBlock(width = 140)
            SubjectSkeletonBlock(width = 220)
            SubjectSkeletonBlock(width = 180)
        }
    }
}
