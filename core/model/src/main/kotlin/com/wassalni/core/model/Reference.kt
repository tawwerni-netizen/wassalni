package com.wassalni.core.model

/**
 * Server-driven, not a Kotlin enum: categories must be addable without shipping
 * an app release. [groupKey] lets related categories score a partial match —
 * a phone reported under "electronics" should still surface.
 */
data class Category(
    val id: String,
    val groupKey: String,
    val nameAr: String,
    val nameEn: String,
    val iconKey: String?,
    val sortOrder: Int,
)

data class ItemColor(
    val id: String,
    val nameAr: String,
    val nameEn: String,
    val hex: String,
)
