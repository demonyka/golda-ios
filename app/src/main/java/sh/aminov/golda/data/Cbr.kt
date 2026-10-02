package sh.aminov.golda.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URI

/** Official daily rates of the Bank of Russia, mirrored as JSON. */
object Cbr {
    private const val URL = "https://www.cbr-xml-daily.ru/daily_json.js"

    /** Used until the first successful download (CBR, 2026-10-02). */
    val fallback = listOf(
        Rate("RUB", 1.0, "2026-10-02"),
        Rate("USD", 83.2454, "2026-10-02"),
        Rate("GEL", 31.9597, "2026-10-02"),
        Rate("THB", 2.47438, "2026-10-02"),
    )

    suspend fun fetch(): List<Rate> = withContext(Dispatchers.IO) {
        val connection = URI(URL).toURL().openConnection() as HttpURLConnection
        connection.connectTimeout = 10_000
        connection.readTimeout = 10_000
        try {
            val json = JSONObject(connection.inputStream.bufferedReader().use { it.readText() })
            val date = json.getString("Date").take(10)
            val valute = json.getJSONObject("Valute")
            valute.keys().asSequence().map { code ->
                val item = valute.getJSONObject(code)
                Rate(code, item.getDouble("Value") / item.getInt("Nominal"), date)
            }.toList() + Rate("RUB", 1.0, date)
        } finally {
            connection.disconnect()
        }
    }
}
