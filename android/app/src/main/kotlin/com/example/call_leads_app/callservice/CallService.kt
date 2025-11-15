package com.example.call_leads_app.callservice

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.database.Cursor
import android.os.Build
import android.os.IBinder
import android.os.Handler // <-- ADD THIS IMPORT
import android.os.Looper // <-- ADD THIS IMPORT
import android.provider.CallLog 
import android.telephony.PhoneStateListener
import android.telephony.TelephonyCallback
import android.telephony.TelephonyManager
import android.util.Log
import io.flutter.plugin.common.EventChannel

class CallService : Service() {

    companion object {
        var eventSink: EventChannel.EventSink? = null
        var pendingInitialEvent: Map<String, Any?>? = null
    }

    private lateinit var telephonyManager: TelephonyManager
    
    private var currentCallNumber: String? = null
    private var currentCallDirection: String? = null
    
    private var previousCallState: Int = TelephonyManager.CALL_STATE_IDLE

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

        // 1. STORE state, but ONLY if started by IncomingReceiver (inbound)
        if (number.isNotEmpty() && direction == "inbound") {
            currentCallNumber = number
            currentCallDirection = direction
        }
        
        // This block handles the OUTBOUND case started by OutgoingReceiver.
        // It sets the trackers before the listener fires the OFFHOOK state.
        if (number.isNotEmpty() && direction == "outbound") {
             currentCallNumber = number
             currentCallDirection = direction
             // Send the 'started' event immediately, before the OFFHOOK
             sendEvent(number, direction, "started")
             // Do NOT return here, we need to register the listener below.
        }

        // 2. Send initial event (e.g., 'ringing' for incoming). Ignore 'state_change' event from receiver.
        if (event != "unknown" && direction == "inbound") {
            sendEvent(number, direction, event)
        }

        // 3. Register the call state listener (handles all state changes)
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

    private fun getOutgoingNumberFromCallLog(): String {
        var cursor: Cursor? = null
        try {
            // Sort by date descending (most recent first)
            val sortOrder = CallLog.Calls.DATE + " DESC" 
            
            cursor = contentResolver.query(
                CallLog.Calls.CONTENT_URI,
                arrayOf(CallLog.Calls.NUMBER),
                null,
                null,
                sortOrder
            )
            
            // We read the first result, which is the most recent call
            if (cursor != null && cursor.moveToFirst()) {
                val numberIndex = cursor.getColumnIndex(CallLog.Calls.NUMBER)
                if (numberIndex >= 0) {
                    return cursor.getString(numberIndex) ?: ""
                }
            }
        } catch (e: SecurityException) {
            Log.e("CallService", "❌ SecurityException: Missing READ_CALL_LOG permission or runtime permission revoked.", e)
        } catch (e: Exception) {
            Log.e("CallService", "❌ Error reading call log. Full stack trace above.", e)
        } finally {
            cursor?.close()
        }
        return ""
    }


    fun handleCallStateUpdate(state: Int, numberFromListener: String?) {
        
        var numberToUse = numberFromListener ?: currentCallNumber ?: ""
        var directionToUse = currentCallDirection ?: "unknown"
        var outcome: String
        
        // 1. 🎯 DETECT Outgoing Call Start (IDLE -> OFFHOOK)
        // We run the fallback logic if currentCallNumber is null AND it's not an inbound call.
        if (previousCallState == TelephonyManager.CALL_STATE_IDLE && 
            state == TelephonyManager.CALL_STATE_OFFHOOK && 
            currentCallDirection != "inbound") { 

            Log.d("CallService", "📞 Detected Outgoing Call Start (IDLE -> OFFHOOK)")

            // Case A: OutgoingReceiver successfully passed the number. Send 'answered'.
            if (currentCallNumber.isNullOrEmpty() == false) {
                 // The 'started' event was already sent in onStartCommand.
                 // We send 'answered' now.
                 sendEvent(currentCallNumber!!, "outbound", "answered")
                 previousCallState = state 
                 return
            }

            // Case B: OutgoingReceiver failed or was blocked. Fallback to Call Log with delay.
            Log.d("CallService", "⚠️ Outgoing number unknown. Falling back to Call Log with 500ms delay.")

            // 🔥 CRITICAL FIX: Run the delaying logic on a new thread.
            Thread {
                try {
                    Thread.sleep(500) // 500ms delay to wait for OS to update CallLog.
                    val outgoingNumber = getOutgoingNumberFromCallLog()
                    
                    if (outgoingNumber.isNotEmpty()) {
                        Log.d("CallService", "✅ CallLog Fallback SUCCESS: $outgoingNumber")

                        currentCallNumber = outgoingNumber
                        currentCallDirection = "outbound"

                        // 🔥 CRITICAL FIX: Post the event sending back to the main thread!
                        Handler(Looper.getMainLooper()).post {
                            // Send both 'started' and 'answered' events from the background thread
                            sendEvent(outgoingNumber, "outbound", "started")
                            sendEvent(outgoingNumber, "outbound", "answered")
                        }
                    } else {
                        Log.e("CallService", "❌ CallLog Fallback FAILED: Could not retrieve outgoing number.")
                    }
                } catch (e: InterruptedException) {
                    Thread.currentThread().interrupt()
                    Log.e("CallService", "Delay interrupted", e)
                }
            }.start()
            
            // Update the state tracker and immediately return.
            previousCallState = state
            return
        }

        // 2. Process all other states (RINGING, OFFHOOK (inbound/follow-up), IDLE)
        when (state) {
            TelephonyManager.CALL_STATE_RINGING -> {
                 outcome = "ringing"
                 // Store number only if it came from the listener (old Android) AND we don't have a number yet.
                 if (currentCallNumber.isNullOrEmpty() && numberFromListener.isNullOrEmpty() == false) {
                     currentCallNumber = numberFromListener
                     currentCallDirection = "inbound"
                     numberToUse = numberFromListener!!
                     directionToUse = "inbound"
                 }
            }
            TelephonyManager.CALL_STATE_OFFHOOK -> outcome = "answered"
            TelephonyManager.CALL_STATE_IDLE -> outcome = "ended"
            else -> {
                previousCallState = state 
                return 
            }
        }
        
        // Use the stored direction if current state logic didn't determine it
        directionToUse = currentCallDirection ?: "unknown"


        // 3. Cleanup on call end
        if (state == TelephonyManager.CALL_STATE_IDLE) {
            Log.d("CallService", "🧹 Cleaning up call state")
            // Use the stored number for the final 'ended' event
            numberToUse = currentCallNumber ?: numberToUse 
            
            // Clear the tracked number/direction after the call ends
            currentCallNumber = null
            currentCallDirection = null
        }
        
        // 4. Send the event
        if (numberToUse.isNotEmpty()) {
            sendEvent(numberToUse, directionToUse, outcome)
        }
        
        // 5. 🎯 CRITICAL: Update the state tracker for the next cycle
        previousCallState = state
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
}