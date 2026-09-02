package com.wassalni.core.model

/**
 * The app's own view of auth state, deliberately smaller than whatever the
 * Supabase SDK exposes: a screen only ever needs to know one of these four
 * things, never the raw session/JWT.
 */
sealed interface SessionState {
    data object Loading : SessionState
    data object SignedOut : SessionState

    /**
     * Signed in, but the account is suspended by a moderator. Distinct from
     * [SignedIn] on purpose — the UI must show a blocking screen with no path
     * back into the app, not a degraded version of it.
     */
    data class Suspended(val reason: String?) : SessionState

    data class SignedIn(val profile: Profile) : SessionState
}

/**
 * Failures a screen can act on individually, rather than one opaque "auth
 * failed" string. Kept small: this is every case the sign-in and sign-up
 * screens need to branch on, not a mirror of every possible Supabase error.
 */
sealed class AuthError(message: String) : Exception(message) {
    data object InvalidCredentials : AuthError("invalid_credentials")
    data object EmailAlreadyInUse : AuthError("email_already_in_use")
    data object WeakPassword : AuthError("weak_password")
    data object NetworkUnavailable : AuthError("network_unavailable")
    data object GoogleSignInCancelled : AuthError("google_sign_in_cancelled")
    data class Unknown(val detail: String) : AuthError(detail)
}
