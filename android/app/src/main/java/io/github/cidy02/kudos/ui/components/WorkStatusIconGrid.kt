package io.github.cidy02.kudos.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.People
import androidx.compose.material.icons.outlined.RadioButtonUnchecked
import androidx.compose.material.icons.outlined.Warning
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Composable
fun WorkStatusIconGrid(
    rating: String,
    categories: List<String>,
    warnings: List<String>,
    isComplete: Boolean,
    modifier: Modifier = Modifier,
    tileSize: Dp = 18.dp,
    announcesToVoiceOver: Boolean = false
) {
    val gap = tileSize * 3 / 18
    val cornerRadius = tileSize * 4 / 18
    val shape = RoundedCornerShape(cornerRadius)
    
    // Rating
    val ratingLetter = when {
        rating.contains("General", ignoreCase = true) -> "G"
        rating.contains("Teen", ignoreCase = true) -> "T"
        rating.contains("Mature", ignoreCase = true) -> "M"
        rating.contains("Explicit", ignoreCase = true) -> "E"
        else -> "?"
    }
    
    // Warnings
    val hasWarning = warnings.any { 
        !it.contains("Choose Not To Use Archive Warnings", ignoreCase = true) && 
        !it.contains("No Archive Warnings Apply", ignoreCase = true)
    }
    
    val semanticDesc = if (announcesToVoiceOver) {
        val wDesc = if (hasWarning) "Has archive warnings" else "No archive warnings"
        val cDesc = if (isComplete) "Complete" else "In progress"
        "Rating: $rating, Categories: ${categories.joinToString()}, $wDesc, $cDesc"
    } else {
        ""
    }

    val semanticsModifier = if (announcesToVoiceOver) {
        Modifier.semantics { contentDescription = semanticDesc }
    } else {
        Modifier.clearAndSetSemantics {}
    }

    Column(
        modifier = modifier.then(semanticsModifier),
        verticalArrangement = Arrangement.spacedBy(gap)
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(gap)) {
            // Top Left: Rating
            StatusTile(
                tileSize = tileSize,
                shape = shape,
                color = MaterialTheme.colorScheme.primary
            ) {
                Text(
                    text = ratingLetter,
                    color = MaterialTheme.colorScheme.primary,
                    fontWeight = FontWeight.Bold,
                    fontSize = (tileSize.value * 12 / 18).sp
                )
            }
            
            StatusTile(
                tileSize = tileSize,
                shape = shape,
                color = if (hasWarning) {
                    MaterialTheme.colorScheme.error
                } else {
                    MaterialTheme.colorScheme.outline
                }
            ) {
                Icon(
                    imageVector = if (hasWarning) Icons.Filled.Warning else Icons.Outlined.Warning,
                    contentDescription = null,
                    tint = if (hasWarning) {
                        MaterialTheme.colorScheme.error
                    } else {
                        MaterialTheme.colorScheme.outline
                    },
                    modifier = Modifier.size(tileSize * 14 / 18)
                )
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(gap)) {
            StatusTile(
                tileSize = tileSize,
                shape = shape,
                color = MaterialTheme.colorScheme.secondary
            ) {
                val raw = if (categories.size > 1) "Multi" else categories.firstOrNull().orEmpty()
                val shortText = when {
                    raw.contains("F/M", ignoreCase = true) -> "F/M"
                    raw.contains("M/M", ignoreCase = true) -> "M/M"
                    raw.contains("F/F", ignoreCase = true) -> "F/F"
                    raw.contains("Gen", ignoreCase = true) -> "Gen"
                    raw.contains("Multi", ignoreCase = true) -> "+"
                    raw.contains("Other", ignoreCase = true) -> "+"
                    raw.isNotBlank() -> "+"
                    else -> null
                }
                if (shortText != null) {
                    Text(
                        text = shortText,
                        color = MaterialTheme.colorScheme.secondary,
                        fontWeight = FontWeight.Bold,
                        fontSize = (tileSize.value * 9 / 18).sp,
                        maxLines = 1
                    )
                } else {
                    Icon(
                        imageVector = Icons.Outlined.People,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.secondary,
                        modifier = Modifier.size(tileSize * 14 / 18)
                    )
                }
            }
            
            // Bottom Right: Completion
            StatusTile(
                tileSize = tileSize,
                shape = shape,
                color = MaterialTheme.colorScheme.tertiary
            ) {
                Icon(
                    imageVector = if (isComplete) Icons.Outlined.CheckCircle else Icons.Outlined.RadioButtonUnchecked,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.tertiary,
                    modifier = Modifier.size(tileSize * 14 / 18)
                )
            }
        }
    }
}

@Composable
private fun StatusTile(
    tileSize: Dp,
    shape: androidx.compose.ui.graphics.Shape,
    color: Color,
    content: @Composable androidx.compose.foundation.layout.BoxScope.() -> Unit
) {
    Box(
        modifier = Modifier
            .size(tileSize)
            .background(color = color.copy(alpha = 0.3f), shape = shape),
        contentAlignment = Alignment.Center,
        content = content
    )
}
