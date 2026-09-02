package com.wassalni.core.model

/**
 * A node in the community tree:
 * country -> governorate -> city/district -> campus|mall|compound|workplace.
 *
 * [ancestorIds] contains this node plus every ancestor, so "is X inside scope S"
 * is a single containment check on the client and a single indexed predicate on
 * the server.
 */
data class Community(
    val id: String,
    val slug: String,
    val nameAr: String,
    val nameEn: String,
    val kind: CommunityKind,
    val parentId: String?,
    val ancestorIds: List<String>,
    val depth: Int,
    val isReportable: Boolean,
    val isActive: Boolean,
) {
    fun isInside(scopeId: String): Boolean = scopeId in ancestorIds
}

/** A curated landmark inside a venue. Never free text — that is what keeps
 *  "same area" a meaningful match signal and keeps home addresses out. */
data class Area(
    val id: String,
    val communityId: String,
    val nameAr: String,
    val nameEn: String,
    val sortOrder: Int,
)

/**
 * How wide the user wants to look. The feed defaults to [Venue]; widening walks
 * up the tree. Search is national; automatic matching is not (see the
 * governorate bound in the matching design).
 */
sealed interface SearchScope {
    val communityId: String?

    /** Just my campus / mall / compound / workplace. */
    data class Venue(override val communityId: String) : SearchScope

    /** My city or district. */
    data class District(override val communityId: String) : SearchScope

    /** My governorate. */
    data class Governorate(override val communityId: String) : SearchScope

    /** All of Egypt. */
    data class Country(override val communityId: String) : SearchScope
}

data class ReportFilters(
    val query: String? = null,
    val type: ReportType? = null,
    val categoryId: String? = null,
    val areaId: String? = null,
    val colorId: String? = null,
    val fromDate: kotlinx.datetime.LocalDate? = null,
    val toDate: kotlinx.datetime.LocalDate? = null,
) {
    val isEmpty: Boolean
        get() = query.isNullOrBlank() && type == null && categoryId == null &&
            areaId == null && colorId == null && fromDate == null && toDate == null
}
