package com.wassalni.app

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import com.wassalni.app.auth.SessionViewModel
import com.wassalni.app.auth.SettingsViewModel
import com.wassalni.app.navigation.Route
import com.wassalni.app.ui.auth.AuthScreen
import com.wassalni.app.ui.auth.DisplayNameScreen
import com.wassalni.app.ui.auth.SuspendedScreen
import com.wassalni.app.ui.home.HomePlaceholderScreen
import com.wassalni.app.ui.settings.SettingsScreen
import com.wassalni.core.data.auth.needsDisplayName
import com.wassalni.core.model.SessionState

/**
 * The root of the app's navigation. [SessionState] decides which of four
 * shapes the screen takes; individual screens never make this decision
 * themselves, which is what makes the suspended-account gate and the
 * display-name gate actually enforceable rather than merely conventional.
 *
 * [SessionState.Suspended] is deliberately rendered with NO [NavHost] around
 * it at all — not just "no button leads anywhere" but structurally no route
 * exists to navigate to. Everything else lives inside a NavHost.
 */
@Composable
fun WassalniApp(sessionViewModel: SessionViewModel = hiltViewModel()) {
    val sessionState by sessionViewModel.sessionState.collectAsState()

    when (val state = sessionState) {
        is SessionState.Loading -> LoadingScreen()

        is SessionState.Suspended -> {
            val settingsViewModel: SettingsViewModel = hiltViewModel()
            SuspendedScreen(reason = state.reason, onSignOut = settingsViewModel::signOut)
        }

        is SessionState.SignedOut -> {
            val navController = rememberNavController()
            NavHost(navController = navController, startDestination = Route.Auth) {
                composable<Route.Auth> {
                    // No explicit navigation call needed: a successful sign-in
                    // changes auth.sessionStatus, sessionState above picks it up,
                    // and this whole `when` re-evaluates to SignedIn.
                    AuthScreen(onSignedIn = {})
                }
            }
        }

        is SessionState.SignedIn -> {
            if (state.profile.needsDisplayName()) {
                DisplayNameScreen(onDone = {})
            } else {
                val navController = rememberNavController()
                NavHost(navController = navController, startDestination = Route.Home) {
                    composable<Route.Home> {
                        HomePlaceholderScreen(onSettingsClick = { navController.navigate(Route.Settings) })
                    }
                    composable<Route.Settings> {
                        SettingsScreen(onSignedOut = { navController.popBackStack() })
                    }
                }
            }
        }
    }
}

@Composable
private fun LoadingScreen() {
    Scaffold { innerPadding ->
        Box(
            modifier = Modifier.fillMaxSize().padding(innerPadding),
            contentAlignment = Alignment.Center,
        ) {
            CircularProgressIndicator()
        }
    }
}
