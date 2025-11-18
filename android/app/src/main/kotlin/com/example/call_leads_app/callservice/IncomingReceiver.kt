// IncomingReceiver.kt
package com.example.call_leads_app.callservice

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.telephony.TelephonyManager
import android.util.Log
import androidx.core.content.ContextCompat

class IncomingReceiver : BroadcastReceiver() {

    private val TAG = "IncomingReceiver"
    private val PREFS = "call_leads_prefs"
    private val KEY_LAST_OUTGOING = "last_outgoing_number"
    private val KEY_LAST_OUTGOING_TS = "last_outgoing_ts"
    private val OUTGOING_MARKER_WINDOW_MS = 10_000L // 10 seconds

    override fun onReceive(context: Context, intent: Intent) {
        try {
            val tmState = intent.getStringExtra(TelephonyManager.EXTRA_STATE)
            var incomingNumber: String? = null
            if (intent.hasExtra(TelephonyManager.EXTRA_INCOMING_NUMBER)) {
                incomingNumber = intent.getStringExtra(TelephonyManager.EXTRA_INCOMING_NUMBER)
            }

            Log.d(TAG, "📞 Triggered by Phone State Change - state=$tmState incoming=$incomingNumber")

            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val lastOutgoing = prefs.getString(KEY_LAST_OUTGOING, null)
            val lastTs = prefs.getLong(KEY_LAST_OUTGOING_TS, 0L)
            val now = System.currentTimeMillis()
            val isRecentOutgoing = !lastOutgoing.isNullOrEmpty() && (now - lastTs) <= OUTGOING_MARKER_WINDOW_MS

            if (isRecentOutgoing && incomingNumber != null && numbersLikelyMatch(lastOutgoing, incomingNumber)) {
                Log.d(TAG, "ℹ️ Detected recent outgoing marker for $incomingNumber — treating as outbound and clearing marker.")
                prefs.edit().remove(KEY_LAST_OUTGOING).remove(KEY_LAST_OUTGOING_TS).apply()

                val outIntent = Intent(context, CallService::class.java).apply {
                    putExtra("event", "outgoing_start")
                    putExtra("direction", "outbound")
                    putExtra("phoneNumber", incomingNumber)
                }
                ContextCompat.startForegroundService(context, outIntent)
                return
            }

            when (tmState) {
                TelephonyManager.EXTRA_STATE_RINGING -> {
                    Log.d(TAG, "RINGING — will be handled by CallService")
                    if (!incomingNumber.isNullOrEmpty()) {
                        val i = Intent(context, CallService::class.java).apply {
                            putExtra("event", "ringing")
                            putExtra("direction", "inbound")
                            putExtra("phoneNumber", incomingNumber)
                        }
                        ContextCompat.startForegroundService(context, i)
                    }
                }
                TelephonyManager.EXTRA_STATE_OFFHOOK -> {
                    Log.d(TAG, "OFFHOOK — will notify CallService if number available")
                    val i = Intent(context, CallService::class.java).apply {
                        putExtra("event", "answered")
                        putExtra("direction", "inbound")
                        putExtra("phoneNumber", incomingNumber)
                    }
                    ContextCompat.startForegroundService(context, i)
                }
                TelephonyManager.EXTRA_STATE_IDLE -> {
                    Log.d(TAG, "IDLE — finalizing call")
                    val i = Intent(context, CallService::class.java).apply {
                        putExtra("event", "ended")
                        putExtra("direction", "inbound")
                        putExtra("phoneNumber", incomingNumber)
                    }
                    ContextCompat.startForegroundService(context, i)
                }
                else -> {
                    Log.d(TAG, "Unhandled telephony state: $tmState")
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error in onReceive: ${e.localizedMessage}", e)
        }
    }

    private fun normalizeNumber(n: String?): String? {
        if (n == null) return null
        val digits = n.filter { it.isDigit() }
        return if (digits.isEmpty()) null else digits
    }

    private fun numbersLikelyMatch(a: String?, b: String?): Boolean {
        val na = normalizeNumber(a) ?: return false
        val nb = normalizeNumber(b) ?: return false
        if (na == nb) return true
        val len = 7
        val sa = if (na.length > len) na.substring(na.length - len) else na
        val sb = if (nb.length > len) nb.substring(nb.length - len) else nb
        return sa == sb
    }
}
