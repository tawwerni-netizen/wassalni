package com.wassalni.core.designsystem

import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Immutable
import androidx.compose.ui.graphics.Color

// Brand: a warm teal. Reads as calm and civic rather than alarming — the app is
// used by people who have just lost something and are already stressed.
private val Teal40 = Color(0xFF16716B)
private val Teal80 = Color(0xFF7BD7CE)
private val Teal90 = Color(0xFF9CF2E8)
private val Teal10 = Color(0xFF00201D)

private val Sand40 = Color(0xFF7A5900)
private val Sand80 = Color(0xFFEEC148)
private val Sand10 = Color(0xFF251A00)

private val Red40 = Color(0xFFB3261E)
private val Red80 = Color(0xFFF2B8B5)

internal val WassalniLightColors = lightColorScheme(
    primary = Teal40,
    onPrimary = Color.White,
    primaryContainer = Teal90,
    onPrimaryContainer = Teal10,
    secondary = Sand40,
    onSecondary = Color.White,
    secondaryContainer = Sand80,
    onSecondaryContainer = Sand10,
    error = Red40,
    onError = Color.White,
    background = Color(0xFFFBFDFB),
    onBackground = Color(0xFF191C1B),
    surface = Color(0xFFFBFDFB),
    onSurface = Color(0xFF191C1B),
    surfaceVariant = Color(0xFFDAE5E2),
    onSurfaceVariant = Color(0xFF3F4947),
    outline = Color(0xFF6F7977),
)

internal val WassalniDarkColors = darkColorScheme(
    primary = Teal80,
    onPrimary = Color(0xFF003733),
    primaryContainer = Color(0xFF005049),
    onPrimaryContainer = Teal90,
    secondary = Sand80,
    onSecondary = Color(0xFF402D00),
    secondaryContainer = Color(0xFF5C4300),
    onSecondaryContainer = Color(0xFFFFDF9B),
    error = Red80,
    onError = Color(0xFF601410),
    background = Color(0xFF111413),
    onBackground = Color(0xFFE0E3E1),
    surface = Color(0xFF111413),
    onSurface = Color(0xFFE0E3E1),
    surfaceVariant = Color(0xFF3F4947),
    onSurfaceVariant = Color(0xFFBEC9C6),
    outline = Color(0xFF899391),
)

/**
 * LOST and FOUND must be distinguishable at a glance in a mixed feed, and they
 * carry meaning the Material roles do not. They live here as semantic tokens so
 * no screen hardcodes "red means lost".
 *
 * Colour is never the *only* signal: every place these are used also carries an
 * icon and a text label, because roughly 1 in 12 men has a colour vision
 * deficiency and red/green is the worst possible pair for it.
 */
@Immutable
data class ReportTypeColors(
    val lostContainer: Color,
    val onLostContainer: Color,
    val foundContainer: Color,
    val onFoundContainer: Color,
)

internal val LightReportTypeColors = ReportTypeColors(
    lostContainer = Color(0xFFFFDAD6),
    onLostContainer = Color(0xFF410002),
    foundContainer = Color(0xFFC6EFC8),
    onFoundContainer = Color(0xFF002106),
)

internal val DarkReportTypeColors = ReportTypeColors(
    lostContainer = Color(0xFF680006),
    onLostContainer = Color(0xFFFFDAD6),
    foundContainer = Color(0xFF00390C),
    onFoundContainer = Color(0xFFC6EFC8),
)
