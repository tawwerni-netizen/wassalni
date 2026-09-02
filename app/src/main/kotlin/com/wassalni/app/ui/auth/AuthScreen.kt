package com.wassalni.app.ui.auth

import android.widget.Toast
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.collectAsState
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.credentials.exceptions.GetCredentialCancellationException
import com.wassalni.app.BuildConfig
import com.wassalni.app.R
import com.wassalni.app.auth.AuthSubmitState
import com.wassalni.app.auth.AuthViewModel
import com.wassalni.app.auth.GoogleIdTokenProvider
import com.wassalni.core.designsystem.WassalniTheme
import com.wassalni.core.model.AuthError
import kotlinx.coroutines.launch

private enum class AuthMode { SIGN_IN, SIGN_UP }

/**
 * Email/password is the only path that can be exercised today: Google
 * sign-in needs a Google Cloud OAuth "web application" client ID (not the
 * Android one) registered in Supabase's Auth providers, and
 * [BuildConfig.GOOGLE_WEB_CLIENT_ID] is blank until that exists. Rather than
 * show a button that would fail on every tap, it is hidden — see
 * ARCHITECTURE.md and TASKS.md M1 for what remains.
 */
@Composable
fun AuthScreen(
    onSignedIn: () -> Unit,
    viewModel: AuthViewModel = hiltViewModel(),
) {
    val spacing = WassalniTheme.spacing
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val submitState by viewModel.submitState.collectAsState()

    var mode by rememberSaveable { mutableStateOf(AuthMode.SIGN_IN) }
    var email by rememberSaveable { mutableStateOf("") }
    var password by rememberSaveable { mutableStateOf("") }
    var passwordVisible by rememberSaveable { mutableStateOf(false) }

    LaunchedEffect(submitState) {
        if (submitState is AuthSubmitState.Succeeded) onSignedIn()
    }

    val isLoading = submitState is AuthSubmitState.Loading
    val errorMessage = (submitState as? AuthSubmitState.Failed)?.error?.let { errorMessageFor(it) }

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
                text = stringResource(R.string.app_name),
                style = MaterialTheme.typography.headlineMedium,
            )
            Spacer(Modifier.height(spacing.sm))
            Text(
                text = stringResource(R.string.tagline),
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            Spacer(Modifier.height(spacing.xxl))

            if (BuildConfig.GOOGLE_WEB_CLIENT_ID.isNotBlank()) {
                val provider = remember { GoogleIdTokenProvider(context) }
                OutlinedButton(
                    onClick = {
                        scope.launch {
                            try {
                                val result = provider.requestIdToken(
                                    webClientId = BuildConfig.GOOGLE_WEB_CLIENT_ID,
                                    filterByAuthorizedAccounts = false,
                                )
                                viewModel.onGoogleIdToken(result.idToken, result.rawNonce)
                            } catch (e: GetCredentialCancellationException) {
                                viewModel.onGoogleSignInCancelled()
                            } catch (e: Exception) {
                                Toast.makeText(context, R.string.error_generic, Toast.LENGTH_SHORT).show()
                            }
                        }
                    },
                    enabled = !isLoading,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text(stringResource(R.string.auth_continue_with_google))
                }

                Spacer(Modifier.height(spacing.lg))
                HorizontalDivider()
                Spacer(Modifier.height(spacing.lg))
            }

            OutlinedTextField(
                value = email,
                onValueChange = { email = it },
                label = { Text(stringResource(R.string.auth_email)) },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
                modifier = Modifier.fillMaxWidth(),
                enabled = !isLoading,
            )

            Spacer(Modifier.height(spacing.md))

            OutlinedTextField(
                value = password,
                onValueChange = { password = it },
                label = { Text(stringResource(R.string.auth_password)) },
                singleLine = true,
                enabled = !isLoading,
                visualTransformation = if (passwordVisible) VisualTransformation.None else PasswordVisualTransformation(),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                keyboardActions = KeyboardActions(onDone = { submit(viewModel, mode, email, password) }),
                trailingIcon = {
                    IconButton(onClick = { passwordVisible = !passwordVisible }) {
                        Icon(
                            imageVector = if (passwordVisible) Icons.Filled.VisibilityOff else Icons.Filled.Visibility,
                            contentDescription = null,
                        )
                    }
                },
                modifier = Modifier.fillMaxWidth(),
            )

            if (errorMessage != null) {
                Spacer(Modifier.height(spacing.sm))
                Text(
                    text = errorMessage,
                    color = MaterialTheme.colorScheme.error,
                    style = MaterialTheme.typography.bodySmall,
                )
            }

            Spacer(Modifier.height(spacing.lg))

            Button(
                onClick = { submit(viewModel, mode, email, password) },
                enabled = !isLoading && email.isNotBlank() && password.isNotBlank(),
                modifier = Modifier.fillMaxWidth(),
            ) {
                if (isLoading) {
                    CircularProgressIndicator(
                        modifier = Modifier.height(20.dp),
                        color = MaterialTheme.colorScheme.onPrimary,
                        strokeWidth = 2.dp,
                    )
                } else {
                    Text(
                        stringResource(
                            if (mode == AuthMode.SIGN_IN) R.string.auth_sign_in else R.string.auth_sign_up
                        )
                    )
                }
            }

            Spacer(Modifier.height(spacing.sm))

            TextButton(
                onClick = {
                    mode = if (mode == AuthMode.SIGN_IN) AuthMode.SIGN_UP else AuthMode.SIGN_IN
                    viewModel.dismissError()
                },
                enabled = !isLoading,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(
                    text = stringResource(
                        if (mode == AuthMode.SIGN_IN) R.string.auth_switch_to_sign_up
                        else R.string.auth_switch_to_sign_in
                    ),
                    textAlign = TextAlign.Center,
                )
            }
        }
    }
}

private fun submit(viewModel: AuthViewModel, mode: AuthMode, email: String, password: String) {
    if (email.isBlank() || password.isBlank()) return
    when (mode) {
        AuthMode.SIGN_IN -> viewModel.onSignInWithEmail(email, password)
        AuthMode.SIGN_UP -> viewModel.onSignUpWithEmail(email, password)
    }
}

@Composable
private fun errorMessageFor(error: AuthError): String = when (error) {
    AuthError.InvalidCredentials -> stringResource(R.string.auth_error_invalid_credentials)
    AuthError.EmailAlreadyInUse -> stringResource(R.string.auth_error_email_in_use)
    AuthError.WeakPassword -> stringResource(R.string.auth_error_weak_password)
    AuthError.NetworkUnavailable -> stringResource(R.string.error_offline)
    AuthError.GoogleSignInCancelled -> "" // the user cancelled; nothing to say
    is AuthError.Unknown -> stringResource(R.string.error_generic)
}
