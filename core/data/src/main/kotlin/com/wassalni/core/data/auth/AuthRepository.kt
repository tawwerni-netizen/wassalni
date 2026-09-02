package com.wassalni.core.data.auth

import com.wassalni.core.model.AuthError
import kotlinx.coroutines.flow.Flow

/**
 * Everything a screen needs from auth, and nothing a screen shouldn't touch —
 * no raw session, no JWT, no Supabase types. [ProfileRepository] owns the
 * `profiles` row; this owns only identity and credentials.
 */
interface AuthRepository {

    /** The signed-in user's id, or null. Cheap, synchronous-feeling check for
     *  gating a single action; screens that need to REACT to sign-out should
     *  use [ProfileRepository.sessionState] instead. */
    fun currentUserId(): String?

    suspend fun signUpWithEmail(email: String, password: String): Result<Unit>
    suspend fun signInWithEmail(email: String, password: String): Result<Unit>

    /**
     * @param rawNonce the UNHASHED nonce that was hashed before being sent to
     * Google — Supabase re-hashes this and compares it to the token's claim.
     * Passing the wrong one (or the hashed value) makes every sign-in fail.
     */
    suspend fun signInWithGoogleIdToken(idToken: String, rawNonce: String): Result<Unit>

    suspend fun signOut(): Result<Unit>

    /** True once the Auth SDK has finished loading any persisted session from
     *  disk. Nothing should render a sign-in vs. signed-in decision before
     *  this flips true, or a real session flashes a sign-in screen first. */
    val isInitialized: Flow<Boolean>
}

internal fun Throwable.toAuthError(): AuthError = when {
    this is AuthError -> this
    message?.contains("invalid", ignoreCase = true) == true &&
        message?.contains("credential", ignoreCase = true) == true -> AuthError.InvalidCredentials
    message?.contains("already registered", ignoreCase = true) == true ||
        message?.contains("already exists", ignoreCase = true) == true -> AuthError.EmailAlreadyInUse
    message?.contains("password", ignoreCase = true) == true &&
        message?.contains("weak", ignoreCase = true) == true -> AuthError.WeakPassword
    message?.contains("network", ignoreCase = true) == true ||
        message?.contains("timeout", ignoreCase = true) == true -> AuthError.NetworkUnavailable
    else -> AuthError.Unknown(message ?: "unknown_auth_error")
}
