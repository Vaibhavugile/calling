package com.example.call_leads_app.callservice

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.database.Cursor
import android.os.Build
import android.os.IBinder
import android.os.Handler
import android.os.Looper
import android.provider.CallLog
import android.telephony.PhoneStateListener
import android.telephony.TelephonyCallback
import android.telephony.TelephonyManager
import android.util.Log
import androidx.annotation.RequiresApi
import io.flutter.plugin.common.EventChannel

class CallService : Service() {

    companion object {
        var eventSink: EventChannel.EventSink? = null
        var pendingInitialEvent: Map<String, Any?>? = null
        private const val CALL_COOLDOWN_MS = 2000L
        private const val CALL_LOG_DELAY_MS = 500L // Time to wait for OS to update Call Log
    }

    private lateinit var telephonyManager: TelephonyManager

    // Tracked state for the currently active call
    private var currentCallNumber: String? = null
    private var currentCallDirection: String? = null

    private var previousCallState: Int = TelephonyManager.CALL_STATE_IDLE
    private var lastCallEndTime: Long = 0 // Tracker for call end cooldown

    // Call listener objects
    private var legacyListener: CallStateListener? = null
    private var modernCallback: TelephonyCallback? = null

    // --------------------------------------------------------------------------
    // SERVICE LIFECYCLE
    // --------------------------------------------------------------------------

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

        // Check if a call is starting via a receiver (IncomingReceiver or OutgoingReceiver)
        val event = intent?.getStringExtra("event")
        val number = intent?.getStringExtra("phoneNumber")
        val direction = intent?.getStringExtra("direction")

        if (!number.isNullOrEmpty() && !direction.isNullOrEmpty()) {
            // Update the state based on the receiver event
            currentCallNumber = number
            currentCallDirection = direction
            Log.d("CallService", "Context set by Intent: $direction to $number (Event: $event)")

            // Send initial event to Flutter immediately
            if (event != "state_change" && event != null) {
                sendCallEvent(
                    number = number,
                    direction = direction,
                    outcome = event,
                    timestamp = System.currentTimeMillis(),
                    durationInSeconds = null
                )
            }
        }

