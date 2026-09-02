package com.wassalni.app.navigation

import kotlinx.serialization.Serializable

/**
 * Type-safe Navigation Compose routes. A sealed hierarchy rather than string
 * paths, so a typo in a route name is a compile error instead of a runtime
 * "destination not found."
 */
sealed interface Route {
    @Serializable data object Auth : Route
    @Serializable data object DisplayNameCapture : Route
    @Serializable data object Suspended : Route
    @Serializable data object Home : Route
    @Serializable data object Settings : Route
}
