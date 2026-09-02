package com.wassalni.app.auth

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.wassalni.core.data.auth.AuthRepository
import com.wassalni.core.model.AuthError
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

sealed interface AuthSubmitState {
    data object Idle : AuthSubmitState
    data object Loading : AuthSubmitState
    data class Failed(val error: AuthError) : AuthSubmitState

    /** Success is not a terminal UI state here — [SessionViewModel] reacts to
     *  the resulting session change and the app navigates away. This exists so
     *  the screen can stop showing a spinner without needing its own
     *  navigation decision. */
    data object Succeeded : AuthSubmitState
}

@HiltViewModel
class AuthViewModel @Inject constructor(
    private val authRepository: AuthRepository,
) : ViewModel() {

    private val _submitState = MutableStateFlow<AuthSubmitState>(AuthSubmitState.Idle)
    val submitState: StateFlow<AuthSubmitState> = _submitState.asStateFlow()

    fun onSignInWithEmail(email: String, password: String) = submit {
        authRepository.signInWithEmail(email, password)
    }

    fun onSignUpWithEmail(email: String, password: String) = submit {
        authRepository.signUpWithEmail(email, password)
    }

    /** Called once the Composable layer has already obtained the Google ID
     *  token via Credential Manager — this ViewModel has no Activity context
     *  and cannot request one itself. */
    fun onGoogleIdToken(idToken: String, rawNonce: String) = submit {
        authRepository.signInWithGoogleIdToken(idToken, rawNonce)
    }

    fun onGoogleSignInCancelled() {
        _submitState.value = AuthSubmitState.Failed(AuthError.GoogleSignInCancelled)
    }

    fun dismissError() {
        _submitState.value = AuthSubmitState.Idle
    }

    private fun submit(action: suspend () -> Result<Unit>) {
        _submitState.value = AuthSubmitState.Loading
        viewModelScope.launch {
            action().fold(
                onSuccess = { _submitState.value = AuthSubmitState.Succeeded },
                onFailure = { e ->
                    _submitState.value = AuthSubmitState.Failed(e as? AuthError ?: AuthError.Unknown(e.message ?: ""))
                },
            )
        }
    }
}
