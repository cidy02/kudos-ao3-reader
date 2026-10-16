package io.github.cidy02.kudos.reader.speech

object TextChunker {
    fun chunk(text: String, maxLength: Int = 250): List<String> =
        makeChunks(text, maxLength.coerceAtLeast(1), separateSentences = false)

    fun sentenceChunks(text: String, maxLength: Int = 250): List<String> =
        makeChunks(text, maxLength.coerceAtLeast(1), separateSentences = true)

    private fun makeChunks(text: String, maxLength: Int, separateSentences: Boolean): List<String> {
        val chunks = mutableListOf<String>()
        val paragraphs = text.split('\n', '\r')

        for (paragraph in paragraphs) {
            val paragraphText = paragraph.trim()
            if (paragraphText.isEmpty()) continue

            if (!separateSentences && paragraphText.length <= maxLength) {
                chunks.add(paragraphText)
            } else {
                val sentences = splitIntoSentences(paragraphText, maxLength)
                if (separateSentences) {
                    chunks.addAll(sentences)
                    continue
                }
                var currentChunk = ""

                for (sentence in sentences) {
                    if (currentChunk.isEmpty()) {
                        currentChunk = sentence
                    } else if (currentChunk.length + sentence.length + 1 <= maxLength) {
                        currentChunk += " " + sentence
                    } else {
                        chunks.add(currentChunk)
                        currentChunk = sentence
                    }
                }
                if (currentChunk.isNotEmpty()) {
                    chunks.add(currentChunk)
                }
            }
        }
        return chunks
    }

    private fun splitIntoSentences(text: String, maxLength: Int): List<String> {
        val rawSentences = mutableListOf<String>()
        var start = 0
        var index = 0
        while (index < text.length) {
            val char = text[index]
            if (char in ".!?") {
                var end = index + 1
                while (end < text.length && text[end] in ".!?\"'”’)]") end++
                if ((end == text.length || text[end].isWhitespace()) &&
                    !(char == '.' && isAbbreviation(text.substring(start, index + 1)))) {
                    rawSentences.add(text.substring(start, end))
                    start = end
                    index = end - 1
                }
            }
            index++
        }
        if (start < text.length) rawSentences.add(text.substring(start))
        
        val sentences = mutableListOf<String>()
        for (rawSentence in rawSentences) {
            val sentence = rawSentence.trim()
            if (sentence.isEmpty()) continue
            
            if (sentence.length <= maxLength) {
                sentences.add(sentence)
            } else {
                sentences.addAll(splitByClauses(sentence, maxLength))
            }
        }
        return sentences
    }

    // English titles and dotted abbreviations must stay attached to their sentence.
    private fun isAbbreviation(prefix: String): Boolean {
        val token = prefix.takeLastWhile { !it.isWhitespace() }.trimStart('"', '\'', '“', '‘', '(')
        val lower = token.lowercase(java.util.Locale.ROOT)
        val dottedParts = token.removeSuffix(".").split('.')
        return lower in setOf("dr.", "mr.", "mrs.", "ms.", "prof.", "rev.", "st.", "jr.", "sr.", "vs.", "etc.") ||
            (token.length == 2 && token.first().isLetter()) ||
            (dottedParts.size > 1 && dottedParts.all { it.length == 1 && it.first().isLetter() })
    }

    private fun splitByClauses(text: String, maxLength: Int): List<String> {
        val delimiters = setOf(';', ':', '—', ',')
        val pieces = mutableListOf<String>()
        var currentPiece = StringBuilder()

        for (i in text.indices) {
            val char = text[i]
            currentPiece.append(char)

            if (delimiters.contains(char)) {
                if (currentPiece.length >= (maxLength / 2)) {
                    pieces.add(currentPiece.toString().trim())
                    currentPiece.clear()
                }
            }
        }

        val remaining = currentPiece.toString().trim()
        if (remaining.isNotEmpty()) {
            pieces.add(remaining)
        }

        return pieces.flatMap { piece ->
            if (piece.length <= maxLength) {
                listOf(piece)
            } else {
                splitByWords(piece, maxLength)
            }
        }.filter { it.isNotEmpty() }
    }

    private fun splitByWords(text: String, maxLength: Int): List<String> {
        val words = text.split(Regex("\\s+"))
        val pieces = mutableListOf<String>()
        var currentPiece = ""

        for (word in words) {
            if (currentPiece.isEmpty()) {
                currentPiece = word
            } else if (currentPiece.length + word.length + 1 <= maxLength) {
                currentPiece += " " + word
            } else {
                pieces.add(currentPiece)
                currentPiece = word
            }
        }
        if (currentPiece.isNotEmpty()) {
            pieces.add(currentPiece)
        }
        return pieces
    }
}
