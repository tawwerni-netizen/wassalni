package com.wassalni.app.auth

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.wassalni.core.data.auth.ProfileRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class DisplayNameViewModel @Inject constructor(
    private val profileRepository: ProfileRepository,
) : ViewModel() {

    private val _submitState = MutableStateFlow<AuthSubmitState>(AuthSubmitState.Idle)
    val submitState: StateFlow<AuthSubmitState> = _submitState.asStateFlow()

    fun onSubmit(name: String) {
        val trimmed = name.trim()
        if (trimmed.length !in 2..40) return

        _submitState.value = AuthSubmitState.Loading
        viewModelScope.launch {
            profileRepository.setDisplayName(trimmed).fold(
                onSuccess = {
                    // sessionState only reacts to the auth session, not to a plain
                    // DB write — without this, needsDisplayName() would never
                    // flip and the app would never advance past this screen.
                    profileRepository.refresh()
                    _submitState.value = AuthSubmitState.Succeeded
                },
                onFailure = { _submitState.value = AuthSubmitState.Idle },
            )
        }
    }
}
