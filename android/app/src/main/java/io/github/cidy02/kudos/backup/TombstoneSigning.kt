package io.github.cidy02.kudos.backup

import android.content.Context
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import com.google.crypto.tink.InsecureSecretKeyAccess
import com.google.crypto.tink.KeyTemplates
import com.google.crypto.tink.KeysetHandle
import com.google.crypto.tink.integration.android.AndroidKeysetManager
import com.google.crypto.tink.signature.Ed25519PrivateKey
import com.google.crypto.tink.signature.Ed25519PublicKey
import com.google.crypto.tink.signature.SignatureConfig
import com.google.crypto.tink.subtle.Ed25519Sign
import com.google.crypto.tink.subtle.Ed25519Verify
import io.github.cidy02.kudos.core.model.SyncTombstone
import io.github.cidy02.kudos.works.WorkTags
import java.security.GeneralSecurityException
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Phase 2 Ed25519 tombstone signatures (shared wire contract).
 *
 * Payload is UTF-8 fields joined by `\n` with no trailing newline:
 * recordType, ao3WorkID, canonicalSourceURL, recordID, deletedAt, signerPublicKey.
 *
 * Signatures are raw 64-byte Ed25519 (128-char lowercase hex). Tink output-prefix
 * variants are not used on the wire so iOS CryptoKit can verify the same bytes.
 */
object TombstoneSigning {
    private const val PUBLIC_KEY_HEX_LENGTH = 64
    private const val SIGNATURE_HEX_LENGTH = 128
    private const val KEYSET_PREF_FILE = "kudos_tombstone_keyset"
    private const val KEYSET_NAME = "ed25519_raw"
    private const val MASTER_KEY_URI = "android-keystore://kudos_tombstone_master"
    private const val SEED_PREF_FILE = "kudos_tombstone_seed"
    private const val SEED_PRIVATE_HEX = "ed25519_private_hex"

    private val deletedAtFormatter: DateTimeFormatter =
        DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss'Z'").withZone(ZoneOffset.UTC)

    private val tinkRegistered = AtomicBoolean(false)
    private val lock = Any()

    @Volatile
    private var privateKey: ByteArray? = null

    @Volatile
    private var publicKeyHex: String? = null

    fun initialize(context: Context) {
        synchronized(lock) {
            if (privateKey != null && publicKeyHex != null) return
            registerTink()
            val appContext = context.applicationContext
            loadFromAndroidKeysetManager(appContext)?.let { cache(it.first, it.second); return }
            loadFromEncryptedSeed(appContext)?.let { cache(it.first, it.second); return }
            val pair = Ed25519Sign.KeyPair.newKeyPair()
            cache(pair.privateKey, pair.publicKey.toLowerHex())
            persistEncryptedSeed(appContext, pair.privateKey)
        }
    }

    /** JVM / Robolectric: in-memory keypair, no Android Keystore. */
    fun initializeWithRawKeyPair(rawPrivateKey: ByteArray, rawPublicKey: ByteArray) {
        synchronized(lock) {
            cache(rawPrivateKey.copyOf(), rawPublicKey.toLowerHex())
        }
    }

    fun resetForTests() {
        synchronized(lock) {
            privateKey = null
            publicKeyHex = null
        }
    }

    fun publicKeyHex(): String {
        ensureKeys()
        return publicKeyHex!!
    }

    fun isOwnPublicKey(hex: String): Boolean {
        val normalized = normalizePublicKeyHex(hex) ?: return false
        val own = publicKeyHex
        return own != null && normalized == own
    }

    fun isTrustedSigner(publicKeyHex: String, trustedPublicKeys: Set<String>): Boolean {
        val normalized = normalizePublicKeyHex(publicKeyHex) ?: return false
        if (isOwnPublicKey(normalized)) return true
        return trustedPublicKeys.any { normalizePublicKeyHex(it) == normalized }
    }

    fun normalizePublicKeyHex(raw: String): String? {
        val hex = raw.trim().lowercase()
        if (hex.length != PUBLIC_KEY_HEX_LENGTH) return null
        if (!hex.all { it in HEX_CHARS }) return null
        return hex
    }

    fun formatDeletedAt(instant: Instant): String =
        deletedAtFormatter.format(instant.truncatedTo(ChronoUnit.SECONDS))

    fun payloadUtf8(tombstone: SyncTombstone): String {
        val ao3 = tombstone.ao3WorkID?.toString().orEmpty()
        val canonical = WorkTags.canonicalAO3WorkURL(tombstone.sourceURL).orEmpty()
        val recordId = tombstone.recordID.trim().lowercase()
        val deletedAt = formatDeletedAt(tombstone.createdAt)
        val signer = tombstone.signerPublicKey.trim().lowercase()
        return listOf(
            tombstone.recordTypeRaw,
            ao3,
            canonical,
            recordId,
            deletedAt,
            signer
        ).joinToString("\n")
    }

