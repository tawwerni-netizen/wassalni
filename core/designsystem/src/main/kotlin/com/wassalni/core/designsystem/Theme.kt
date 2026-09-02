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
 * Arabic is the app's default language, and the user can switch to English.
 *
 * Layout direction therefore FOLLOWS THE ACTIVE LOCALE — it is not pinned to
 * RTL. Arabic is the default because `values/` holds Arabic and the app
 * declares `ar` as its default locale, so a fresh install is RTL; switching to
 * English must flip the whole layout to LTR, or the English mode reads as
 * broken. Pinning RTL here would have made the language switch cosmetic.
 *
 * [overrideLayoutDirection] is for previews and screenshot tests only, so both
 * directions can be asserted without changing the device locale. Leave it null
 * in production code.
 */
@Composable
fun WassalniTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    overrideLayoutDirection: LayoutDirection? = null,
    content: @Composable () -> Unit,
) {
    val colorScheme = if (darkTheme) WassalniDarkColors else WassalniLightColors
    val typeColors = if (darkTheme) DarkReportTypeColors else LightReportTypeColors
    // LocalLayoutDirection already reflects the active locale, so the null case
    // is a pass-through rather than a decision.
    val direction = overrideLayoutDirection ?: LocalLayoutDirection.current

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
