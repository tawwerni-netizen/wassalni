package com.wassalni.app.ui.auth

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Block
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.wassalni.app.R
import com.wassalni.core.designsystem.WassalniTheme

/**
 * Deliberately a dead end: no bottom nav, no back button that leads anywhere
 * useful, no way to reach a report or a conversation. The only action is
 * signing out. This is rendered directly by the root composable — outside any
 * NavHost — precisely so there is no route back into the app for a suspended
 * account; see WassalniApp.kt.
 */
@Composable
fun SuspendedScreen(
    reason: String?,
    onSignOut: () -> Unit,
) {
    val spacing = WassalniTheme.spacing

    Scaffold { innerPadding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
                .padding(horizontal = spacing.screen, vertical = spacing.xl),
            verticalArrangement = Arrangement.Center,
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Icon(
                imageVector = Icons.Filled.Block,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.error,
                modifier = Modifier.height(48.dp),
            )
            Spacer(Modifier.height(spacing.lg))
            Text(
                stringResource(R.string.suspended_title),
                style = MaterialTheme.typography.headlineSmall,
                textAlign = TextAlign.Center,
            )
            Spacer(Modifier.height(spacing.sm))
            Text(
                stringResource(R.string.suspended_body),
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
            )
            if (!reason.isNullOrBlank()) {
                Spacer(Modifier.height(spacing.sm))
                Text(
                    stringResource(R.string.suspended_reason_prefix, reason),
                    style = MaterialTheme.typography.bodyMedium,
                    textAlign = TextAlign.Center,
                )
            }
            Spacer(Modifier.height(spacing.xxl))
            TextButton(onClick = onSignOut, modifier = Modifier.fillMaxWidth()) {
                Text(stringResource(R.string.suspended_sign_out))
            }
        }
    }
}
