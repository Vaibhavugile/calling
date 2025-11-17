// IncomingReceiver.kt

package com.example.call_leads_app.callservice

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.telephony.TelephonyManager
import android.util.Log

class IncomingReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context?, intent: Intent?) {
        Log.d("IncomingReceiver", "📞 Triggered by Phone State Change")

        if (context == null || intent == null) {
            Log.e("IncomingReceiver", "❌ Context or Intent null")
            return
        }

        val state = intent.getStringExtra(TelephonyManager.EXTRA_STATE)
        val number = intent.getStringExtra(TelephonyManager.EXTRA_INCOMING_NUMBER)

        Log.d("IncomingReceiver", "📞 State=$state  Incoming=$number")
        
        // ======================================================================
        // ✅ FIX: Handle both RINGING and OFFHOOK (answered) as call start events.
        // This is crucial for devices that skip the RINGING broadcast and go
        // straight to OFFHOOK, but provide the number.
        // ======================================================================
        val isRingingOrOffHookStart = 
            (state == TelephonyManager.EXTRA_STATE_RINGING) || 
            (state == TelephonyManager.EXTRA_STATE_OFFHOOK)
        
        if (isRingingOrOffHookStart && !number.isNullOrEmpty()) {
            
            // Send 'ringing' if it's RINGING, otherwise send 'answered' 
            // as a fallback when the OS skips the RINGING broadcast.
            val event = if (state == TelephonyManager.EXTRA_STATE_RINGING) "ringing" else "answered"

            Log.d("IncomingReceiver", "✅ Starting Service for Incoming: $number (Event: $event)")
            
            val serviceIntent = Intent(context, CallService::class.java).apply {
                putExtra("direction", "inbound")
                putExtra("phoneNumber", number)
                putExtra("event", event)
            }
            context.startForegroundService(serviceIntent)
        } else {
            // Ignore IDLE or state changes without a number. 
            // The running CallService listener will handle the rest.
            Log.d("IncomingReceiver", "⚠️ Ignoring non-starting broadcast (State: $state, Number: $number).")
        }
    }
}