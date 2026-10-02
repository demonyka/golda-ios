package sh.aminov.golda.data

import android.content.Context
import android.media.MediaRecorder
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import sh.aminov.golda.domain.VoiceItem
import sh.aminov.golda.domain.VoicePrompt
import sh.aminov.golda.domain.VoiceResult
import java.io.File
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URI
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import sh.aminov.golda.domain.tr

/** Records one voice note to an Opus file. */
class VoiceRecorder(private val context: Context) {
    private var recorder: MediaRecorder? = null
    private var file: File? = null
    private var startedAt = 0L
    private var peak = 0f
    private var samples = 0

    fun start(): File {
        val target = File(VoiceQueue.dir(context), "${System.currentTimeMillis()}.ogg")
        recorder = MediaRecorder(context).apply {
            setAudioSource(MediaRecorder.AudioSource.VOICE_RECOGNITION)
            setOutputFormat(MediaRecorder.OutputFormat.OGG)
            setAudioEncoder(MediaRecorder.AudioEncoder.OPUS)
            setAudioChannels(1)
            setAudioSamplingRate(16_000)
            setAudioEncodingBitRate(24_000)
            setMaxDuration(60_000)
            setOutputFile(target)
            prepare()
            start()
        }
        file = target
        startedAt = System.currentTimeMillis()
        peak = 0f
        samples = 0
        return target
    }

    /**
     * The finished file, or null when nothing usable was recorded: an empty file, a tap shorter
     * than 0.8 s, or silence (judged only when the level was actually being watched).
     */
    fun stop(): File? {
        val r = recorder ?: return null
        val accidental = System.currentTimeMillis() - startedAt < 800 || (samples >= 3 && peak < 0.03f)
        recorder = null
        runCatching { r.stop() } // throws when nothing was recorded or the 60 s limit already stopped it
        r.release()
        val f = file ?: return null
        if (accidental || f.length() == 0L) {
            f.delete()
            return null
        }
        return f
    }

    fun cancel() {
        stop()?.delete()
    }

    /** How loud it has been since the last call, 0..1; 0 when not recording. Also keeps the loudest moment. */
    fun level(): Float {
        val now = runCatching { (recorder?.maxAmplitude ?: 0) / 32767f }.getOrDefault(0f)
        samples++
        peak = maxOf(peak, now)
        return now
    }
}

/** Voice notes waiting to be understood; the file name is the time they were recorded. */
object VoiceQueue {
    fun dir(context: Context) = File(context.filesDir, "voice").apply { mkdirs() }

    fun pending(context: Context): List<File> =
        dir(context).listFiles { f -> f.extension == "ogg" || f.extension == "wav" }.orEmpty().sortedBy { it.name }

    fun recordedAt(file: File): Long = file.nameWithoutExtension.toLongOrNull() ?: file.lastModified()
}

class GeminiException(message: String, val offline: Boolean) : Exception(message)

object Gemini {
    const val DEFAULT_MODEL = "gemini-3.5-flash-lite"

    suspend fun parse(audio: File, system: String, key: String, model: String): VoiceResult = withContext(Dispatchers.IO) {
        val mime = if (audio.extension == "wav") "audio/wav" else "audio/ogg"
        val body = JSONObject()
            .put("systemInstruction", JSONObject().put("parts", JSONArray().put(JSONObject().put("text", system))))
            .put(
                "contents",
                JSONArray().put(
                    JSONObject().put(
                        "parts",
                        JSONArray().put(
                            JSONObject().put(
                                "inlineData",
                                JSONObject().put("mimeType", mime).put("data", Base64.encodeToString(audio.readBytes(), Base64.NO_WRAP)),
                            ),
                        ),
                    ),
                ),
            )
            .put(
                "generationConfig",
                JSONObject()
                    .put("responseMimeType", "application/json")
                    .put("responseSchema", JSONObject(VoicePrompt.schema)),
            )

        val url = URI("https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent").toURL()
        val connection = url.openConnection() as HttpURLConnection
        try {
            connection.requestMethod = "POST"
            connection.connectTimeout = 15_000
            connection.readTimeout = 45_000
            connection.doOutput = true
            connection.setRequestProperty("Content-Type", "application/json")
            connection.setRequestProperty("x-goog-api-key", key)
            connection.outputStream.use { it.write(body.toString().toByteArray()) }
            val code = connection.responseCode
            if (code !in 200..299) {
                val error = connection.errorStream?.bufferedReader()?.use { it.readText() }.orEmpty()
                val message = runCatching { JSONObject(error).getJSONObject("error").getString("message") }.getOrDefault("HTTP $code")
                throw GeminiException(message, offline = code >= 500)
            }
            val text = JSONObject(connection.inputStream.bufferedReader().use { it.readText() })
                .getJSONArray("candidates").getJSONObject(0)
                .getJSONObject("content").getJSONArray("parts").getJSONObject(0).getString("text")
            read(JSONObject(text))
        } catch (e: IOException) {
            throw GeminiException(e.message ?: tr("нет сети", "no network"), offline = true)
        } finally {
            connection.disconnect()
        }
    }

    private fun read(json: JSONObject): VoiceResult {
        fun JSONObject.str(name: String) = if (isNull(name) || !has(name)) null else getString(name).takeIf { it.isNotBlank() }
        val items = json.optJSONArray("items") ?: JSONArray()
        return VoiceResult(
            transcript = json.optString("transcript"),
            items = (0 until items.length()).map { i ->
                val o = items.getJSONObject(i)
                VoiceItem(
                    intent = o.optString("intent", "unknown"),
                    amount = o.str("amount"),
                    currency = o.str("currency"),
                    note = o.optString("note"),
                    category = o.str("category"),
                    accountId = o.str("account_id"),
                    toAccountId = o.str("to_account_id"),
                    toAmount = o.str("to_amount"),
                    date = o.str("date"),
                )
            },
        )
    }
}

/** Encrypts small secrets with a key that never leaves the phone's keystore. */
object KeyVault {
    private const val ALIAS = "golda-secrets"

    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getEntry(ALIAS, null) as? KeyStore.SecretKeyEntry)?.let { return it.secretKey }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(
                KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .build(),
            )
        }.generateKey()
    }

    fun encrypt(plain: String): String {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE, key()) }
        return Base64.encodeToString(cipher.iv + cipher.doFinal(plain.toByteArray()), Base64.NO_WRAP)
    }

    /** Null when the data was encrypted on another phone (restored from a backup) or is damaged. */
    fun decrypt(sealed: String): String? = runCatching {
        val bytes = Base64.decode(sealed, Base64.NO_WRAP)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply {
            init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, bytes, 0, 12))
        }
        String(cipher.doFinal(bytes, 12, bytes.size - 12))
    }.getOrNull()
}
