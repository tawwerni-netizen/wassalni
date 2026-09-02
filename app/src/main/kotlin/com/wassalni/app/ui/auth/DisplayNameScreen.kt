package com.wassalni.app.ui.auth

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.wassalni.app.R
import com.wassalni.app.auth.AuthSubmitState
import com.wassalni.app.auth.DisplayNameViewModel
import com.wassalni.core.designsystem.WassalniTheme

/**
 * Shown once, right after first sign-in, while the profile row still has the
 * placeholder name the signup trigger assigns. There is no name-length
 * enforcement server-side beyond a 2–40 char CHECK constraint (0001), so this
 * screen's validation is a UX nicety, not the security boundary.
 */
@Composable
fun DisplayNameScreen(
    onDone: () -> Unit,
    viewModel: DisplayNameViewModel = hiltViewModel(),
) {
    val spacing = WassalniTheme.spacing
    val submitState by viewModel.submitState.collectAsState()
    var name by rememberSaveable { mutableStateOf("") }

    LaunchedEffect(submitState) {
        if (submitState is AuthSubmitState.Succeeded) onDone()
    }

    val isLoading = submitState is AuthSubmitState.Loading
    val trimmedLength = name.trim().length
    val isValid = trimmedLength in 2..40

    Scaffold { innerPadding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
                .padding(horizontal = spacing.screen, vertical = spacing.xl),
            verticalArrangement = Arrangement.Center,
        ) {
            Text(stringResource(R.string.display_name_title), style = MaterialTheme.typography.headlineMedium)
            Spacer(Modifier.height(spacing.sm))
            Text(
                stringResource(R.string.display_name_subtitle),
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            Spacer(Modifier.height(spacing.xxl))

            OutlinedTextField(
                value = name,
                onValueChange = { if (it.length <= 40) name = it },
                label = { Text(stringResource(R.string.display_name_label)) },
                singleLine = true,
                isError = name.isNotEmpty() && !isValid,
                supportingText = if (name.isNotEmpty() && !isValid) {
                    { Text(stringResource(R.string.display_name_error_length)) }
                } else null,
                enabled = !isLoading,
                modifier = Modifier.fillMaxWidth(),
            )

            Spacer(Modifier.height(spacing.lg))

            Button(
                onClick = { viewModel.onSubmit(name) },
                enabled = isValid && !isLoading,
                modifier = Modifier.fillMaxWidth(),
            ) {
                if (isLoading) {
                    CircularProgressIndicator(
                        modifier = Modifier.height(20.dp),
                        color = MaterialTheme.colorScheme.onPrimary,
                        strokeWidth = 2.dp,
                    )
                } else {
                    Text(stringResource(R.string.display_name_continue))
                }
            }
        }
    }
}
