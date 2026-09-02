package com.wassalni.core.designsystem

import androidx.compose.material3.Typography
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.LineHeightStyle
import androidx.compose.ui.unit.sp

/**
 * Arabic-first type ramp.
 *
 * Arabic script needs more vertical room than Latin at the same point size —
 * ascenders, descenders and dot positioning all sit further out — so line
 * heights here are looser than the Material defaults. Cramped Arabic is the
 * single most common way an app reads as "translated" rather than native.
 *
 * TODO(M0): swap [WassalniFontFamily] for Cairo or IBM Plex Sans Arabic once the
 * font files are added to res/font. FontFamily.Default falls back to the
 * platform Arabic face, which is legible but generic.
 */
private val WassalniFontFamily = FontFamily.Default

private val lineHeightStyle = LineHeightStyle(
    alignment = LineHeightStyle.Alignment.Center,
    trim = LineHeightStyle.Trim.None,
)

private fun style(size: Int, height: Int, weight: FontWeight) = TextStyle(
    fontFamily = WassalniFontFamily,
    fontWeight = weight,
    fontSize = size.sp,
    lineHeight = height.sp,
    lineHeightStyle = lineHeightStyle,
)

val WassalniTypography = Typography(
    displaySmall = style(36, 48, FontWeight.Bold),
    headlineLarge = style(30, 42, FontWeight.Bold),
    headlineMedium = style(26, 36, FontWeight.Bold),
    headlineSmall = style(22, 32, FontWeight.SemiBold),
    titleLarge = style(20, 30, FontWeight.SemiBold),
    titleMedium = style(17, 26, FontWeight.SemiBold),
    titleSmall = style(15, 24, FontWeight.Medium),
    bodyLarge = style(17, 28, FontWeight.Normal),
    bodyMedium = style(15, 25, FontWeight.Normal),
    bodySmall = style(13, 22, FontWeight.Normal),
    labelLarge = style(15, 22, FontWeight.Medium),
    labelMedium = style(13, 20, FontWeight.Medium),
    labelSmall = style(11, 18, FontWeight.Medium),
)
