package com.example.call_leads_app.callservice

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.telephony.PhoneStateListener
import android.telephony.TelephonyCallback
import android.telephony.TelephonyManager
import android.util.Log
import io.flutter.plugin.common.EventChannel

class CallService : Service() {

    companion object {
        var eventSink: EventChannel.EventSink? = null
        // Stores the full event map if Flutter is not connected (Fix from previous step)
        var pendingInitialEvent: Map<String, Any?>? = null
    }

    private lateinit var telephonyManager: TelephonyManager
    
    // 🔥 NEW: Track the current active call number/direction
    private var currentCallNumber: String? = null
    private var currentCallDirection: String? = null

    override fun onCreate() {
        super.onCreate()
        Log.d("CallService", "🚀 Service created")

        telephonyManager = getSystemService(TELEPHONY_SERVICE) as TelephonyManager
        createChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d("CallService", "🚀 onStartCommand: $intent")

        val number = intent?.getStringExtra("phoneNumber") ?: ""
        val direction = intent?.getStringExtra("direction") ?: "unknown"
        val event = intent?.getStringExtra("event") ?: "unknown"

        Log.d("CallService", "📞 Initial event=$event  number=$number  dir=$direction")

        // 🔥 STORE active call number and direction from the initial intent
        if (number.isNotEmpty()) {
            currentCallNumber = number
        }
        currentCallDirection = direction

        // Initial event for outgoing/ringing state (e.g., from OutgoingReceiver)
        sendEvent(number, direction, event)

        // Existing call state listener setup
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            telephonyManager.registerTelephonyCallback(
                mainExecutor,
                CallStateCallback(this)
            )
        } else {
            @Suppress("DEPRECATION")
            telephonyManager.listen(
                CallStateListener(this),
                PhoneStateListener.LISTEN_CALL_STATE
            )
        }

        startForeground(1, buildNotification())
        return START_NOT_STICKY
    }

    // 🔥 NEW: Method called by CallStateListener and CallStateCallback to handle state changes
    fun handleCallStateUpdate(state: Int, numberFromListener: String?) {
        var outcome: String
        
        when (state) {
            TelephonyManager.CALL_STATE_RINGING -> outcome = "ringing"
            TelephonyManager.CALL_STATE_OFFHOOK -> outcome = "answered"
            TelephonyManager.CALL_STATE_IDLE -> outcome = "ended"
            else -> return // Ignore other states
        }

        // Use the number from the listener if available, otherwise use the stored number.
        // For IDLE (call end), `numberFromListener` is often null/empty, so we rely on currentCallNumber.
        val numberToUse = if (numberFromListener.isNullOrEmpty()) {
            currentCallNumber ?: ""
        } else {
            numberFromListener
        }
        
        val directionToUse = currentCallDirection ?: "unknown"
        
        // Crucial: Clear the tracked number/direction after the call ends (IDLE state)
        if (state == TelephonyManager.CALL_STATE_IDLE) {
            currentCallNumber = null
            currentCallDirection = null
        }
        
        if (numberToUse.isNotEmpty()) {
            sendEvent(numberToUse, directionToUse, outcome)
        }
    }


    private fun sendEvent(number: String, direction: String, outcome: String) {
        val data = mapOf(
            "phoneNumber" to number,
            "direction" to direction,
            "outcome" to outcome,
            "timestamp" to System.currentTimeMillis()
        )

        Log.d("CallService", "📤 Sending event to Flutter: $data")

        if (eventSink == null) {
            Log.w("CallService", "⚠️ Flutter not connected yet → storing pending")
            pendingInitialEvent = data
            return
        }

        eventSink?.success(data)
    }

    private fun buildNotification(): Notification {
        return Notification.Builder(this, "call_channel")
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
}