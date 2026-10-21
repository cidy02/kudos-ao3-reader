package io.github.cidy02.kudos.reader.speech

/** sherpa-onnx lexicon rows are a word followed by space-separated tokens from tokens.txt. */
internal object KokoroPronunciationLexicon {
    fun render(corrections: Map<String, String>, tokens: Set<String>): String = corrections.toSortedMap()
        .mapNotNull { (word, ipa) ->
            // Keep every original entry in the JSON/backup. Unsafe rows or unsupported IPA
            // must not inject another row, or turn into a partially pronounced word.
            if (word.isEmpty() || word.any { it.isWhitespace() || Character.isSpaceChar(it) || it.isISOControl() }) {
                return@mapNotNull null
            }
            val phonemes = ipa.codePoints().toArray().map { String(Character.toChars(it)) }
                .filterNot { it.isBlank() }
            if (phonemes.isEmpty() || phonemes.any { it !in tokens }) return@mapNotNull null
            "$word ${phonemes.joinToString(" ")}\n"
        }.joinToString("")
}
