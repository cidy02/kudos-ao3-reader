package io.github.cidy02.kudos.network.ao3

sealed interface AO3Result<out T> {
    data class Success<T>(val value: T) : AO3Result<T>
    data class Failure(val error: AO3Error) : AO3Result<Nothing>
}
