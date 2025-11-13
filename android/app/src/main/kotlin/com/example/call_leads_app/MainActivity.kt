// android/app/src/main/kotlin/com/example/call_leads_app/MainActivity.kt
package com.example.call_leads_app

import androidx.annotation.NonNull
import com.example.call_leads_app.callservice.CallService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CALL_EVENTS = "com.example.call_leads_app/callEvents"

    // The event sink is now managed by CallService, but we need to set it here.
    // We remove the old internal eventSink and pendingEvents

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // EVENT CHANNEL → (Android → Flutter)
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CALL_EVENTS
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                // 🔥 Set the static event sink in CallService
                CallService.eventSink = events
                
                // 🔥 FLUSH the pending event immediately upon connection
                val pendingEvent = CallService.pendingInitialEvent
                if (pendingEvent != null) {
                    println("📞 FLUSHING PENDING EVENT: $pendingEvent")
                    events?.success(pendingEvent)
                    CallService.pendingInitialEvent = null
                }
            }

            override fun onCancel(arguments: Any?) {
                // Clear the static event sink in CallService
                CallService.eventSink = null
            }
        })
        
        // Remove the old MethodChannel logic for initial call data, as CallService now handles it via pendingInitialEvent
    }
}