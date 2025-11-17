// android/app/src/main/kotlin/com/example/call_leads_app/callservice/OutgoingReceiver.kt

package com.example.call_leads_app.callservice

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Captures the outgoing number immediately before the call connects.
 */
class OutgoingReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {
        Log.d("OutgoingReceiver", "📞 Triggered by ACTION_NEW_OUTGOING_CALL")

        if (context == null || intent == null) {
            Log.e("OutgoingReceiver", "❌ Context or Intent null")
            return
        }

        // The outgoing number is available in this Intent's extra
        val number = intent.getStringExtra(Intent.EXTRA_PHONE_NUMBER)
        
        if (number.isNullOrEmpty()) {
            Log.w("OutgoingReceiver", "⚠️ Outgoing Number is empty/null. Ignoring.")
            return
        }
        
        Log.d("OutgoingReceiver", "📞 Outgoing Number: $number")

        val serviceIntent = Intent(context, CallService::class.java).apply {
            // Send a custom event to CallService to indicate call start with a number
            putExtra("direction", "outbound")
            putExtra("phoneNumber", number)
            putExtra("event", "outgoing_start") // New event type
        }
        
        // Start the CallService to handle the rest of the call lifecycle
        context.startForegroundService(serviceIntent)
    }
}