package com.voltraware.gateway_commissioning

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.IntentFilter
import android.net.wifi.WifiManager
import android.os.Handler
import android.os.Looper
import android.os.Build
import android.location.LocationManager

class MainActivity : FlutterActivity() {
    private var scanReceiver: BroadcastReceiver? = null
    private var scanReply: MethodChannel.Result? = null
    private val scanHandler = Handler(Looper.getMainLooper())
    private fun finishScan(error: String? = null) {
        val reply = scanReply ?: return
        scanReply = null
        scanHandler.removeCallbacksAndMessages(null)
        scanReceiver?.let { try { unregisterReceiver(it) } catch (_: IllegalArgumentException) {} }
        scanReceiver = null
        if (error != null) { reply.error(error, error, null); return }
        try {
            val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            reply.success(wifi.scanResults.map { mapOf("ssid" to it.SSID, "rssi" to it.level, "frequency" to it.frequency) })
        } catch (_: SecurityException) { reply.error("permission", "permission", null) }
    }
    private fun scanWifi(result: MethodChannel.Result) {
        if (scanReply != null) { result.error("busy", "busy", null); return }
        val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        if (!wifi.isWifiEnabled) { result.error("wifi_off", "wifi_off", null); return }
        val location = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        if (!location.isProviderEnabled(LocationManager.GPS_PROVIDER) && !location.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
            result.error("location_off", "location_off", null); return
        }
        scanReply = result
        scanReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                if (intent.action == WifiManager.SCAN_RESULTS_AVAILABLE_ACTION) {
                    finishScan(if (intent.getBooleanExtra(WifiManager.EXTRA_RESULTS_UPDATED, false)) null else "throttled")
                }
            }
        }
        try {
            val filter = IntentFilter(WifiManager.SCAN_RESULTS_AVAILABLE_ACTION)
            if (Build.VERSION.SDK_INT >= 33) registerReceiver(scanReceiver, filter, Context.RECEIVER_EXPORTED)
            else registerReceiver(scanReceiver, filter)
            scanHandler.postDelayed({ finishScan("timeout") }, 15000)
            if (!wifi.startScan()) finishScan("throttled")
        } catch (_: SecurityException) { finishScan("permission") }
    }
    override fun onDestroy() {
        finishScan("cancelled")
        super.onDestroy()
    }
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "voltraware/wifi")
            .setMethodCallHandler { call, result ->
                if (call.method == "scan") scanWifi(result) else result.notImplemented()
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "voltraware/report")
            .setMethodCallHandler { call, result ->
                if (call.method != "share") {
                    result.notImplemented()
                } else {
                    val text = call.argument<String>("text")
                    if (text.isNullOrBlank()) {
                        result.error("empty", "Report is empty", null)
                    } else {
                        val intent = Intent(Intent.ACTION_SEND).apply {
                            type = "text/plain"
                            putExtra(Intent.EXTRA_TEXT, text)
                        }
                        startActivity(Intent.createChooser(intent, null))
                        result.success(null)
                    }
                }
            }
    }
}
