package com.wassalni.core.data.remote

import com.wassalni.core.data.BuildConfig

/**
 * Build-time Supabase configuration.
 *
 * The anon key is public by design: it identifies the project, it does not
 * authorise anything. Row Level Security is the security boundary, so shipping
 * this key in the APK is expected and safe. The *service role* key bypasses RLS
 * entirely and must never appear in this module, in any resource, or in git —
 * it lives only in Edge Function environment variables.
 */
object SupabaseConfig {
    val url: String = BuildConfig.SUPABASE_URL
    val anonKey: String = BuildConfig.SUPABASE_ANON_KEY

    val isConfigured: Boolean
        get() = url.isNotBlank() && anonKey.isNotBlank()

    /**
     * Fails loudly at startup rather than surfacing as an opaque network error
     * on the first query. A missing local.properties is the single most common
     * first-run problem on a new machine.
     */
    fun requireConfigured() {
        check(isConfigured) {
            "Supabase is not configured. Copy local.properties.template to " +
                "local.properties and set SUPABASE_URL and SUPABASE_ANON_KEY. " +
                "See README.md."
        }
        check(!anonKey.startsWith("eyJ") || anonKey.count { it == '.' } == 2) {
            "SUPABASE_ANON_KEY does not look like a JWT."
        }
    }
}
