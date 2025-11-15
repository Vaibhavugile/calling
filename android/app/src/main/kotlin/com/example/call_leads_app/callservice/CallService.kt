package com.example.call_leads_app.callservice

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
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

    // Data class to hold the rich data pulled from Android Call Log
    private data class CallLogEntry(
        val number: String,
        val direction: String, // "inbound" or "outbound"
        val outcome: String,   // "answered", "missed", "rejected", "ended"
        val durationInSeconds: Int
    )

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
    // Note: rawState is often passed by IncomingReceiver for better logic
    val rawState = intent?.getIntExtra("rawState", -1) ?: -1 

    Log.d("CallService", "📞 Initial event=$event  number=$number  dir=$direction")

    // 1. Cooldown Check (Only applies to IDLE broadcasts)
    // Ignore rapid restarts/IDLE broadcasts right after a call ended
    if (event == "state_change" && rawState == TelephonyManager.CALL_STATE_IDLE && System.currentTimeMillis() - lastCallEndTime < CALL_COOLDOWN_MS) {
        Log.d("CallService", "⚠️ Ignoring rapid IDLE broadcast after call end (cooldown).")
        startForeground(1, buildNotification())
        return START_NOT_STICKY
    }
    
    // 2. Handle Outbound (OutgoingReceiver - START)
    if (number.isNotEmpty() && direction == "outbound") {
          currentCallNumber = number
          currentCallDirection = direction
          // Send the 'started' event immediately, before the OFFHOOK
          sendEvent(number, direction, "started")
    }

    // 3. Handle Inbound (IncomingReceiver - RINGING)
    else if (number.isNotEmpty() && direction == "inbound") {
        currentCallNumber = number
        currentCallDirection = direction
        // Send initial event (e.g., 'ringing' for incoming).
        if (event != "unknown") {
            sendEvent(number, direction, event)
        }
    }
    
    // 4. Fallback: IncomingReceiver/Listener provides a number during OFFHOOK
    // We trust this number if we don't have one yet.
    else if (rawState == TelephonyManager.CALL_STATE_OFFHOOK && number.isNotEmpty() && currentCallNumber.isNullOrEmpty()) {
        Log.d("CallService", "✅ Fallback to OFFHOOK number: $number. Assuming Outbound.")
        currentCallNumber = number
        currentCallDirection = "outbound" // Assume outbound if not marked as inbound/ringing
    }

    // 5. Register the call state listener (handles all state changes)
    // This handles subsequent state changes (RINGING -> OFFHOOK -> IDLE)
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        // Use TelephonyCallback for API 31+
        telephonyManager.registerTelephonyCallback(
            mainExecutor,
            CallStateCallback(this)
        )
    } else {
        // Use PhoneStateListener for API < 31
        @Suppress("DEPRECATION")
        telephonyManager.listen(
            CallStateListener(this),
            PhoneStateListener.LISTEN_CALL_STATE
        )
    }

    startForeground(1, buildNotification())
    return START_NOT_STICKY
}

    /**
     * Reads the Call Log to find the most recent call record.
     * Maps the system fields to app-specific fields (direction, outcome, duration).
     */
    private fun getLatestCallLogEntry(): CallLogEntry? {
        var cursor: Cursor? = null
        try {
            val projection = arrayOf(
                CallLog.Calls.NUMBER,
                CallLog.Calls.TYPE,
                CallLog.Calls.DURATION,
                CallLog.Calls.DATE
            )
            // Sort by date descending (most recent first)
            val sortOrder = CallLog.Calls.DATE + " DESC"  
            
            cursor = contentResolver.query(
                CallLog.Calls.CONTENT_URI,
                projection,
                null,
                null,
                sortOrder
            )
            
            if (cursor != null && cursor.moveToFirst()) {
                val numberIndex = cursor.getColumnIndex(CallLog.Calls.NUMBER)
                val typeIndex = cursor.getColumnIndex(CallLog.Calls.TYPE)
                val durationIndex = cursor.getColumnIndex(CallLog.Calls.DURATION)
                
                if (numberIndex < 0 || typeIndex < 0 || durationIndex < 0) {
                    Log.e("CallService", "❌ Error getting CallLog column index.")
                    return null
                }

                val number = cursor.getString(numberIndex) ?: "UNKNOWN_NUMBER"
                val type = cursor.getInt(typeIndex)
                val duration = cursor.getInt(durationIndex)
                
                // Map system type to app-specific direction and outcome
                val (direction, outcome) = when (type) {
                    CallLog.Calls.OUTGOING_TYPE -> 
                        // Outgoing: duration > 0 is answered, duration == 0 is typically ended (cancelled/no answer)
                        if (duration > 0) Pair("outbound", "answered") else Pair("outbound", "ended")
                    CallLog.Calls.INCOMING_TYPE -> 
                        // Incoming: duration > 0 is answered, duration == 0 is typically a missed call *before* rejection or system logging
                        if (duration > 0) Pair("inbound", "answered") else Pair("inbound", "missed")
                    CallLog.Calls.MISSED_TYPE -> 
                        Pair("inbound", "missed")
                    CallLog.Calls.REJECTED_TYPE -> 
                        Pair("inbound", "rejected")
                    // Default to 'ended' for other types or unknown cases where duration might indicate connection
                    else -> {
                        if (duration > 0) Pair("unknown", "answered") else Pair("unknown", "ended")
                    }
                }

                Log.d("CallService", "✅ CallLog Result: Num=$number, Dir=$direction, Outcome=$outcome, Dur=$duration")
                return CallLogEntry(number, direction, outcome, duration)
            }
        } catch (e: SecurityException) {
            Log.e("CallService", "❌ SecurityException: Missing READ_CALL_LOG permission or runtime permission revoked.", e)
        } catch (e: Exception) {
            Log.e("CallService", "❌ Error reading call log.", e)
        } finally {
            cursor?.close()
        }
        return null
    }


    fun handleCallStateUpdate(state: Int, numberFromListener: String?) {
        
        var numberToUse = numberFromListener ?: currentCallNumber
        var directionToUse = currentCallDirection ?: "unknown"

        Log.d("CallService", "🔄 State Update: $previousCallState -> $state. Listener Number: $numberFromListener. Internal Number: $currentCallNumber")
        
        // 1. 🎯 DETECT Outgoing Call Start (IDLE -> OFFHOOK)
        // This handles outgoing calls where OutgoingReceiver *might* have failed.
        if (previousCallState == TelephonyManager.CALL_STATE_IDLE && 
            state == TelephonyManager.CALL_STATE_OFFHOOK && 
            currentCallDirection != "inbound") { 

            Log.d("CallService", "📞 Detected Outgoing Call Start (IDLE -> OFFHOOK)")

            // Case A: Number is already known (from OutgoingReceiver or onStartCommand fallback)
            if (currentCallNumber.isNullOrEmpty() == false) {
                 // The 'started' event was already sent in onStartCommand. Send 'answered' now.
                 sendEvent(currentCallNumber!!, "outbound", "answered")
            } else {
                 // Case B: OutgoingReceiver failed. Fallback to Call Log with delay.
                 Log.d("CallService", "⚠️ Outgoing number unknown. Falling back to Call Log with ${CALL_LOG_DELAY_MS}ms delay.")

                 // Postpone the Call Log lookup to try and catch the number.
                 Handler(Looper.getMainLooper()).postDelayed({
                      // Re-check if a faster broadcast set the number during the delay
                      if (currentCallNumber.isNullOrEmpty() == false) {
                          Log.d("CallService", "⚠️ Call Log fallback cancelled: number (${currentCallNumber}) was set by a faster broadcast.")
                          sendEvent(currentCallNumber!!, "outbound", "answered") // Re-send answered event just in case
                          return@postDelayed
                      }
                      
                      // If still null, try to get the number from Call Log
                      val outgoingEntry = getLatestCallLogEntry()
                      
                      // If the latest entry is an outgoing call with duration 0, it's the one we just started
                      if (outgoingEntry != null && outgoingEntry.direction == "outbound") { 
                          Log.d("CallService", "✅ CallLog Fallback SUCCESS: ${outgoingEntry.number}")
                          currentCallNumber = outgoingEntry.number
                          currentCallDirection = "outbound"

                          // Send both 'started' and 'answered' events to ensure Flutter UI is up to date
                          sendEvent(outgoingEntry.number, "outbound", "started")
                          sendEvent(outgoingEntry.number, "outbound", "answered")  
                      } else {
                          Log.e("CallService", "❌ CallLog Fallback FAILED for OFFHOOK: Could not retrieve outgoing number.")
                      }
                  }, CALL_LOG_DELAY_MS)
            }
            
            previousCallState = state
            return
        }

        // 2. Process all other states (RINGING, OFFHOOK (inbound/follow-up), IDLE)
        var outcome: String? = null
        
        when (state) {
            TelephonyManager.CALL_STATE_RINGING -> {
                outcome = "ringing"
                // Store number only if it came from the listener/broadcast AND we don't have a number yet.
                if (currentCallNumber.isNullOrEmpty() && numberFromListener.isNullOrEmpty() == false) {
                    currentCallNumber = numberFromListener
                    currentCallDirection = "inbound"
                    numberToUse = numberFromListener
                    directionToUse = "inbound"
                }
            }
            TelephonyManager.CALL_STATE_OFFHOOK -> {
                // RINGING -> OFFHOOK (Answered Incoming) or initial OFFHOOK (Answered Outgoing)
                if (currentCallDirection == "inbound" || previousCallState == TelephonyManager.CALL_STATE_RINGING) {
                    outcome = "answered"
                } else if (currentCallDirection == "outbound") {
                    // Outbound call is in progress. No new event needed unless we missed the first 'answered'.
                    outcome = "answered" 
                }
            }
            
            TelephonyManager.CALL_STATE_IDLE -> {
                // IDLE is the end state. We handle the final rich event using Call Log.
                Log.d("CallService", "📞 Detected IDLE state. Triggering rich call log lookup.")
                
                // 3. 🎯 CRITICAL: Handle IDLE via Call Log in a background thread
                previousCallState = state // Update state immediately
                
                // We use a separate thread for the potentially blocking Call Log query
                Thread {
                    try {
                        Thread.sleep(CALL_LOG_DELAY_MS) // Wait for the Call Log to be updated by the OS
                        
                        // Capture the number/direction *before* clearing state
                        val trackedNumber = currentCallNumber
                        val trackedDirection = currentCallDirection
                        
                        // Clear the internal state trackers immediately to allow a new call to start
                        currentCallNumber = null
                        currentCallDirection = null
                        lastCallEndTime = System.currentTimeMillis() // Record end time for cooldown
                        
                        // 4. Get final call data from Call Log
                        val finalLogEntry = getLatestCallLogEntry()
                        
                        // 5. Send the final rich event back on the main thread
                        Handler(Looper.getMainLooper()).post {
                            if (finalLogEntry != null) {
                                // Prefer the Call Log data as it is the final, authoritative record
                                Log.d("CallService", "✅ Call Log lookup successful. Sending rich final event.")
                                sendEvent(
                                    finalLogEntry.number, 
                                    finalLogEntry.direction, 
                                    finalLogEntry.outcome, 
                                    finalLogEntry.durationInSeconds
                                )
                            } else if (trackedNumber.isNullOrEmpty() == false) {
                                // Fallback: Send a basic 'ended' event if we tracked a number but the Call Log failed
                                Log.e("CallService", "❌ Call Log failed. Sending basic 'ended' event for $trackedNumber.")
                                // The outcome is 'ended' as a generic final state when no CallLog data is available.
                                sendEvent(trackedNumber, trackedDirection ?: "unknown", "ended") 
                            } else {
                                Log.w("CallService", "⚠️ IDLE event fired but no tracked number or Call Log data found. Skipping event.")
                            }
                        }
                    } catch (e: InterruptedException) {
                        Thread.currentThread().interrupt()
                        Log.e("CallService", "Delay interrupted during IDLE processing.", e)
                    }
                }.start()
                
                return // CRITICAL: Stop here, the final event is handled by the background thread.
            }
            
            else -> {
                previousCallState = state  
                return // Ignore other states or unknown transitions
            }
        }

        // 6. Send intermediate event (RINGING, OFFHOOK(answered))
        if (numberToUse.isNullOrEmpty() == false && outcome.isNullOrEmpty() == false) {
              sendEvent(numberToUse!!, directionToUse, outcome!!)
        }
        
        // 7. Update the state tracker for the next cycle
        previousCallState = state
    }


    /**
     * Sends an event to Flutter via the EventChannel.
     * @param durationInSeconds Optional duration, only used for final 'ended', 'missed', 'rejected' events.
     */
    private fun sendEvent(number: String, direction: String, outcome: String, durationInSeconds: Int? = null) {
        val data = mutableMapOf<String, Any?>(
            "phoneNumber" to number,
            "direction" to direction,
            "outcome" to outcome,
            "timestamp" to System.currentTimeMillis()
        )
        if (durationInSeconds != null) {
            data["durationInSeconds"] = durationInSeconds
        }

        Log.d("CallService", "📤 Sending event to Flutter: $data")

        if (eventSink == null) {
            Log.w("CallService", "⚠️ Flutter not connected yet → storing pending")
            pendingInitialEvent = data
            return
        }

        // Must run on the main thread for EventChannel
        Handler(Looper.getMainLooper()).post {
            eventSink?.success(data)
        }
    }

    private fun buildNotification(): Notification {
        val notificationChannelId = "call_channel"
        // Ensure you have a small icon resource if you change the placeholder
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
        super.onDestroy()
        Log.d("CallService", "Service destroyed")
    }
}