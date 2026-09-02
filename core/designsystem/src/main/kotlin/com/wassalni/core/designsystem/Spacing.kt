package com.wassalni.core.designsystem

import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * A 4dp scale. Named rather than numeric so spacing decisions are reviewable —
 * `spacing.screen` says what it is for, `16.dp` does not.
 */
@Immutable
data class Spacing(
    val hairline: Dp = 1.dp,
    val xs: Dp = 4.dp,
    val sm: Dp = 8.dp,
    val md: Dp = 12.dp,
    val lg: Dp = 16.dp,
    val xl: Dp = 24.dp,
    val xxl: Dp = 32.dp,

    /** Horizontal padding for screen content. */
    val screen: Dp = 16.dp,

    /** Minimum touch target. Below this, people miss. */
    val touchTarget: Dp = 48.dp,
)

internal val LocalSpacing = staticCompositionLocalOf { Spacing() }
