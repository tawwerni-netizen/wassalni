package com.wassalni.core.model.text

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * These tests are the contract between [ArabicText] and `wassalni_normalize_ar()`
 * / `wassalni_contains_sensitive_number()` in the SQL migrations. Any change here
 * must be mirrored there, and vice versa.
 */
class ArabicTextTest {

    // --- normalisation -----------------------------------------------------

    @Test
    fun `folds taa marbuta so mahfaza matches either spelling`() {
        assertEquals(ArabicText.normalize("محفظة"), ArabicText.normalize("محفظه"))
    }

    @Test
    fun `folds alef variants`() {
        val target = ArabicText.normalize("احمد")
        assertEquals(target, ArabicText.normalize("أحمد"))
        assertEquals(target, ArabicText.normalize("إحمد"))
        assertEquals(target, ArabicText.normalize("آحمد"))
    }

    @Test
    fun `folds alef maqsura to yaa`() {
        assertEquals(ArabicText.normalize("مصطفي"), ArabicText.normalize("مصطفى"))
    }

    @Test
    fun `strips tashkeel`() {
        assertEquals(ArabicText.normalize("مفتاح"), ArabicText.normalize("مِفْتَاح"))
    }

    @Test
    fun `strips tatweel`() {
        assertEquals(ArabicText.normalize("مفتاح"), ArabicText.normalize("مفـــتاح"))
    }

    @Test
    fun `folds arabic indic digits to latin`() {
        assertEquals("iphone 13", ArabicText.normalize("iPhone ١٣"))
    }

    @Test
    fun `collapses punctuation and whitespace`() {
        assertEquals("محفظه جلد بني", ArabicText.normalize("  محفظة،  جلد   بني!! "))
    }

    @Test
    fun `empty and null normalise to empty`() {
        assertEquals("", ArabicText.normalize(null))
        assertEquals("", ArabicText.normalize("   "))
    }

    // --- the privacy guard -------------------------------------------------

    @Test
    fun `flags a national id`() {
        assertTrue(ArabicText.containsSensitiveNumber("رقمي القومي 29801011234567"))
    }

    @Test
    fun `flags an egyptian mobile number`() {
        assertTrue(ArabicText.containsSensitiveNumber("كلمني على 01012345678"))
    }

    @Test
    fun `flags a spaced card number`() {
        assertTrue(ArabicText.containsSensitiveNumber("4111 1111 1111 1111"))
    }

    @Test
    fun `flags a dashed card number`() {
        assertTrue(ArabicText.containsSensitiveNumber("4111-1111-1111-1111"))
    }

    @Test
    fun `flags arabic indic digits too`() {
        assertTrue(ArabicText.containsSensitiveNumber("٠١٠١٢٣٤٥٦٧٨"))
    }

    @Test
    fun `flags an egyptian iban`() {
        assertTrue(ArabicText.containsSensitiveNumber("EG380019000500000000263180002"))
    }

    // False positives are the expensive failure here: a guard that blocks
    // ordinary descriptions trains users to write nothing.

    @Test
    fun `allows a year`() {
        assertFalse(ArabicText.containsSensitiveNumber("موديل 2024"))
    }

    @Test
    fun `allows a price`() {
        assertFalse(ArabicText.containsSensitiveNumber("حوالي 1500 جنيه"))
    }

    @Test
    fun `allows a model number`() {
        assertFalse(ArabicText.containsSensitiveNumber("iPhone 13 Pro Max 256"))
    }

    @Test
    fun `allows a date written with slashes`() {
        assertFalse(ArabicText.containsSensitiveNumber("ضاعت يوم 12/5/2026"))
    }

    @Test
    fun `allows a building and room number`() {
        assertFalse(ArabicText.containsSensitiveNumber("مبنى 5 قاعة 302"))
    }

    // --- similarity hint ---------------------------------------------------

    @Test
    fun `identical answers score one`() {
        assertEquals(1f, ArabicText.roughSimilarity("أزرق", "ازرق"), 0.001f)
    }

    @Test
    fun `related answers score above zero`() {
        assertTrue(ArabicText.roughSimilarity("ازرق فاتح", "ازرق") > 0.3f)
    }

    @Test
    fun `unrelated answers score low`() {
        assertTrue(ArabicText.roughSimilarity("احمر", "جلد بني") < 0.2f)
    }
}
