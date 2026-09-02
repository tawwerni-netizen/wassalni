package com.wassalni.app.auth

import android.content.Context
import androidx.credentials.CredentialManager
import androidx.credentials.GetCredentialRequest
import androidx.credentials.exceptions.GetCredentialException
import com.google.android.libraries.identity.googleid.GetGoogleIdOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import com.google.android.libraries.identity.googleid.GoogleIdTokenParsingException
import java.security.MessageDigest
import java.util.UUID

/**
 * The Android-specific half of Google sign-in. Everything Supabase-specific
 * (feeding the resulting token into `auth.signInWith(IDToken)`) lives in
 * [com.wassalni.core.data.auth.AuthRepository] instead — this class only knows
 * about Credential Manager and Google's ID token format.
 *
 * Nonce handling matters and is easy to get backwards: the HASHED nonce goes
 * to Google (embedded in the token's `nonce` claim); the RAW nonce goes to
 * Supabase, which re-hashes it and compares. Sending the same value to both
 * makes every sign-in fail.
 */
class GoogleIdTokenProvider(private val context: Context) {

    data class Result(val idToken: String, val rawNonce: String)

    /**
     * @param webClientId the Google Cloud OAuth "Web application" client ID —
     * NOT the Android client ID. Credential Manager's native flow always uses
     * the web client as the audience.
     * @param filterByAuthorizedAccounts true to only offer Google accounts
     * that have signed into this app before (fast, silent-friendly); false to
     * show every account on the device. Callers should try `true` first and
     * fall back to `false` on [NoCredentialException]-shaped failures.
     */
    suspend fun requestIdToken(
        webClientId: String,
        filterByAuthorizedAccounts: Boolean,
    ): Result {
        val rawNonce = UUID.randomUUID().toString()
        val hashedNonce = sha256Hex(rawNonce)

        val option = GetGoogleIdOption.Builder()
            .setFilterByAuthorizedAccounts(filterByAuthorizedAccounts)
            .setServerClientId(webClientId)
            .setNonce(hashedNonce)
            .build()

        val request = GetCredentialRequest.Builder()
            .addCredentialOption(option)
            .build()

        val response = try {
            CredentialManager.create(context).getCredential(context, request)
        } catch (e: GetCredentialException) {
            throw GoogleSignInFailed(e)
        }

        val credential = try {
            GoogleIdTokenCredential.createFrom(response.credential.data)
        } catch (e: GoogleIdTokenParsingException) {
            throw GoogleSignInFailed(e)
        }

        return Result(idToken = credential.idToken, rawNonce = rawNonce)
    }

    private fun sha256Hex(value: String): String =
        MessageDigest.getInstance("SHA-256")
            .digest(value.toByteArray())
            .joinToString("") { "%02x".format(it) }
}

class GoogleSignInFailed(cause: Throwable) : Exception(cause)
