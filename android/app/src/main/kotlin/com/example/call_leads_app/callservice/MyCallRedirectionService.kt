package com.example.call_leads_app.callservice

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.telecom.CallRedirectionService
import android.telecom.PhoneAccountHandle
import android.util.Log

class MyCallRedirectionService : CallRedirectionService() {

    private val TAG = "MyCallRedirectionService"

    // NOTE: Replace this with your actual full service class name if different
    private val CALL_SERVICE_CLASS_NAME = "com.example.call_leads_app.CallService"

    // Match the signature the platform expects exactly (phoneAccount is non-null here)
    override fun onPlaceCall(handle: Uri, phoneAccount: PhoneAccountHandle, allowInteractiveResponse: Boolean) {
        try {
            val phoneNumber = handle.schemeSpecificPart
            Log.d(TAG, "onPlaceCall: $phoneNumber")

            // Create an intent and set the class by name (avoids compile-time reference).
            val intent = Intent()
            intent.setClassName(this.packageName, CALL_SERVICE_CLASS_NAME)
            intent.putExtra("event", "outgoing_start")
            intent.putExtra("direction", "outbound")
            intent.putExtra("phoneNumber", phoneNumber)

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(intent)
            else startService(intent)

            // Allow Telecom to proceed without modification
            placeCallUnmodified()
        } catch (e: Exception) {
            Log.e(TAG, "Error in onPlaceCall: ${e.localizedMessage}")
            // Fail-safe: cancel the call if something is seriously wrong
            cancelCall()
        }
    }
}
    