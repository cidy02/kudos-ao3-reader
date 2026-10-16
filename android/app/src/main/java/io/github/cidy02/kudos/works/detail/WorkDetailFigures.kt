package io.github.cidy02.kudos.works.detail

/** AO3's printed zero is a figure; an unpopulated local zero is not. */
object WorkDetailFigures {
    fun preferred(local: Int?, remote: Int?): Int? = remote ?: local?.takeIf { it > 0 }
}
