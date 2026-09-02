package com.wassalni.core.designsystem

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.unit.LayoutDirection

private val LocalReportTypeColors = staticCompositionLocalOf { LightReportTypeColors }

object WassalniTheme {
    val reportTypeColors: ReportTypeColors
        @Composable @ReadOnlyComposable get() = LocalReportTypeColors.current

    val spacing: Spacing
        @Composable @ReadOnlyComposable get() = LocalSpacing.current
}

/**
 * The app is Arabic-first, so RTL is the default rather than something derived
 * from the device locale. A user whose phone is set to English still gets an
 * Arabic RTL app unless they choose otherwise — that is the intended product
 * behaviour, not an accident.
 *
 * [forceLayoutDirection] exists so previews and screenshot tests can assert the
 * LTR rendering too; every screen must be checked in both.
 */
@Composable
fun WassalniTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    forceLayoutDirection: LayoutDirection? = LayoutDirection.Rtl,
    content: @Composable () -> Unit,
) {
    val colorScheme = if (darkTheme) WassalniDarkColors else WassalniLightColors
    val typeColors = if (darkTheme) DarkReportTypeColors else LightReportTypeColors
    val direction = forceLayoutDirection ?: LocalLayoutDirection.current

    CompositionLocalProvider(
        LocalReportTypeColors provides typeColors,
        LocalSpacing provides Spacing(),
        LocalLayoutDirection provides direction,
    ) {
        MaterialTheme(
            colorScheme = colorScheme,
            typography = WassalniTypography,
            content = content,
        )
    }
}
