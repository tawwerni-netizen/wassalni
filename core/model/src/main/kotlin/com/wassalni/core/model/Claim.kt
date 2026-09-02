package com.wassalni.core.model

import kotlinx.datetime.Instant

data class Profile(
    val id: String,
    val displayName: String,
    val communityId: String?,
    val role: UserRole,
    val isSuspended: Boolean,
    val returnsCount: Int,
)

/**
 * P2. Only ever fetched by the report owner (the finder). There is no code path
 * that hands a [VerificationQuestion.expectedAnswer] to a claimant — which is
 * why the claimant-facing type below carries the question text alone.
 */
data class VerificationQuestion(
    val id: String,
    val reportId: String,
    val question: String,
    val expectedAnswer: String,
    val sortOrder: Int,
)

/** What a claimant sees: the question, never the answer. */
data class VerificationPrompt(
    val id: String,
    val question: String,
    val sortOrder: Int,
)

data class Claim(
    val id: String,
    val reportId: String,
    val claimantId: String,
    val claimantDisplayName: String,
    val status: ClaimStatus,
    val rejectionNote: String?,
    val finderConfirmedAt: Instant?,
    val claimantConfirmedAt: Instant?,
    val answers: List<ClaimAnswer> = emptyList(),
    val createdAt: Instant,
    val updatedAt: Instant,
) {
    val bothConfirmed: Boolean
        get() = finderConfirmedAt != null && claimantConfirmedAt != null

    /** True when this side has confirmed and is waiting on the other. */
    fun awaitingCounterpart(viewerIsFinder: Boolean): Boolean =
        if (viewerIsFinder) finderConfirmedAt != null && claimantConfirmedAt == null
        else claimantConfirmedAt != null && finderConfirmedAt == null
}

/**
 * An answer submitted by a claimant. [gradedCorrect] is set by the FINDER.
 *
 * The system never grades: real answers vary too much ("أزرق" vs "ازرق فاتح")
 * for an automatic comparison to be fair, and auto-grading would mean the
 * server holds the secret in a form that can be brute-forced by submitting
 * guesses. A similarity hint may be shown to the finder, but the decision is
 * always theirs.
 */
data class ClaimAnswer(
    val id: String,
    val detailId: String,
    val question: String,
    val answer: String,
    val gradedCorrect: Boolean?,
)

/**
 * A suggestion, not a verdict. Carries [reasons] and never a score — see
 * [MatchReason].
 */
data class MatchCandidate(
    val id: String,
    val reportId: String,
    val candidate: Report,
    val reasons: List<MatchReason>,
    val dismissedAt: Instant?,
)
