package com.wassalni.app.auth

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.wassalni.core.data.auth.AuthRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class SettingsViewModel @Inject constructor(
    private val authRepository: AuthRepository,
) : ViewModel() {

    /** Fire-and-forget: [com.wassalni.app.auth.SessionViewModel] reacts to the
     *  resulting sign-out through its own session flow, so this screen does
     *  not need to track a result to navigate correctly. */
    fun signOut() {
        viewModelScope.launch { authRepository.signOut() }
    }
}
