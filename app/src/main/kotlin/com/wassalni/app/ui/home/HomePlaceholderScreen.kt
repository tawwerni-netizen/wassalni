package com.wassalni.app.ui.home

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.SearchOff
import androidx.compose.material.icons.filled.VolunteerActivism
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import com.wassalni.app.R
import com.wassalni.core.designsystem.WassalniTheme

/**
 * M0 placeholder. Proves the theme, RTL, typography and string resources are
 * wired end to end, and stakes out the shape the real home screen takes in M4:
 * the two primary actions are the product, so they get the whole screen and
 * nothing competes with them.
 */
@Composable
fun HomePlaceholderScreen(
    onLostClick: () -> Unit = {},
    onFoundClick: () -> Unit = {},
) {
    val spacing = WassalniTheme.spacing

    Scaffold { innerPadding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = spacing.screen, vertical = spacing.xl),
            verticalArrangement = Arrangement.Center,
        ) {
            Text(
                text = stringResource(R.string.home_greeting),
                style = MaterialTheme.typography.headlineMedium,
                modifier = Modifier.semantics { heading() },
            )
            Spacer(Modifier.height(spacing.sm))
            Text(
                text = stringResource(R.string.tagline),
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            Spacer(Modifier.height(spacing.xxl))

            PrimaryActionCard(
                title = stringResource(R.string.action_lost),
                subtitle = stringResource(R.string.action_lost_subtitle),
                icon = Icons.Filled.SearchOff,
                container = WassalniTheme.reportTypeColors.lostContainer,
                onContainer = WassalniTheme.reportTypeColors.onLostContainer,
                onClick = onLostClick,
            )

            Spacer(Modifier.height(spacing.lg))

            PrimaryActionCard(
                title = stringResource(R.string.action_found),
                subtitle = stringResource(R.string.action_found_subtitle),
                icon = Icons.Filled.VolunteerActivism,
                container = WassalniTheme.reportTypeColors.foundContainer,
                onContainer = WassalniTheme.reportTypeColors.onFoundContainer,
                onClick = onFoundClick,
            )

            Spacer(Modifier.height(spacing.xxl))

            Text(
                text = stringResource(R.string.home_placeholder_note),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.outline,
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }
}

/**
 * LOST and FOUND are never distinguished by colour alone — each card carries an
 * icon and a text label too. Red/green is the worst possible pair for the ~8% of
 * men with a colour vision deficiency.
 */
@Composable
private fun PrimaryActionCard(
    title: String,
    subtitle: String,
    icon: ImageVector,
    container: Color,
    onContainer: Color,
    onClick: () -> Unit,
) {
    val spacing = WassalniTheme.spacing

    Card(
        onClick = onClick,
        colors = CardDefaults.cardColors(
            containerColor = container,
            contentColor = onContainer,
        ),
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 96.dp),
    ) {
        Row(
            modifier = Modifier.padding(spacing.lg),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null, // the title next to it already says it
                modifier = Modifier.size(spacing.xxl),
            )
            Spacer(Modifier.width(spacing.lg))
            Column {
                Text(text = title, style = MaterialTheme.typography.titleLarge)
                Spacer(Modifier.height(spacing.xs))
                Text(text = subtitle, style = MaterialTheme.typography.bodyMedium)
            }
        }
    }
}

// Arabic is the default language and English is a switch the user can make, so
// both directions are real shipping states. The LTR preview is not decoration:
// a layout that only works in one direction makes the language toggle cosmetic.

@Preview(name = "RTL light", locale = "ar", showBackground = true)
@Composable
private fun PreviewRtlLight() {
    WassalniTheme(darkTheme = false) { HomePlaceholderScreen() }
}

@Preview(name = "RTL dark", locale = "ar", showBackground = true)
@Composable
private fun PreviewRtlDark() {
    WassalniTheme(darkTheme = true) { HomePlaceholderScreen() }
}

@Preview(name = "LTR light (English)", locale = "en", showBackground = true)
@Composable
private fun PreviewLtrLight() {
    WassalniTheme(darkTheme = false, overrideLayoutDirection = LayoutDirection.Ltr) {
        HomePlaceholderScreen()
    }
}

@Preview(name = "RTL large font", locale = "ar", showBackground = true, fontScale = 2.0f)
@Composable
private fun PreviewLargeFont() {
    WassalniTheme(darkTheme = false) { HomePlaceholderScreen() }
}
