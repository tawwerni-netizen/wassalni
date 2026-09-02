package com.wassalni.core.model

import kotlinx.datetime.Instant
import kotlinx.datetime.LocalDate

/**
 * A report as the rest of the app sees it. Every field here is P0 — public to
 * any signed-in user nationwide.
 *
 * P1 (the location hint) lives in [ReportPrivateDetails] and P2 (verification
 * questions) in [VerificationQuestion], both fetched separately and both gated
 * by their own RLS policies. They are deliberately not nullable fields on this
 * class: an optional field on a public model is how private data leaks into a
 * feed by accident.
 */
data class Report(
    val id: String,
    val profileId: String?,           // null once the author deletes their account
    val authorDisplayName: String,
    val type: ReportType,
    val status: ReportStatus,
    val communityId: String,
    val communityName: String,
    val governorateId: String?,
    val areaId: String?,
    val areaName: String?,
    val categoryId: String,
    val colorId: String?,
    val brand: String?,
    val title: String,
    val description: String,
    val occurredOn: LocalDate,
    val timeBucket: TimeBucket?,
    val images: List<ReportImage> = emptyList(),
    val createdAt: Instant,
    val updatedAt: Instant,
) {
    /**
     * Ownership is a function of *who is asking*, so it takes the viewer rather
     * than reading ambient state. A mutable "current user" global would make
     * this model untestable and would silently answer wrong during sign-out.
     */
    fun isOwnedBy(viewerProfileId: String?): Boolean =
        profileId != null && profileId == viewerProfileId
}

data class ReportImage(
    val id: String,
    val storagePath: String,
    val isPublic: Boolean,
)

/** P1. Only ever populated for the report owner or an approved counterparty. */
data class ReportPrivateDetails(
    val reportId: String,
    val locationHint: String?,
)

/**
 * A report being composed. Held in Room so a half-written report survives the
 * process being killed — losing a description someone spent two minutes on is
 * how you lose the report entirely.
 */
data class ReportDraft(
    val id: String,
    val type: ReportType,
    val communityId: String? = null,
    val areaId: String? = null,
    val categoryId: String? = null,
    val colorId: String? = null,
    val brand: String? = null,
    val title: String = "",
    val description: String = "",
    val locationHint: String? = null,
    val occurredOn: LocalDate? = null,
    val timeBucket: TimeBucket? = null,
    val localImagePaths: List<String> = emptyList(),
    /** FOUND only: the questions a claimant will have to answer. */
    val verificationQuestions: List<DraftVerificationQuestion> = emptyList(),
    val updatedAt: Instant,
) {
    val isSubmittable: Boolean
        get() = communityId != null &&
            categoryId != null &&
            occurredOn != null &&
            title.length in 3..80 &&
            description.length in 10..1000 &&
            (type == ReportType.LOST || verificationQuestions.isNotEmpty())
}

data class DraftVerificationQuestion(
    val question: String,
    val expectedAnswer: String,
)