        // This ensures the service keeps running until explicitly stopped or destroyed
        return START_STICKY
    }

    // --------------------------------------------------------------------------
    // TELEPHONY CALLBACK REGISTRATION
    // --------------------------------------------------------------------------

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

    // --------------------------------------------------------------------------
    // CORE STATE HANDLER
    // --------------------------------------------------------------------------

    fun handleCallStateUpdate(state: Int, incomingNumber: String?) {
        Log.d("CallService", "📞 Listener State Change: ${stateToName(state)} (Incoming: $incomingNumber)")

        // Check for cooldown period to avoid duplicate processing of IDLE
        if (state == TelephonyManager.CALL_STATE_IDLE && System.currentTimeMillis() < lastCallEndTime + CALL_COOLDOWN_MS) {
            Log.d("CallService", "🚫 DEDUPLICATED: IDLE event ignored due to cooldown.")
            return
        }

        // 1. STATE TRANSITION: OFFHOOK (Call Connected)
        if (state == TelephonyManager.CALL_STATE_OFFHOOK) {
            if (previousCallState == TelephonyManager.CALL_STATE_RINGING) {
                // INCOMING CALL WAS ANSWERED
                sendCallEvent(
                    number = currentCallNumber ?: incomingNumber ?: "unknown",
                    direction = currentCallDirection ?: "inbound",
                    outcome = "answered",
                    timestamp = System.currentTimeMillis(),
                    durationInSeconds = null
                )
            } else if (previousCallState == TelephonyManager.CALL_STATE_IDLE) {
                // OUTBOUND CALL CONNECTED (or missed OutgoingReceiver)
                if (currentCallNumber.isNullOrEmpty()) {
                    // Failsafe: OutgoingReceiver failed. Use Call Log to get context.
                    readCallLogForLastCall()
                } else {
                    // Everything worked fine (OutgoingReceiver started us). Send 'answered' event.
                    sendCallEvent(
                        number = currentCallNumber!!,
                        direction = currentCallDirection ?: "outbound",
                        outcome = "answered",
                        timestamp = System.currentTimeMillis(),
                        durationInSeconds = null
                    )
                }
            }
        }

        // 2. STATE TRANSITION: IDLE (Call Ended)
        else if (state == TelephonyManager.CALL_STATE_IDLE) {
            if (previousCallState == TelephonyManager.CALL_STATE_OFFHOOK) {
                // CALL ENDED (Answered/Connected)
                handleCallEndedAfterOffhook()
            } else if (previousCallState == TelephonyManager.CALL_STATE_RINGING) {
                // MISSED/REJECTED CALL (Incoming)
                handleCallEndedAfterRinging(incomingNumber)
            }
            // Clear tracking data after an IDLE event
            currentCallNumber = null
            currentCallDirection = null
            lastCallEndTime = System.currentTimeMillis() // Set cooldown
        }

        // 3. STATE TRANSITION: RINGING (New Incoming Call)
        else if (state == TelephonyManager.CALL_STATE_RINGING) {
            Log.d("CallService", "RINGING event received via listener. Handled by Intent.")
        }

        previousCallState = state
    }

    // --------------------------------------------------------------------------
    // CALL ENDING HANDLERS
    // --------------------------------------------------------------------------

    private fun handleCallEndedAfterOffhook() {
        if (currentCallNumber.isNullOrEmpty()) {
            Log.e("CallService", "❌ ERROR: Call ended (OFFHOOK->IDLE) but currentCallNumber is missing.")
            return
        }

        readCallLogForLastCall(
            numberOverride = currentCallNumber,
            directionOverride = currentCallDirection,
            cooldown = true
        )
    }

    private fun handleCallEndedAfterRinging(incomingNumber: String?) {
        val finalNumber = currentCallNumber ?: incomingNumber

        if (finalNumber.isNullOrEmpty()) {
            Log.e("CallService", "❌ ERROR: Call ended (RINGING->IDLE) but no number available.")
            return
        }

        readCallLogForLastCall(
            numberOverride = finalNumber,
            directionOverride = "inbound",
            cooldown = true
        )
    }

    // --------------------------------------------------------------------------
    // FAILSAFE & LOG READING (updated - NO 'LIMIT' token)
    // --------------------------------------------------------------------------

    private fun readCallLogForLastCall(
        numberOverride: String? = null,
        directionOverride: String? = null,
        cooldown: Boolean = false
    ) {
        if (checkSelfPermission(android.Manifest.permission.READ_CALL_LOG) !=
            android.content.pm.PackageManager.PERMISSION_GRANTED
        ) {
            Log.e("CallService", "❌ READ_CALL_LOG permission not granted for failsafe.")
            return
        }

        val delay = if (cooldown) CALL_LOG_DELAY_MS else 0L

        Handler(Looper.getMainLooper()).postDelayed({
            var cursor: Cursor? = null
            try {
                // Build URI with limit=1 to avoid 'Invalid token LIMIT'
                val limitUri = CallLog.Calls.CONTENT_URI.buildUpon()
                    .appendQueryParameter("limit", "1")
                    .build()

                cursor = contentResolver.query(
                    limitUri,
                    arrayOf(
                        CallLog.Calls.NUMBER,
                        CallLog.Calls.TYPE,
                        CallLog.Calls.DATE,
                        CallLog.Calls.DURATION
                    ),
                    null,
                    null,
                    "${CallLog.Calls.DATE} DESC"
                )

                if (cursor?.moveToFirst() == true) {
                    val number = numberOverride
                        ?: cursor.getString(cursor.getColumnIndexOrThrow(CallLog.Calls.NUMBER))
                    val type = cursor.getInt(cursor.getColumnIndexOrThrow(CallLog.Calls.TYPE))
                    val duration =
                        cursor.getLong(cursor.getColumnIndexOrThrow(CallLog.Calls.DURATION)) // sec
                    val timestamp =
                        cursor.getLong(cursor.getColumnIndexOrThrow(CallLog.Calls.DATE))

                    val (outcome, direction) = getOutcomeAndDirectionFromType(type, directionOverride)

                    if (currentCallNumber.isNullOrEmpty()) {
                        currentCallNumber = number
                        currentCallDirection = direction
                    }

                    Log.w(
                        "CallService",
                        "🚨 Call Log Result: $outcome ($direction) to $number, Duration: $duration"
                    )

                    sendCallEvent(
                        number = number,
                        direction = direction,
                        outcome = outcome,
                        timestamp = timestamp,
                        durationInSeconds = duration.toInt()
                    )
                }
            } catch (e: Exception) {
                Log.e("CallService", "❌ Error reading Call Log: $e")
            } finally {
                cursor?.close()
            }
        }, delay)
    }

    private fun getOutcomeAndDirectionFromType(type: Int, directionOverride: String?): Pair<String, String> {
        val direction = directionOverride ?: when (type) {
            CallLog.Calls.OUTGOING_TYPE -> "outbound"
            CallLog.Calls.INCOMING_TYPE -> "inbound"
            CallLog.Calls.MISSED_TYPE -> "inbound"
            CallLog.Calls.REJECTED_TYPE -> "inbound"
            else -> "unknown"
        }

        val outcome = when (type) {
            CallLog.Calls.OUTGOING_TYPE, CallLog.Calls.INCOMING_TYPE ->
                if (direction == "outbound" && previousCallState == TelephonyManager.CALL_STATE_IDLE) {
                    "outgoing_start"
                } else {
                    "ended"
                }

            CallLog.Calls.MISSED_TYPE -> "missed"
            CallLog.Calls.REJECTED_TYPE -> "rejected"
            else -> "ended"
        }
        return Pair(outcome, direction)
    }

    // --------------------------------------------------------------------------
    // FLUTTER EVENT CHANNEL
    // --------------------------------------------------------------------------

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

        Handler(Looper.getMainLooper()).post {
            eventSink?.success(data)
        }
    }

    // --------------------------------------------------------------------------
    // NOTIFICATION/UTILITY
    // --------------------------------------------------------------------------

    private fun buildNotification(): Notification {
        val notificationChannelId = "call_channel"
        return Notification.Builder(this, notificationChannelId)
            .setContentTitle("Call Tracking Running")
            .setContentText("Detecting call events")
            .setSmallIcon(android.R.drawable.sym_call_incoming)
            .build()
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "call_channel",
                "Call Tracking",
                NotificationManager.IMPORTANCE_LOW
            )
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }

    override fun onBind(intent: Intent?): IBinder? {
        return null
    }

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
