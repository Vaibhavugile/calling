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

        val serviceIntent = Intent(context, CallService::class.java)
        
        // Only set direction/event if it's explicitly an incoming ringing call
        if (state == TelephonyManager.EXTRA_STATE_RINGING) {
            Log.d("IncomingReceiver", "📞 Starting Service for Incoming RINGING")
            serviceIntent.putExtra("direction", "inbound")
            serviceIntent.putExtra("phoneNumber", number ?: "")
            serviceIntent.putExtra("event", "ringing")
        } 
        
        // ✅ FIX: Skip starting the service if it's IDLE and no specific number is provided.
        // The running CallService should already handle the end of the call via its listener.
        else if (state == TelephonyManager.EXTRA_STATE_IDLE && number.isNullOrEmpty()) {
            Log.d("IncomingReceiver", "⚠️ Ignoring IDLE broadcast with null number.")
            return
        }
        
        else {
            // For all other states (OFFHOOK, IDLE with a number), send generic info
            serviceIntent.putExtra("direction", "unknown")
            serviceIntent.putExtra("phoneNumber", number ?: "")
            serviceIntent.putExtra("event", "state_change") // Signals CallService to use its internal listener
        }
        
        // Start the CallService to handle the call lifecycle in the foreground
        context.startForegroundService(serviceIntent)
    }
}