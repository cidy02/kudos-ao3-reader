package io.github.cidy02.kudos.files

import java.nio.file.Path

sealed interface FileWriteResult {
    data class Success(val path: Path) : FileWriteResult
    data class Failure(val message: String, val cause: Throwable? = null) : FileWriteResult
}
