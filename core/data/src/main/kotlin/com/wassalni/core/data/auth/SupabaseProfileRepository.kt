package com.wassalni.core.data.auth

import com.wassalni.core.model.Profile
import com.wassalni.core.model.SessionState
import com.wassalni.core.model.UserRole
import io.github.jan.supabase.auth.Auth
import io.github.jan.supabase.auth.status.SessionStatus
import io.github.jan.supabase.postgrest.Postgrest
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flow
import kotlinx.serialization.Serializable
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Mirrors `v_my_profile` — the self-only view, not the raw `profiles` table.
 * Kept private to this file: nothing outside the data layer should know the
 * database's column names.
 */
@Serializable
private data class MyProfileRow(
    val id: String,
    val display_name: String,
    val community_id: String?,
    val role: UserRole,
    val is_suspended: Boolean,
    val suspended_reason: String?,
    val returns_count: Int,
)

private fun MyProfileRow.toProfile() = Profile(
    id = id,
    displayName = display_name,
    communityId = community_id,
    role = role,
    isSuspended = is_suspended,
    returnsCount = returns_count,
)

@Singleton
class SupabaseProfileRepository @Inject constructor(
    private val auth: Auth,
    private val postgrest: Postgrest,
) : ProfileRepository {

    // Ticking this forces sessionState to re-fetch even though auth.sessionStatus
    // itself has not changed — see refresh() and the ProfileRepository doc.
    private val refreshTrigger = MutableStateFlow(0)

    override fun refresh() {
        refreshTrigger.value++
    }

    @OptIn(ExperimentalCoroutinesApi::class)
    override val sessionState: Flow<SessionState>
        get() = combine(auth.sessionStatus, refreshTrigger) { status, _ -> status }.flatMapLatest { status ->
            flow {
                when (status) {
                    is SessionStatus.Initializing -> emit(SessionState.Loading)

                    is SessionStatus.NotAuthenticated,
                    is SessionStatus.RefreshFailure,
                    -> emit(SessionState.SignedOut)

                    is SessionStatus.Authenticated -> {
                        val row = fetchMyProfileRow()
                        emit(
                            when {
                                // The signup trigger (0008) is effectively instant, but
                                // there is a brief window right after account creation
                                // where the row may not exist yet.
                                row == null -> SessionState.Loading
                                row.is_suspended -> SessionState.Suspended(row.suspended_reason)
                                else -> SessionState.SignedIn(row.toProfile())
                            }
                        )
                    }
                }
            }
        }

    override suspend fun setDisplayName(name: String): Result<Unit> = runCatching {
        val userId = auth.currentUserOrNull()?.id ?: error("not_signed_in")
        postgrest.from("profiles").update(
            { set("display_name", name) }
        ) {
            filter { eq("id", userId) }
        }
        Unit
    }

    override suspend fun anonymizeMyData(): Result<Unit> = runCatching {
        postgrest.rpc("anonymize_my_data")
        Unit
    }

    private suspend fun fetchMyProfileRow(): MyProfileRow? =
        postgrest.from("v_my_profile").select().decodeSingleOrNull<MyProfileRow>()
}
