package io.github.cidy02.kudos.onboarding

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.MenuBook
import androidx.compose.material.icons.outlined.BugReport
import androidx.compose.material.icons.outlined.Code
import androidx.compose.material.icons.outlined.FavoriteBorder
import androidx.compose.material.icons.outlined.Shield
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.R
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SubjectPalette

/**
 * First-launch welcome screen (iOS `WelcomeView` parity). Theme-aware Material 3
 * introduction — not a legal wall of text. Full disclaimer and credits live in
 * Account → About. Host persists completion via [onContinue].
 */
@Composable
fun WelcomeScreen(
    onContinue: () -> Unit,
    modifier: Modifier = Modifier,
    onBack: () -> Unit = {}
) {
    androidx.activity.compose.BackHandler(onBack = onBack)
    val context = LocalContext.current

    OnboardingScaffold(modifier = modifier, content = {
        WelcomeHeader()
        WelcomePoints()
    }, footer = {
        val tokens = LocalKudosTokens.current
        TextButton(
            onClick = {
                runCatching {
                    context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(RepositoryUrl)))
                }
            },
            colors = ButtonDefaults.textButtonColors(contentColor = tokens.accent),
            modifier = Modifier.semantics {
                contentDescription = "View on GitHub. Opens the project's source code in your browser"
            }
        ) {
            Icon(Icons.Outlined.Code, contentDescription = null, modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(8.dp))
            Text("View on GitHub", lineHeight = 20.sp)
        }
        Button(
            onClick = onContinue,
            colors = ButtonDefaults.buttonColors(
                containerColor = tokens.accent,
                contentColor = SubjectPalette.label(tokens.accent)
            ),
            modifier = Modifier.fillMaxWidth().heightIn(min = 52.dp)
        ) {
            Text("Continue", style = MaterialTheme.typography.titleMedium, lineHeight = 24.sp)
        }
    })
}

@Composable
private fun WelcomeHeader() {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        Image(
            painter = painterResource(R.drawable.ic_kudos_mark),
            contentDescription = null,
            modifier = Modifier
                .size(108.dp)
                .shadow(8.dp, RoundedCornerShape(24.dp))
                .clip(RoundedCornerShape(24.dp))
        )
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(
                text = "Welcome to Kudos",
                style = MaterialTheme.typography.headlineLarge,
                color = LocalKudosTokens.current.primaryInk,
                lineHeight = 40.sp,
                textAlign = TextAlign.Center
            )
            Text(
                text = "Free to use • Ad-free • Built by fans",
                style = MaterialTheme.typography.titleSmall,
                lineHeight = 20.sp,
                color = LocalKudosTokens.current.secondaryInk,
                textAlign = TextAlign.Center
            )
        }
    }
}

@Composable
private fun WelcomePoints() {
    Column(
        modifier = Modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(22.dp)
    ) {
        OnboardingPoint(
            icon = Icons.AutoMirrored.Outlined.MenuBook,
            title = "Built for AO3 Readers",
            body = "An unofficial reader for Archive of Our Own. Kudos is free and open " +
                "source, has no ads, and isn't affiliated with AO3 or the OTW."
        )
        OnboardingPoint(
            icon = Icons.Outlined.Shield,
            title = "Your Privacy Matters",
            body = "Kudos has no ads, analytics, tracking, or hidden data collection. Your " +
                "AO3 sign-in and the information Kudos needs stay on your device."
        )
        OnboardingPoint(
            icon = Icons.Outlined.FavoriteBorder,
            title = "Community Built",
            body = "Kudos is made by fans. It doesn't accept donations, but you can " +
                "contribute to the project."
        )
        OnboardingPoint(
            icon = Icons.Outlined.BugReport,
            title = "Need Help?",
            body = "Found a bug? Shake your device to send a report, or open an issue on " +
                "GitHub. The AO3 team can't help with Kudos, so please don't contact them about it."
        )
    }
}

private const val RepositoryUrl = "https://github.com/cidy02/kudos-ao3-reader"
