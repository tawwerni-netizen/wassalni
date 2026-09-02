@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package com.wassalni.app.ui.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.wassalni.app.R
import com.wassalni.app.auth.SettingsViewModel
import com.wassalni.app.ui.locale.AppLocale
import com.wassalni.core.designsystem.WassalniTheme

@Composable
fun SettingsScreen(
    onSignedOut: () -> Unit,
    viewModel: SettingsViewModel = hiltViewModel(),
) {
    val spacing = WassalniTheme.spacing

    Scaffold(
        topBar = { TopAppBar(title = { Text(stringResource(R.string.settings_title)) }) }
    ) { innerPadding ->
        Column(modifier = Modifier.fillMaxSize().padding(innerPadding).padding(spacing.screen)) {
            Text(stringResource(R.string.settings_language), style = MaterialTheme.typography.titleMedium)
            Spacer(Modifier.height(spacing.sm))
            LanguagePicker()

            Spacer(Modifier.height(spacing.xl))
            HorizontalDivider()
            Spacer(Modifier.height(spacing.xl))

            TextButton(
                onClick = {
                    viewModel.signOut()
                    onSignedOut()
                },
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(stringResource(R.string.settings_sign_out))
            }
        }
    }
}

/**
 * Switching here flips the app's whole layout direction, not just its
 * strings — see [com.wassalni.core.designsystem.WassalniTheme]. Arabic stays
 * first in the list because it is the default, not because it is
 * alphabetically first.
 */
@Composable
private fun LanguagePicker() {
    var selected by remember { mutableStateOf(AppLocale.current()) }

    Column(Modifier.selectableGroup()) {
        AppLocale.entries.forEach { locale ->
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .selectable(
                        selected = selected == locale,
                        onClick = {
                            selected = locale
                            AppLocale.apply(locale)
                        },
                        role = Role.RadioButton,
                    )
                    .padding(vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                RadioButton(selected = selected == locale, onClick = null)
                Spacer(Modifier.width(8.dp))
                Text(text = locale.nativeName, style = MaterialTheme.typography.bodyLarge)
            }
        }
    }
}
