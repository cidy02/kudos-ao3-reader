package io.github.cidy02.kudos.works.detail

import org.junit.Assert.assertEquals
import org.junit.Test

class WorkDetailDatesTest {
    // WorkStatLabelTests displayDate assertions.
    @Test fun recognizedAO3DatesUseTheDisplayDateFormatter() {
        assertEquals("11/01/2025", WorkDetailDates.displayDate("2025-11-01"))
        assertEquals("11/01/2025", WorkDetailDates.displayDate("01 Nov 2025"))
        assertEquals("not a date", WorkDetailDates.displayDate("not a date"))
        assertEquals("2025-02-30", WorkDetailDates.displayDate("2025-02-30"))
        assertEquals("", WorkDetailDates.displayDate(""))
    }
}
