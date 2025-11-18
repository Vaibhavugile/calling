package com.example.call_leads_app.callservice

import android.content.Intent
import android.content.Context
import android.net.Uri
import android.os.Build
import android.telecom.CallRedirectionService
import android.telecom.PhoneAccountHandle
import android.util.Log

class MyCallRedirectionService : CallRedirectionService() {

    private val TAG = "MyCallRedirectionService"
    private val PREFS = "call_leads_prefs"
    private val KEY_LAST_OUTGOING = "last_outgoing_number"
    private val KEY_LAST_OUTGOING_TS = "last_outgoing_ts"

    // Ensure this matches the actual package + class of CallService
    private val CALL_SERVICE_CLASS_NAME = "com.example.call_leads_app.callservice.CallService"

    override fun onPlaceCall(handle: Uri, phoneAccount: PhoneAccountHandle, allowInteractiveResponse: Boolean) {
        try {
            val phoneNumber = handle.schemeSpecificPart
            Log.d(TAG, "onPlaceCall: $phoneNumber")

            // 1) Save outgoing marker to SharedPreferences (guaranteed)
            val prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            prefs.edit()
                .putString(KEY_LAST_OUTGOING, phoneNumber)
                .putLong(KEY_LAST_OUTGOING_TS, System.currentTimeMillis())
                .apply()
            Log.d(TAG, "Saved outgoing marker for $phoneNumber (prefs keys: $KEY_LAST_OUTGOING / $KEY_LAST_OUTGOING_TS)")

            // 2) Start CallService with explicit extras so native code can immediately forward
            val intent = Intent().apply {
                setClassName(packageName, CALL_SERVICE_CLASS_NAME)
                putExtra("event", "outgoing_start")
                putExtra("direction", "outbound")
                putExtra("phoneNumber", phoneNumber)
            }

            Log.d(TAG, "Starting CallService for outgoing_start → class=$CALL_SERVICE_CLASS_NAME")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }

            // 3) Let Telecom place the call unchanged
            placeCallUnmodified()
        } catch (e: Exception) {
            Log.e(TAG, "Error in onPlaceCall: ${e.localizedMessage}", e)
            cancelCall()
        }
    }
}
