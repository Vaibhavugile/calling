// MyInCallService.kt
package com.example.call_leads_app.callservice

import android.telecom.Call
import android.telecom.InCallService
import android.util.Log

class MyInCallService : InCallService() {

    private val TAG = "MyInCallService"

    private val callCallback = object : Call.Callback() {
        override fun onStateChanged(call: Call, state: Int) {
            super.onStateChanged(call, state)
            Log.d(TAG, "onStateChanged: state=$state handle=${call.details?.handle}")
            // Optionally forward relevant events to CallService or a MethodChannel
        }

        override fun onDetailsChanged(call: Call, details: Call.Details?) {
            super.onDetailsChanged(call, details)
            Log.d(TAG, "onDetailsChanged: ${call.details?.handle}")
        }
    }

    override fun onCallAdded(call: Call) {
        super.onCallAdded(call)
        Log.d(TAG, "onCallAdded: ${call.details?.handle}")
        try {
            call.registerCallback(callCallback)
        } catch (e: Exception) {
            Log.e(TAG, "Error registering call callback: ${e.localizedMessage}", e)
        }
    }

    override fun onCallRemoved(call: Call) {
        super.onCallRemoved(call)
        Log.d(TAG, "onCallRemoved: ${call.details?.handle}")
        try {
            call.unregisterCallback(callCallback)
        } catch (ignored: Exception) {
            // defensive: ignore
        }
    }
}
