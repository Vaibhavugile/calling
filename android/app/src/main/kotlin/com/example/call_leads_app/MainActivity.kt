package com.example.call_leads_app

import android.app.Activity
import android.app.role.RoleManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.util.Log
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CALL_EVENTS = "com.example.call_leads_app/callEvents"
    private val NATIVE_CHANNEL = "com.example.call_leads_app/native"
    private val TAG = "MainActivity"
    private val REQUEST_ROLE_DIALER = 32123 // arbitrary request code

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // EVENT CHANNEL → (Android → Flutter)
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CALL_EVENTS
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                try {
                    // wire the static sink that CallService writes into
                    com.example.call_leads_app.callservice.CallService.eventSink = events

                    // If CallService buffered an initial event earlier, flush it once
                    val pendingEvent = com.example.call_leads_app.callservice.CallService.pendingInitialEvent
                    if (pendingEvent != null) {
                        Log.d(TAG, "FLUSHING PENDING EVENT: $pendingEvent")
                        try {
                            events?.success(pendingEvent)
                        } catch (e: Exception) {
                            Log.e(TAG, "Error flushing pending event to Flutter: ${e.localizedMessage}")
                        } finally {
                            com.example.call_leads_app.callservice.CallService.pendingInitialEvent = null
                        }
                    }

                    // NOTE: If you later add an instance-level flush method on CallService,
                    // you can also call it here (via a broadcast or service binding) to be extra sure.
                } catch (e: Exception) {
                    Log.e(TAG, "onListen error: ${e.localizedMessage}", e)
                }
            }

            override fun onCancel(arguments: Any?) {
                try {
                    com.example.call_leads_app.callservice.CallService.eventSink = null
                } catch (e: Exception) {
                    Log.e(TAG, "onCancel error: ${e.localizedMessage}", e)
                }
            }
        })

        // METHOD CHANNEL → (Flutter → Android)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            NATIVE_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestDialerRole" -> {
                    val ok = requestDialerRole()
                    // respond safely
                    try {
                        result.success(ok)
                    } catch (e: Exception) {
                        Log.e(TAG, "Error sending method channel result: ${e.localizedMessage}")
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    /**
     * Request the user to set this app as the default dialer (ROLE_DIALER).
     * Uses startActivityForResult to avoid activity-ktx dependency.
     */
    private fun requestDialerRole(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            Log.w(TAG, "ROLE_DIALER via RoleManager requires API 29+. Skipping.")
            return false
        }

        val roleManager = getSystemService(Context.ROLE_SERVICE) as? RoleManager
        if (roleManager == null) {
            Log.w(TAG, "RoleManager not available")
            return false
        }

        return try {
            if (!roleManager.isRoleHeld(RoleManager.ROLE_DIALER)) {
                val intent = roleManager.createRequestRoleIntent(RoleManager.ROLE_DIALER)
                // startActivityForResult is still acceptable here
                startActivityForResult(intent, REQUEST_ROLE_DIALER)
                true
            } else {
                Log.d(TAG, "Already holds ROLE_DIALER")
                true
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to launch role request intent: ${e.localizedMessage}", e)
            false
        }
    }

    // handle the result from startActivityForResult
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_ROLE_DIALER) {
            if (resultCode == Activity.RESULT_OK) {
                Log.d(TAG, "User granted ROLE_DIALER")
            } else {
                Log.d(TAG, "User did NOT grant ROLE_DIALER")
            }
        }
    }
}
