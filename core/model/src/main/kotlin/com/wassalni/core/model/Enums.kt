package com.wassalni.core.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * LOST and FOUND are not mirror images. A LOST report *should* be detailed —
 * detail helps a finder recognise the item. A FOUND report must be deliberately
 * vague, because public detail lets an impostor describe an item they never saw.
 * The composer coaches differently per type; see [ReportType.coachingIsRestrictive].
 */
@Serializable
enum class ReportType {
    @SerialName("lost") LOST,
    @SerialName("found") FOUND;

    /** FOUND reporters must be told to hold identifying detail back. */
    val coachingIsRestrictive: Boolean get() = this == FOUND

    val opposite: ReportType get() = if (this == LOST) FOUND else LOST
}

@Serializable
enum class ReportStatus {
    @SerialName("open") OPEN,
    @SerialName("possible_match") POSSIBLE_MATCH,
    @SerialName("claim_in_progress") CLAIM_IN_PROGRESS,
    @SerialName("matched") MATCHED,
    @SerialName("returned") RETURNED,
    @SerialName("closed") CLOSED,
    @SerialName("removed") REMOVED;

    val isResolved: Boolean get() = this == RETURNED || this == CLOSED
    val isClaimable: Boolean get() = this == OPEN || this == POSSIBLE_MATCH || this == CLAIM_IN_PROGRESS
}

@Serializable
enum class ClaimStatus {
    @SerialName("pending") PENDING,
    @SerialName("verifying") VERIFYING,
    @SerialName("approved") APPROVED,
    @SerialName("rejected") REJECTED,
    @SerialName("withdrawn") WITHDRAWN,
    @SerialName("expired") EXPIRED;

    val isLive: Boolean get() = this == PENDING || this == VERIFYING || this == APPROVED
}

@Serializable
enum class CommunityKind {
    @SerialName("country") COUNTRY,
    @SerialName("governorate") GOVERNORATE,
    @SerialName("city") CITY,
    @SerialName("district") DISTRICT,
    @SerialName("campus") CAMPUS,
    @SerialName("mall") MALL,
    @SerialName("compound") COMPOUND,
    @SerialName("workplace") WORKPLACE;

    /** Reports attach to venues and districts, never to a governorate or the country. */
    val isReportable: Boolean get() = this != COUNTRY && this != GOVERNORATE
}

@Serializable
enum class TimeBucket {
    @SerialName("early_morning") EARLY_MORNING,
    @SerialName("morning") MORNING,
    @SerialName("afternoon") AFTERNOON,
    @SerialName("evening") EVENING,
    @SerialName("night") NIGHT,
    @SerialName("unknown") UNKNOWN,
}

@Serializable
enum class UserRole {
    @SerialName("user") USER,
    @SerialName("moderator") MODERATOR,
    @SerialName("admin") ADMIN;

    val isStaff: Boolean get() = this != USER
}

@Serializable
enum class ModerationReason {
    @SerialName("scam") SCAM,
    @SerialName("fake_report") FAKE_REPORT,
    @SerialName("dangerous") DANGEROUS,
    @SerialName("inappropriate") INAPPROPRIATE,
    @SerialName("privacy") PRIVACY,
}

/**
 * Why the system thinks two reports might be related.
 *
 * These are rendered as chips. The numeric score behind them is deliberately
 * NOT part of this model — it never crosses the network to the client, because
 * a number reads as certainty and this is a heuristic.
 */
@Serializable
enum class MatchReason {
    @SerialName("same_category") SAME_CATEGORY,
    @SerialName("similar_category") SIMILAR_CATEGORY,
    @SerialName("same_area") SAME_AREA,
    @SerialName("same_community") SAME_COMMUNITY,
    @SerialName("nearby_place") NEARBY_PLACE,
    @SerialName("same_governorate") SAME_GOVERNORATE,
    @SerialName("same_day") SAME_DAY,
    @SerialName("close_date") CLOSE_DATE,
    @SerialName("nearby_date") NEARBY_DATE,
    @SerialName("same_color") SAME_COLOR,
    @SerialName("similar_color") SIMILAR_COLOR,
    @SerialName("similar_description") SIMILAR_DESCRIPTION,
    @SerialName("same_brand") SAME_BRAND,
}