    fun payloadBytes(tombstone: SyncTombstone): ByteArray =
        payloadUtf8(tombstone).toByteArray(Charsets.UTF_8)

    fun sign(tombstone: SyncTombstone): SyncTombstone {
        ensureKeys()
        return signWithRawKey(tombstone, privateKey!!, publicKeyHex!!)
    }

    fun signWithRawKey(
        tombstone: SyncTombstone,
        rawPrivateKey: ByteArray,
        publicKeyHex: String
    ): SyncTombstone {
        val normalizedPub = normalizePublicKeyHex(publicKeyHex)
            ?: error("signerPublicKey must be 64-char lowercase hex")
        val withPub = tombstone.copy(signerPublicKey = normalizedPub)
        val signature = Ed25519Sign(rawPrivateKey).sign(payloadBytes(withPub)).toLowerHex()
        return withPub.copy(signature = signature)
    }

    fun verify(tombstone: SyncTombstone): Boolean {
        val pub = normalizePublicKeyHex(tombstone.signerPublicKey) ?: return false
        val sigHex = tombstone.signature.trim().lowercase()
        if (sigHex.length != SIGNATURE_HEX_LENGTH || !sigHex.all { it in HEX_CHARS }) return false
        return try {
            Ed25519Verify(hexToBytes(pub)).verify(hexToBytes(sigHex), payloadBytes(tombstone.copy(signerPublicKey = pub)))
            true
        } catch (_: GeneralSecurityException) {
            false
        } catch (_: IllegalArgumentException) {
            false
        }
    }

    private fun ensureKeys() {
        if (privateKey != null && publicKeyHex != null) return
        synchronized(lock) {
            if (privateKey != null && publicKeyHex != null) return
            val pair = Ed25519Sign.KeyPair.newKeyPair()
            cache(pair.privateKey, pair.publicKey.toLowerHex())
        }
    }

    private fun cache(rawPrivate: ByteArray, hexPublic: String) {
        privateKey = rawPrivate
        publicKeyHex = hexPublic.lowercase()
    }

    private fun registerTink() {
        if (tinkRegistered.compareAndSet(false, true)) {
            SignatureConfig.register()
        }
    }

    private fun loadFromAndroidKeysetManager(context: Context): Pair<ByteArray, String>? {
        return try {
            registerTink()
            val handle = AndroidKeysetManager.Builder()
                .withSharedPref(context, KEYSET_NAME, KEYSET_PREF_FILE)
                .withKeyTemplate(KeyTemplates.get("ED25519WithRawOutput"))
                .withMasterKeyUri(MASTER_KEY_URI)
                .build()
                .keysetHandle
            extractRawKeyPair(handle)
        } catch (_: Exception) {
            null
        }
    }

    private fun extractRawKeyPair(handle: KeysetHandle): Pair<ByteArray, String>? {
        return try {
            val private = handle.getAt(0).key as Ed25519PrivateKey
            val rawPrivate = private.privateKeyBytes.toByteArray(InsecureSecretKeyAccess.get())
            val public = handle.publicKeysetHandle.getAt(0).key as Ed25519PublicKey
            val rawPublic = public.publicKeyBytes.toByteArray()
            if (rawPrivate.size != 32 || rawPublic.size != 32) return null
            rawPrivate to rawPublic.toLowerHex()
        } catch (_: Exception) {
            null
        }
    }

    private fun loadFromEncryptedSeed(context: Context): Pair<ByteArray, String>? {
        return try {
            val prefs = encryptedSeedPrefs(context)
            val hex = prefs.getString(SEED_PRIVATE_HEX, null) ?: return null
            val rawPrivate = hexToBytes(hex)
            val pair = Ed25519Sign.KeyPair.newKeyPairFromSeed(rawPrivate)
            pair.privateKey to pair.publicKey.toLowerHex()
        } catch (_: Exception) {
            null
        }
    }

    private fun persistEncryptedSeed(context: Context, rawPrivate: ByteArray) {
        try {
            encryptedSeedPrefs(context).edit()
                .putString(SEED_PRIVATE_HEX, rawPrivate.toLowerHex())
                .apply()
        } catch (_: Exception) {
            // Robolectric / missing Android Keystore — in-memory key is enough.
        }
    }

    private fun encryptedSeedPrefs(context: Context) = EncryptedSharedPreferences.create(
        context,
        SEED_PREF_FILE,
        MasterKey.Builder(context).setKeyScheme(MasterKey.KeyScheme.AES256_GCM).build(),
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
    )

    internal fun hexToBytes(hex: String): ByteArray {
        require(hex.length % 2 == 0) { "hex length must be even" }
        return ByteArray(hex.length / 2) { i ->
            hex.substring(i * 2, i * 2 + 2).toInt(16).toByte()
        }
    }

    private val HEX_CHARS = "0123456789abcdef".toSet()
}

internal fun ByteArray.toLowerHex(): String =
    joinToString("") { byte -> "%02x".format(byte) }
