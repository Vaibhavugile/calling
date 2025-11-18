package com.example.call_leads_app.callservice

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.database.Cursor
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.CallLog
import android.telephony.PhoneStateListener
import android.telephony.TelephonyCallback
import android.telephony.TelephonyManager
import android.util.Log
import io.flutter.plugin.common.EventChannel
import kotlin.math.abs

class CallService : Service() {

    companion object {
        var eventSink: EventChannel.EventSink? = null
        var pendingInitialEvent: Map<String, Any?>? = null

        private const val CALL_COOLDOWN_MS = 2000L
        private const val CALL_LOG_DELAY_MS = 800L
        private const val CALL_LOG_RETRY_DELAY_MS = 900L
        private const val CALL_LOG_RETRY_MAX = 6
        private const val OUTGOING_MARKER_WINDOW_MS = 12_000L

        private const val PREFS = "call_leads_prefs"
        private const val KEY_LAST_OUTGOING = "last_outgoing_number"
        private const val KEY_LAST_OUTGOING_TS = "last_outgoing_ts"

        private const val FINAL_LOCK_TTL_MS = 15_000L
    }

    private lateinit var telephonyManager: TelephonyManager
    private val mainHandler = Handler(Looper.getMainLooper())

    private var currentCallNumber: String? = null
    private var currentCallDirection: String? = null
    private var previousCallState: Int = TelephonyManager.CALL_STATE_IDLE
    private var lastCallEndTime: Long = 0

    private var legacyListener: CallStateListener? = null
    private var modernCallback: TelephonyCallback? = null

    override fun onCreate() {
        super.onCreate()
        createChannel()
        startForeground(1, buildNotification())
        telephonyManager = getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
        registerTelephonyCallback()
        Log.d("CallService", "✅ Service created and listening.")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d("CallService", "➡️ Service onStartCommand received.")

        val event = intent?.getStringExtra("event")
        val number = intent?.getStringExtra("phoneNumber")
        val direction = intent?.getStringExtra("direction")

        Log.d("CallService", "onStartCommand extras: event=$event direction=$direction phoneNumber=$number")

        if (event == "ended") {
            Log.d("CallService", "Received 'ended' intent — deferring final result to call log (numberOverride=$number).")
            readCallLogForLastCall(numberOverride = number, directionOverride = null, cooldown = true, retryCount = 0)
            return START_STICKY
        }

        if (!number.isNullOrEmpty() && !direction.isNullOrEmpty()) {
            if (currentCallDirection == null || currentCallDirection == "unknown") {
                currentCallDirection = direction
            } else {
                if (currentCallDirection == "outbound") {
                    Log.d("CallService", "Keeping existing direction=outbound (do not overwrite from Intent).")
                } else {
                    currentCallDirection = direction
                }
            }

            currentCallNumber = number
            Log.d("CallService", "Context set by Intent: $currentCallDirection to $currentCallNumber (Event: $event)")

            if (event == "outgoing_start") {
                val payload = mapOf<String, Any?>(
                    "phoneNumber" to number,
                    "direction" to "outbound",
                    "outcome" to "outgoing_start",
                    "timestamp" to System.currentTimeMillis(),
                    "durationInSeconds" to null
                )
                Log.d("CallService", "DEBUG: Immediate forward outbound -> $payload")
                if (eventSink != null) {
                    mainHandler.post { eventSink?.success(payload) }
                } else {
                    Log.w("CallService", "⚠️ Flutter not connected yet → storing pending (outgoing)")
                    pendingInitialEvent = payload
                }
            } else if (event != null && event != "state_change") {
                sendCallEvent(number, currentCallDirection ?: direction, event, System.currentTimeMillis(), null)
            }
        }

        return START_STICKY
    }

