package com.wassalni.app.auth

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.wassalni.core.data.auth.ProfileRepository
import com.wassalni.core.model.SessionState
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import javax.inject.Inject

/**
 * The single source of truth for "what should the whole app show right now" —
 * sign-in, the suspended-account gate, or the real app. Lives above the
 * navigation graph rather than inside any one screen, because this decision
 * is not a screen's to make: nothing else should be able to navigate around a
 * suspension or a missing session.
 */
@HiltViewModel
class SessionViewModel @Inject constructor(
    profileRepository: ProfileRepository,
) : ViewModel() {

    val sessionState: StateFlow<SessionState> = profileRepository.sessionState
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), SessionState.Loading)
}
