package com.wassalni.core.data.auth

import com.wassalni.core.model.Profile
import com.wassalni.core.model.SessionState
import kotlinx.coroutines.flow.Flow

/**
 * The user's own profile: `v_my_profile`, not the raw `profiles` table. That
 * view is what exposes `role`/`is_suspended` back to the user reading their
 * own row — the base table's column grant deliberately does not (see
 * ARCHITECTURE.md §9, decision 6/7's sibling issue in db/migrations/0010).
 */
interface ProfileRepository {

    /**
     * The single source of truth for "what should the user see right now" —
     * [com.wassalni.core.model.SessionState.Loading] until auth finishes
     * initialising, then tracks sign-in state and suspension together so a
     * screen never has to combine two separate flows itself.
     */
    val sessionState: Flow<SessionState>

    suspend fun setDisplayName(name: String): Result<Unit>

    /** Data half of account deletion — see ARCHITECTURE.md §9 decision on
     *  0010: does not remove the auth account itself. */
    suspend fun anonymizeMyData(): Result<Unit>

    /**
     * Forces [sessionState] to re-fetch the profile row. [sessionState] is
     * driven by the auth session, not by a Realtime subscription on
     * `profiles` — a plain DB write like [setDisplayName] does not change the
     * auth session at all, so without this the UI would never learn the write
     * happened and a screen gated on `needsDisplayName()` would never advance.
     */
    fun refresh()
}

/** A profile still using the placeholder name the signup trigger assigns —
 *  the signal to show the display-name capture step. */
fun Profile.needsDisplayName(): Boolean = displayName == PLACEHOLDER_DISPLAY_NAME

private const val PLACEHOLDER_DISPLAY_NAME = "مستخدم جديد"