    private fun registerTelephonyCallback() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            modernCallback = CallStateCallback(this)
            telephonyManager.registerTelephonyCallback(mainExecutor, modernCallback as CallStateCallback)
            Log.d("CallService", "✅ Registered TelephonyCallback (API S+)")
        } else {
            @Suppress("DEPRECATION")
            legacyListener = CallStateListener(this)
            @Suppress("DEPRECATION")
            telephonyManager.listen(legacyListener, PhoneStateListener.LISTEN_CALL_STATE)
            Log.d("CallService", "✅ Registered PhoneStateListener (API < S)")
        }
    }

    private fun unregisterTelephonyCallback() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            modernCallback?.let {
                telephonyManager.unregisterTelephonyCallback(it)
                modernCallback = null
                Log.d("CallService", "✅ Unregistered TelephonyCallback")
            }
        } else {
            @Suppress("DEPRECATION")
            legacyListener?.let {
                telephonyManager.listen(it, PhoneStateListener.LISTEN_NONE)
                legacyListener = null
                Log.d("CallService", "✅ Unregistered PhoneStateListener")
            }
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

    fun handleCallStateUpdate(state: Int, incomingNumber: String?) {
        Log.d("CallService", "📞 Listener State Change: ${stateToName(state)} (Incoming: $incomingNumber)")

        if (state == TelephonyManager.CALL_STATE_IDLE && System.currentTimeMillis() < lastCallEndTime + CALL_COOLDOWN_MS) {
            Log.d("CallService", "🚫 DEDUPLICATED: IDLE event ignored due to cooldown.")
            return
        }

        try {
            if (state == TelephonyManager.CALL_STATE_OFFHOOK && previousCallState == TelephonyManager.CALL_STATE_IDLE && currentCallNumber.isNullOrEmpty()) {
                val prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                val lastOutgoing = prefs.getString(KEY_LAST_OUTGOING, null)
                val lastTs = prefs.getLong(KEY_LAST_OUTGOING_TS, 0L)
                val now = System.currentTimeMillis()
                if (!lastOutgoing.isNullOrEmpty() && now - lastTs <= OUTGOING_MARKER_WINDOW_MS) {
                    if (numbersLikelyMatch(lastOutgoing, incomingNumber) || incomingNumber == null) {
                        currentCallNumber = lastOutgoing
                        currentCallDirection = "outbound"
                        Log.d("CallService", "EARLY: Detected outgoing marker → treating call as OUTBOUND for $currentCallNumber")
                        prefs.edit().remove(KEY_LAST_OUTGOING).remove(KEY_LAST_OUTGOING_TS).apply()

                        sendCallEvent(currentCallNumber ?: "unknown", "outbound", "answered", System.currentTimeMillis(), null)
                        previousCallState = state
                        return
                    }
                }
            }
        } catch (e: Exception) {
            Log.e("CallService", "Error reading outgoing marker early: ${e.localizedMessage}")
        }

        if (state == TelephonyManager.CALL_STATE_OFFHOOK) {
            if (previousCallState == TelephonyManager.CALL_STATE_RINGING) {
                val dir = if (currentCallDirection == "outbound") "outbound" else "inbound"
                sendCallEvent(currentCallNumber ?: incomingNumber ?: "unknown", currentCallDirection ?: dir, "answered", System.currentTimeMillis(), null)
            } else if (previousCallState == TelephonyManager.CALL_STATE_IDLE) {
                if (currentCallNumber.isNullOrEmpty()) {
                    readCallLogForLastCall()
                } else {
                    sendCallEvent(currentCallNumber!!, currentCallDirection ?: "outbound", "answered", System.currentTimeMillis(), null)
                }
            }
        } else if (state == TelephonyManager.CALL_STATE_IDLE) {
            if (previousCallState == TelephonyManager.CALL_STATE_OFFHOOK) {
                handleCallEndedAfterOffhook()
            } else if (previousCallState == TelephonyManager.CALL_STATE_RINGING) {
                handleCallEndedAfterRinging(incomingNumber)
            }
            currentCallNumber = null
            currentCallDirection = null
            lastCallEndTime = System.currentTimeMillis()
        } else if (state == TelephonyManager.CALL_STATE_RINGING) {
            Log.d("CallService", "RINGING event received via listener.")
            if (currentCallDirection == null) currentCallDirection = "inbound"
            if (currentCallNumber == null && !incomingNumber.isNullOrEmpty()) currentCallNumber = incomingNumber
        }

        previousCallState = state
    }

    private fun handleCallEndedAfterOffhook() {
        if (currentCallNumber.isNullOrEmpty()) {
            Log.e("CallService", "❌ ERROR: Call ended (OFFHOOK->IDLE) but currentCallNumber is missing.")
            return
        }

        readCallLogForLastCall(numberOverride = currentCallNumber, directionOverride = currentCallDirection, cooldown = true, retryCount = 0)
    }

    private fun handleCallEndedAfterRinging(incomingNumber: String?) {
        val finalNumber = currentCallNumber ?: incomingNumber
        if (finalNumber.isNullOrEmpty()) {
            Log.e("CallService", "❌ ERROR: Call ended (RINGING->IDLE) but no number available.")
            return
        }
        readCallLogForLastCall(numberOverride = finalNumber, directionOverride = "inbound", cooldown = true, retryCount = 0)
    }

    private fun readCallLogForLastCall(
        numberOverride: String? = null,
        directionOverride: String? = null,
        cooldown: Boolean = false,
        retryCount: Int = 0
    ) {
        if (checkSelfPermission(android.Manifest.permission.READ_CALL_LOG) != android.content.pm.PackageManager.PERMISSION_GRANTED) {
            Log.e("CallService", "❌ READ_CALL_LOG permission not granted for failsafe.")
            val outgoing = getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY_LAST_OUTGOING, null)
            val fallbackNumber = numberOverride ?: outgoing
            if (!fallbackNumber.isNullOrEmpty()) {
                val ts = getSharedPreferences(PREFS, Context.MODE_PRIVATE).getLong(KEY_LAST_OUTGOING_TS, System.currentTimeMillis())
                emitFinalCallEventIfNotLocked(fallbackNumber, "ended", ts, null, directionOverride)
            } else {
                Log.w("CallService", "No fallback due to missing number and missing permission.")
            }
            return
        }

        val delay = if (cooldown) CALL_LOG_DELAY_MS else 0L
        mainHandler.postDelayed({
            var cursor: Cursor? = null
            try {
                val recentWindowMs = System.currentTimeMillis() - 5 * 60 * 1000L
                val selection = "${CallLog.Calls.DATE}>=?"
                val selectionArgs = arrayOf(recentWindowMs.toString())
                val limitUri = CallLog.Calls.CONTENT_URI.buildUpon().appendQueryParameter("limit", "20").build()

                cursor = contentResolver.query(
                    limitUri,
                    arrayOf(CallLog.Calls._ID, CallLog.Calls.NUMBER, CallLog.Calls.TYPE, CallLog.Calls.DATE, CallLog.Calls.DURATION),
                    selection,
                    selectionArgs,
                    "${CallLog.Calls.DATE} DESC"
                )

                if (cursor == null || cursor.count == 0) {
                    Log.w("CallService", "Call log query returned empty or null.")
                    if (retryCount < CALL_LOG_RETRY_MAX - 1) {
                        Log.d("CallService", "Retrying call-log read after short delay. retry=${retryCount + 1}")
                        mainHandler.postDelayed({
                            readCallLogForLastCall(numberOverride, directionOverride, cooldown, retryCount + 1)
                        }, CALL_LOG_RETRY_DELAY_MS)
                    } else {
                        Log.w("CallService", "Max retries reached and no usable rows. Attempting fallback if possible.")
                        val prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                        val outgoing = prefs.getString(KEY_LAST_OUTGOING, null)
                        val fallbackNumber = numberOverride ?: outgoing
                        if (!fallbackNumber.isNullOrEmpty()) {
                            val ts = prefs.getLong(KEY_LAST_OUTGOING_TS, System.currentTimeMillis())
                            emitFinalCallEventIfNotLocked(fallbackNumber, "ended", ts, null, directionOverride)
                        } else {
                            Log.w("CallService", "No number available to emit final; skipping fallback.")
                        }
                    }
                    return@postDelayed
                }

                val prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                val lastOutgoing = prefs.getString(KEY_LAST_OUTGOING, null)
                val lastOutgoingTs = prefs.getLong(KEY_LAST_OUTGOING_TS, 0L)
                val outgoingMarker: Pair<String, Long>? = if (!lastOutgoing.isNullOrEmpty() && lastOutgoingTs > 0L) Pair(lastOutgoing, lastOutgoingTs) else null

                val best = pickBestCallLogRow(cursor, outgoingMarker)
                if (best != null) {
                    val num = numberOverride ?: best.number ?: outgoingMarker?.first ?: ""
                    val ts = best.timestamp
                    val dur = if (best.duration >= 0) best.duration else null
                    val outcomeAndDir = getOutcomeAndDirectionFromType(best.type, directionOverride)
                    val outcome = outcomeAndDir.first
                    var direction = outcomeAndDir.second

                    if (outgoingMarker != null && numbersLikelyMatch(outgoingMarker.first, num) && abs(outgoingMarker.second - ts) <= OUTGOING_MARKER_WINDOW_MS) {
                        direction = "outbound"
                    }

                    Log.w("CallService", "🚨 Call Log Result (picked): $outcome ($direction) to $num, Duration: $dur ts:$ts")
                    emitFinalCallEventIfNotLocked(num, outcome, ts, dur, direction)
                } else {
                    Log.w("CallService", "No suitable call-log row found after retries.")
                    val outgoing = prefs.getString(KEY_LAST_OUTGOING, null)
                    val fallbackNumber = numberOverride ?: outgoing
                    if (!fallbackNumber.isNullOrEmpty()) {
                        val ts = prefs.getLong(KEY_LAST_OUTGOING_TS, System.currentTimeMillis())
                        emitFinalCallEventIfNotLocked(fallbackNumber, "ended", ts, null, directionOverride)
                    } else {
                        Log.w("CallService", "No number available to emit final; skipping fallback.")
                    }
                }
            } catch (e: Exception) {
                Log.e("CallService", "❌ Error reading Call Log: $e")
                val prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                val outgoing = prefs.getString(KEY_LAST_OUTGOING, null)
                val fallbackNumber = numberOverride ?: outgoing
                if (!fallbackNumber.isNullOrEmpty()) {
                    val ts = prefs.getLong(KEY_LAST_OUTGOING_TS, System.currentTimeMillis())
                    emitFinalCallEventIfNotLocked(fallbackNumber, "ended", ts, null, directionOverride)
                } else {
                    Log.w("CallService", "No number available to emit final after error; skipping fallback.")
                }
            } finally {
                cursor?.close()
            }
        }, delay)
    }

    private data class _RowPick(val number: String?, val type: Int, val timestamp: Long, val duration: Int)

    private fun pickBestCallLogRow(cursor: Cursor, outgoingMarker: Pair<String, Long>?): _RowPick? {
        val rows = mutableListOf<_RowPick>()
        if (!cursor.moveToFirst()) return null
        do {
            try {
                val number = cursor.getString(cursor.getColumnIndexOrThrow(CallLog.Calls.NUMBER))
                val type = cursor.getInt(cursor.getColumnIndexOrThrow(CallLog.Calls.TYPE))
                val ts = cursor.getLong(cursor.getColumnIndexOrThrow(CallLog.Calls.DATE))
                val dur = cursor.getInt(cursor.getColumnIndexOrThrow(CallLog.Calls.DURATION))
                rows.add(_RowPick(number, type, ts, dur))
            } catch (e: Exception) {
            }
        } while (cursor.moveToNext())

        if (rows.isEmpty()) return null

        outgoingMarker?.let { (markerNumber, markerTs) ->
            val toleranceMs = OUTGOING_MARKER_WINDOW_MS
            val matches = rows.filter { it.number != null && numbersLikelyMatch(it.number, markerNumber) && abs(it.timestamp - markerTs) <= toleranceMs }
            if (matches.isNotEmpty()) {
                return matches.maxByOrNull { it.duration }
            }
        }

        val withDur = rows.filter { it.duration > 0 }
        if (withDur.isNotEmpty()) {
            return withDur.maxByOrNull { it.duration }
        }
        return rows.maxByOrNull { it.timestamp }
    }

    // NEW: infer outcome/direction from CallLog type (fallback if directionOverride provided)
    private fun getOutcomeAndDirectionFromType(callType: Int, directionOverride: String? = null): Pair<String, String> {
        // CallLog.Calls.TYPE values:
        // 1 = INCOMING_TYPE, 2 = OUTGOING_TYPE, 3 = MISSED_TYPE, 4 = VOICEMAIL_TYPE, 5 = REJECTED_TYPE, 6 = BLOCKED_TYPE, 7 = ANSWERED_EXTERNALLY
        return when (callType) {
            CallLog.Calls.INCOMING_TYPE -> Pair("ended", "inbound")
            CallLog.Calls.OUTGOING_TYPE -> Pair("outgoing_start", "outbound")
            CallLog.Calls.MISSED_TYPE -> Pair("missed", "inbound")
            CallLog.Calls.VOICEMAIL_TYPE -> Pair("voicemail", "inbound")
            // Some vendors map REJECTED to type 5 or use MISSED; treat as rejected/inbound
            5 -> Pair("rejected", "inbound")
            CallLog.Calls.ANSWERED_EXTERNALLY_TYPE -> Pair("answered_external", "inbound")
            else -> {
                // fallback: use directionOverride or default inbound-ended
                if (!directionOverride.isNullOrEmpty()) {
                    val out = if (directionOverride == "outbound") "outgoing_start" else "ended"
                    Pair(out, directionOverride)
                } else {
                    Pair("ended", "inbound")
                }
            }
        }
    }

    private fun emitFinalCallEventIfNotLocked(phoneNumber: String, finalOutcome: String, timestampMs: Long, durationSec: Int?, directionOverride: String? = null) {
        val normalized = normalizeNumber(phoneNumber) ?: ""
        if (normalized.isEmpty()) {
            Log.w("CallService", "emitFinalCallEventIfNotLocked: normalized phone empty → skipping.")
            return
        }
        val prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val lockKey = "final_lock_$normalized"
        val lockedUntil = prefs.getLong(lockKey, 0L)
        val now = System.currentTimeMillis()
        if (now < lockedUntil) {
            Log.d("CallService", "Finalization for $normalized currently locked until $lockedUntil — skipping.")
            return
        }
        prefs.edit().putLong(lockKey, now + FINAL_LOCK_TTL_MS).apply()
        emitFinalCallEvent(phoneNumber, finalOutcome, timestampMs, durationSec, directionOverride)
    }

    private fun emitFinalCallEvent(phoneNumber: String, finalOutcome: String, timestampMs: Long, durationSec: Int?, directionOverride: String? = null) {
        val prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val normalized = normalizeNumber(phoneNumber) ?: ""

        if (normalized.isEmpty()) {
            Log.w("CallService", "emitFinalCallEvent: empty phoneNumber — skipping emit.")
            return
        }

        val outgoingMarker = readOutgoingMarker()
        val isOutbound = if (directionOverride != null) {
            directionOverride == "outbound"
        } else {
            outgoingMarker?.first?.let { numbersLikelyMatch(it, phoneNumber) } ?: false
        }

        val lastFinalKey = "last_final_ts_$normalized"
        val lastFinalTs = prefs.getLong(lastFinalKey, 0L)
        val lastDurKey = "last_final_dur_$normalized"
        val lastDur = prefs.getInt(lastDurKey, -1)

        if (lastFinalTs != 0L && abs(lastFinalTs - timestampMs) < 2000L) {
            if (durationSec == null || durationSec == lastDur) {
                Log.d("CallService", "Skipping duplicate final event for $normalized (ts close and dur unchanged)")
                return
            }
        }

        val payload = mapOf(
            "phoneNumber" to phoneNumber,
            "direction" to if (isOutbound) "outbound" else "inbound",
            "outcome" to finalOutcome,
            "timestamp" to timestampMs,
            "durationInSeconds" to durationSec
        )

        Log.d("CallService", "📤 Emitting final event to Flutter: $payload")
        if (eventSink == null) {
            Log.w("CallService", "⚠️ Flutter not connected yet → storing pending final")
            pendingInitialEvent = payload
        } else {
            mainHandler.post { eventSink?.success(payload) }
        }

        prefs.edit().putLong(lastFinalKey, timestampMs).putInt(lastDurKey, durationSec ?: -1).apply()
    }

    private fun readOutgoingMarker(): Pair<String, Long>? {
        val prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val num = prefs.getString(KEY_LAST_OUTGOING, null)
        val ts = prefs.getLong(KEY_LAST_OUTGOING_TS, 0L)
        if (num == null || ts == 0L) return null
        return Pair(num, ts)
    }

    fun sendCallEvent(number: String, direction: String, outcome: String, timestamp: Long, durationInSeconds: Int?) {
        val data = mapOf(
            "phoneNumber" to number,
            "direction" to direction,
            "outcome" to outcome,
            "timestamp" to timestamp,
            "durationInSeconds" to durationInSeconds,
        )
        Log.d("CallService", "📤 Sending event to Flutter: $data")
        if (eventSink == null) {
            Log.w("CallService", "⚠️ Flutter not connected yet → storing pending")
            pendingInitialEvent = data
            return
        }
        mainHandler.post { eventSink?.success(data) }
    }

    private fun buildNotification(): Notification {
        val notificationChannelId = "call_channel"
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, notificationChannelId)
                .setContentTitle("Call Tracking Running")
                .setContentText("Detecting call events")
                .setSmallIcon(android.R.drawable.sym_call_incoming)
                .build()
        } else {
            Notification.Builder(this)
                .setContentTitle("Call Tracking Running")
                .setContentText("Detecting call events")
                .setSmallIcon(android.R.drawable.sym_call_incoming)
                .build()
        }
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel("call_channel", "Call Tracking", NotificationManager.IMPORTANCE_LOW)
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        unregisterTelephonyCallback()
        super.onDestroy()
        Log.d("CallService", "🛑 Service destroyed")
    }

    private fun stateToName(state: Int): String {
        return when (state) {
            TelephonyManager.CALL_STATE_IDLE -> "IDLE"
            TelephonyManager.CALL_STATE_RINGING -> "RINGING"
            TelephonyManager.CALL_STATE_OFFHOOK -> "OFFHOOK"
            else -> "UNKNOWN ($state)"
        }
    }
}
