package com.voltraware.gateway_commissioning

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
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
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities

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
    // Round 24: the default network for the field rescue outbox
    // (lib/data/network_watch.dart): "available", "validated" (once per
    // network), "lost".
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private fun stopNetworkWatch() {
        val callback = networkCallback ?: return
        networkCallback = null
        try {
            (getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager)
                .unregisterNetworkCallback(callback)
        } catch (_: Exception) {}
    }
    private fun startNetworkWatch(events: EventChannel.EventSink) {
        stopNetworkWatch()
        val main = Handler(Looper.getMainLooper())
        val callback = object : ConnectivityManager.NetworkCallback() {
            private var validated: Network? = null
            override fun onAvailable(network: Network) {
                main.post { events.success("available") }
            }
            override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) {
                if (!caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)) return
                if (network == validated) return
                validated = network
                main.post { events.success("validated") }
            }
            override fun onLost(network: Network) {
                if (network == validated) validated = null
                main.post { events.success("lost") }
            }
        }
        try {
            (getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager)
                .registerDefaultNetworkCallback(callback)
            networkCallback = callback
        } catch (e: Exception) {
            events.error("unavailable", e.message, null)
        }
    }
    override fun onDestroy() {
        finishScan("cancelled")
        stopNetworkWatch()
        super.onDestroy()
    }
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "voltraware/wifi")
            .setMethodCallHandler { call, result ->
                if (call.method == "scan") scanWifi(result) else result.notImplemented()
            }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "voltraware/network")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    startNetworkWatch(events)
                }
                override fun onCancel(arguments: Any?) {
                    stopNetworkWatch()
                }
            })
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
