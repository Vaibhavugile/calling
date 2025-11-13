package com.example.call_leads_app.callservice

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.telephony.TelephonyManager
import android.util.Log

class IncomingReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context?, intent: Intent?) {
        Log.d("IncomingReceiver", "📞 Triggered")

        if (context == null || intent == null) {
            Log.e("IncomingReceiver", "❌ Context or Intent null")
            return
        }

        val state = intent.getStringExtra(TelephonyManager.EXTRA_STATE)
        var number = intent.getStringExtra(TelephonyManager.EXTRA_INCOMING_NUMBER)

        Log.d("IncomingReceiver", "📞 State=$state  Incoming=$number")

        // 🔥 REMOVED: The logic below was removed because CallService.pendingInitialNumber 
        // no longer exists and the CallService now handles state persistence better.
        // if (number.isNullOrEmpty()) {
        //     number = CallService.pendingInitialNumber
        // }

        if (state == TelephonyManager.EXTRA_STATE_RINGING) {
            Log.d("IncomingReceiver", "📞 Incoming call RINGING: $number")

            val serviceIntent = Intent(context, CallService::class.java)
            serviceIntent.putExtra("direction", "inbound")
            serviceIntent.putExtra("phoneNumber", number ?: "")
            serviceIntent.putExtra("event", "ringing")

            // Start the CallService to handle the call lifecycle in the foreground
            context.startForegroundService(serviceIntent)
        }
    }
}