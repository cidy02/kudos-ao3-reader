package io.github.cidy02.kudos.reader.speech

object TextChunker {
    fun chunk(text: String, maxLength: Int = 250): List<String> {
        val chunks = mutableListOf<String>()
        val paragraphs = text.split("\n", "\r\n")

        for (paragraph in paragraphs) {
            val paragraphText = paragraph.trim()
            if (paragraphText.isEmpty()) continue

            if (paragraphText.length <= maxLength) {
                chunks.add(paragraphText)
            } else {
                val sentences = splitIntoSentences(paragraphText, maxLength)
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
        // Regex: split on . ! ? followed by space, keeping punctuation attached
        // (?<=[.!?])\s+ -> matches whitespace preceded by .!?
        val regex = Regex("(?<=[.!?])\\s+")
        val rawSentences = text.split(regex)
        
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

    private fun splitByClauses(text: String, maxLength: Int): List<String> {
        val delimiters = setOf(';', ':', '—', ',', '”', '"')
        val pieces = mutableListOf<String>()
        var currentPiece = StringBuilder()

        for (i in text.indices) {
            val char = text[i]
            currentPiece.append(char)

            if (delimiters.contains(char)) {
                if (currentPiece.length >= (maxLength / 2) || char == '”' || char == '"') {
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
