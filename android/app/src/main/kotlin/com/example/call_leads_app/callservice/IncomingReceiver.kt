package com.example.call_leads_app.callservice

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.SystemClock
import android.telephony.TelephonyManager
import android.util.Log

class IncomingReceiver : BroadcastReceiver() {

    private val TAG = "IncomingReceiver"
    private val PREFS = "call_leads_prefs"
    private val KEY_LAST_OUTGOING = "last_outgoing_number"
    private val KEY_LAST_OUTGOING_TS = "last_outgoing_ts"

    // How long (ms) after an outgoing marker we still consider calls related
    private val OUTGOING_MARKER_WINDOW_MS = 10_000L // 10 seconds

    override fun onReceive(context: Context, intent: Intent) {
        try {
            val tmState = intent.getStringExtra(TelephonyManager.EXTRA_STATE)
            var incomingNumber: String? = null
            if (intent.hasExtra(TelephonyManager.EXTRA_INCOMING_NUMBER)) {
                incomingNumber = intent.getStringExtra(TelephonyManager.EXTRA_INCOMING_NUMBER)
            }

            Log.d(TAG, "📞 Triggered by Phone State Change")
            Log.d(TAG, "📞 State=$tmState  Incoming=$incomingNumber")

            // Read outgoing marker
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val lastOutgoing = prefs.getString(KEY_LAST_OUTGOING, null)
            val lastTs = prefs.getLong(KEY_LAST_OUTGOING_TS, 0L)
            val now = System.currentTimeMillis()

            val isRecentOutgoing = !lastOutgoing.isNullOrEmpty() && (now - lastTs) <= OUTGOING_MARKER_WINDOW_MS

            if (isRecentOutgoing && incomingNumber != null && lastOutgoing == incomingNumber) {
                // This incoming broadcast corresponds to an outgoing call we started earlier.
                Log.d(TAG, "ℹ️ Detected recent outgoing marker for $incomingNumber — treating as outbound / ignoring inbound flow.")
                // Clear marker to avoid future confusion
                prefs.edit().remove(KEY_LAST_OUTGOING).remove(KEY_LAST_OUTGOING_TS).apply()

                // Optionally, start the CallService to notify about outbound (if needed)
                val outIntent = Intent(context, CallService::class.java).apply {
                    putExtra("event", "outgoing_start")
                    putExtra("direction", "outbound")
                    putExtra("phoneNumber", incomingNumber)
                }
                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                    context.startForegroundService(outIntent)
                } else {
                    context.startService(outIntent)
                }

                return // skip inbound handling
            }

            // Existing logic: only act for convenient state transitions
            when (tmState) {
                TelephonyManager.EXTRA_STATE_RINGING -> {
                    Log.d(TAG, "RINGING — will be handled by CallService")
                    // Start service for incoming ringing if we have a number
                    if (!incomingNumber.isNullOrEmpty()) {
                        val i = Intent(context, CallService::class.java).apply {
                            putExtra("event", "ringing")
                            putExtra("direction", "inbound")
                            putExtra("phoneNumber", incomingNumber)
                        }
                        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                            context.startForegroundService(i)
                        } else {
                            context.startService(i)
                        }
                    }
                }
                TelephonyManager.EXTRA_STATE_OFFHOOK -> {
                    // Offhook — call answered/connected
                    Log.d(TAG, "OFFHOOK — will notify CallService if number available")
                    val i = Intent(context, CallService::class.java).apply {
                        putExtra("event", "answered")
                        putExtra("direction", "inbound")
                        putExtra("phoneNumber", incomingNumber)
                    }
                    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                        context.startForegroundService(i)
                    } else {
                        context.startService(i)
                    }
                }
                TelephonyManager.EXTRA_STATE_IDLE -> {
                    Log.d(TAG, "IDLE — finalizing call")
                    val i = Intent(context, CallService::class.java).apply {
                        putExtra("event", "ended")
                        putExtra("direction", "inbound")
                        putExtra("phoneNumber", incomingNumber)
                    }
                    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                        context.startForegroundService(i)
                    } else {
                        context.startService(i)
                    }
                }
                else -> {
                    Log.d(TAG, "Unhandled telephony state: $tmState")
                }
            }
        } catch (e: Exception) {
            Log.e("IncomingReceiver", "Error in onReceive: ${e.localizedMessage}")
        }
    }
}
