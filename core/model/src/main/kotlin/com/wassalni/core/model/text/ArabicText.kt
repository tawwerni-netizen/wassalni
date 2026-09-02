package com.wassalni.core.model.text

/**
 * Arabic text handling shared by search, matching hints, and the privacy guard.
 *
 * [normalize] MUST stay behaviourally identical to `wassalni_normalize_ar()` in
 * `db/migrations/0001_init.sql`. If the two drift, the client will show a user
 * matches the server will not find, which reads as the app being broken. The
 * unit tests in `ArabicTextTest` are the contract; mirror any change into both.
 */
object ArabicText {

    // U+064B..U+0652 tashkeel, U+0640 tatweel, U+0670 superscript alef
    private val DIACRITICS = Regex("[\u064B-\u0652\u0640\u0670]")
    private val NON_ALNUM = Regex("[^\\p{L}\\p{N} ]")
    private val WHITESPACE = Regex("\\s+")

    private const val FROM = "أإآٱةىؤئ٠١٢٣٤٥٦٧٨٩"
    private const val TO = "ااااهيوي0123456789"

    fun normalize(input: String?): String {
        if (input.isNullOrBlank()) return ""
        val stripped = DIACRITICS.replace(input.lowercase(), "")
        val folded = buildString(stripped.length) {
            for (ch in stripped) {
                val i = FROM.indexOf(ch)
                append(if (i >= 0) TO[i] else ch)
            }
        }
        return WHITESPACE.replace(NON_ALNUM.replace(folded, " "), " ").trim()
    }

    /**
     * Mirrors `wassalni_contains_sensitive_number()`.
     *
     * Eight or more digits in a row — separators allowed — is the shape of a
     * national ID (14), a phone number (11), or a card number (16), and none of
     * those belong in a lost-and-found report. Shorter runs are left alone so
     * prices, years, model numbers and "iPhone 13" still work.
     *
     * The client check exists so the user gets a clear Arabic explanation
     * instead of a server error. It is NOT the enforcement point — the database
     * trigger is, because a modified client can skip this.
     */
    fun containsSensitiveNumber(input: String?): Boolean {
        if (input.isNullOrBlank()) return false
        return LONG_DIGIT_RUN.containsMatchIn(input) || IBAN.containsMatchIn(input)
    }

    private val LONG_DIGIT_RUN = Regex("[0-9\u0660-\u0669](?:[ \\-]?[0-9\u0660-\u0669]){7,}")
    private val IBAN = Regex("\\bEG[0-9]{2}[A-Z0-9]{10,}\\b", RegexOption.IGNORE_CASE)

    /**
     * Cheap similarity used only for the finder's grading hint. Deliberately not
     * a decision function: it suggests, the finder decides.
     */
    fun roughSimilarity(a: String?, b: String?): Float {
        val x = normalize(a)
        val y = normalize(b)
        if (x.isEmpty() || y.isEmpty()) return 0f
        if (x == y) return 1f
        val xs = trigrams(x)
        val ys = trigrams(y)
        if (xs.isEmpty() || ys.isEmpty()) return 0f
        val shared = xs.intersect(ys).size.toFloat()
        return shared / (xs.size + ys.size - shared)
    }

    private fun trigrams(s: String): Set<String> {
        val padded = "  $s "
        if (padded.length < 3) return emptySet()
        return (0..padded.length - 3).mapTo(mutableSetOf()) { padded.substring(it, it + 3) }
    }
}
