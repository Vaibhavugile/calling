// OutgoingReceiver.kt
package com.example.call_leads_app.callservice

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.content.ContextCompat

class OutgoingReceiver : BroadcastReceiver() {
    private val TAG = "OutgoingReceiver"

    override fun onReceive(context: Context?, intent: Intent?) {
        Log.d(TAG, "📞 ACTION_NEW_OUTGOING_CALL received")

        if (context == null || intent == null) {
            Log.e(TAG, "Context or Intent null")
            return
        }

        val number = intent.getStringExtra(Intent.EXTRA_PHONE_NUMBER)

        if (number.isNullOrEmpty()) {
            Log.w(TAG, "Outgoing Number empty/null. Ignoring.")
            return
        }

        Log.d(TAG, "📞 Outgoing Number: $number")

        val serviceIntent = Intent(context, CallService::class.java).apply {
            putExtra("direction", "outbound")
            putExtra("phoneNumber", number)
            putExtra("event", "outgoing_start")
        }

        ContextCompat.startForegroundService(context, serviceIntent)
    }
}
