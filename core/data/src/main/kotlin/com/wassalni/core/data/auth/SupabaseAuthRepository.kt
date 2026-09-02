package com.wassalni.core.data.auth

import io.github.jan.supabase.auth.Auth
import io.github.jan.supabase.auth.status.SessionStatus
import io.github.jan.supabase.auth.providers.Google
import io.github.jan.supabase.auth.providers.builtin.Email
import io.github.jan.supabase.auth.providers.builtin.IDToken
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class SupabaseAuthRepository @Inject constructor(
    private val auth: Auth,
) : AuthRepository {

    override fun currentUserId(): String? = auth.currentUserOrNull()?.id

    override suspend fun signUpWithEmail(email: String, password: String): Result<Unit> =
        runCatching {
            auth.signUpWith(Email) {
                this.email = email
                this.password = password
            }
        }.mapCatchingAuthError()

    override suspend fun signInWithEmail(email: String, password: String): Result<Unit> =
        runCatching {
            auth.signInWith(Email) {
                this.email = email
                this.password = password
            }
        }.mapCatchingAuthError()

    override suspend fun signInWithGoogleIdToken(idToken: String, rawNonce: String): Result<Unit> =
        runCatching {
            auth.signInWith(IDToken) {
                this.idToken = idToken
                this.provider = Google
                this.nonce = rawNonce
            }
        }.mapCatchingAuthError()

    override suspend fun signOut(): Result<Unit> = runCatching { auth.signOut() }.mapCatchingAuthError()

    override val isInitialized: Flow<Boolean>
        get() = auth.sessionStatus.map { it !is SessionStatus.Initializing }

    private fun <T> Result<T>.mapCatchingAuthError(): Result<Unit> =
        fold(
            onSuccess = { Result.success(Unit) },
            onFailure = { Result.failure(it.toAuthError()) },
        )
}
