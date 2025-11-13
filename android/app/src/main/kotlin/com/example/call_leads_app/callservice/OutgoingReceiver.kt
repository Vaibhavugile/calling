package com.example.call_leads_app.callservice

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class OutgoingReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context?, intent: Intent?) {
        Log.d("OutgoingReceiver", "📞 Outgoing call detected")

        if (context == null || intent == null) return

        var number = intent.getStringExtra(Intent.EXTRA_PHONE_NUMBER)
        Log.d("OutgoingReceiver", "📞 Raw number: $number")

        // 🔥 Android 12+ sometimes blocks EXTRA_PHONE_NUMBER
        if (number.isNullOrEmpty()) {
            number = intent.data?.schemeSpecificPart
            Log.d("OutgoingReceiver", "📞 Fallback number: $number")
        }

        val serviceIntent = Intent(context, CallService::class.java)
        serviceIntent.putExtra("direction", "outbound")
        serviceIntent.putExtra("phoneNumber", number ?: "")
        serviceIntent.putExtra("event", "started")

        context.startForegroundService(serviceIntent)
    }
}
