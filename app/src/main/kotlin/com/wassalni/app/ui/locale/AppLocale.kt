package com.wassalni.app.ui.locale

import androidx.appcompat.app.AppCompatDelegate
import androidx.core.os.LocaleListCompat

/**
 * The app ships in Arabic and the user can switch to English.
 *
 * Arabic is the *default*, not a forced setting: `values/` holds Arabic and
 * `locales_config.xml` declares `ar` as the default locale, so a fresh install
 * is Arabic even on an English phone. Switching to English must also flip the
 * layout to LTR — which is why [com.wassalni.core.designsystem.WassalniTheme]
 * follows the active locale instead of pinning RTL.
 *
 * `setApplicationLocales` is persisted by the framework on API 33+ and by
 * AppCompat's `autoStoreLocales` service below that, so the choice survives a
 * restart without us storing it ourselves.
 */
enum class AppLocale(val tag: String, val nativeName: String) {
    ARABIC("ar", "العربية"),
    ENGLISH("en", "English");

    companion object {
        val default = ARABIC

        fun current(): AppLocale {
            val tag = AppCompatDelegate.getApplicationLocales()
                .toLanguageTags()
                .substringBefore(',')
                .substringBefore('-')
            return entries.firstOrNull { it.tag == tag } ?: default
        }

        fun apply(locale: AppLocale) {
            AppCompatDelegate.setApplicationLocales(
                LocaleListCompat.forLanguageTags(locale.tag)
            )
        }
    }
}
