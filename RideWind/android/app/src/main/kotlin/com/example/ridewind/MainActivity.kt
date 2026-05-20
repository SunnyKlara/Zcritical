package com.example.ridewind

import android.app.Activity
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        const val CHANNEL = "com.example.ridewind/audio_capture"
        const val REQUEST_MEDIA_PROJECTION = 1001
    }

    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startCapture" -> {
                        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                            result.error("UNSUPPORTED", "需要 Android 10 或更高版本", null)
                            return@setMethodCallHandler
                        }
                        val ip = call.argument<String>("ip") ?: "192.168.4.1"
                        AudioCaptureService.esp32Ip = ip
                        pendingResult = result
                        val mpm = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
                        startActivityForResult(mpm.createScreenCaptureIntent(), REQUEST_MEDIA_PROJECTION)
                    }
                    "stopCapture" -> {
                        val intent = Intent(this, AudioCaptureService::class.java)
                        intent.action = AudioCaptureService.ACTION_STOP
                        startService(intent)
                        result.success(true)
                    }
                    "isCapturing" -> {
                        result.success(AudioCaptureService.isRunning)
                    }
                    "getStatus" -> {
                        result.success(AudioCaptureService.statusMessage)
                    }
                    "scanWifi" -> {
                        val wifiManager = applicationContext.getSystemService(WIFI_SERVICE) as android.net.wifi.WifiManager
                        @Suppress("DEPRECATION")
                        val success = wifiManager.startScan()
                        if (success) {
                            // Small delay for scan to complete
                            android.os.Handler(mainLooper).postDelayed({
                                @Suppress("DEPRECATION")
                                val results = wifiManager.scanResults
                                val wifiList = results
                                    .filter { it.SSID.isNotEmpty() }
                                    .distinctBy { it.SSID }
                                    .sortedByDescending { it.level }
                                    .take(15)
                                    .map { mapOf(
                                        "ssid" to it.SSID,
                                        "rssi" to it.level,
                                        "secure" to (it.capabilities.contains("WPA") || it.capabilities.contains("WEP"))
                                    )}
                                result.success(wifiList)
                            }, 3000)
                        } else {
                            // Return cached results
                            @Suppress("DEPRECATION")
                            val results = wifiManager.scanResults
                            val wifiList = results
                                .filter { it.SSID.isNotEmpty() }
                                .distinctBy { it.SSID }
                                .sortedByDescending { it.level }
                                .take(15)
                                .map { mapOf(
                                    "ssid" to it.SSID,
                                    "rssi" to it.level,
                                    "secure" to (it.capabilities.contains("WPA") || it.capabilities.contains("WEP"))
                                )}
                            result.success(wifiList)
                        }
                    }
                    "getConnectedWifi" -> {
                        val wifiManager = applicationContext.getSystemService(WIFI_SERVICE) as android.net.wifi.WifiManager
                        @Suppress("DEPRECATION")
                        val info = wifiManager.connectionInfo
                        if (info != null && info.networkId != -1) {
                            var ssid = info.ssid ?: ""
                            // Remove surrounding quotes from SSID
                            if (ssid.startsWith("\"") && ssid.endsWith("\"")) {
                                ssid = ssid.substring(1, ssid.length - 1)
                            }
                            // Get frequency in MHz
                            val frequency = info.frequency
                            result.success(mapOf(
                                "ssid" to ssid,
                                "frequency" to frequency
                            ))
                        } else {
                            result.success(null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        if (requestCode == REQUEST_MEDIA_PROJECTION) {
            if (resultCode == Activity.RESULT_OK && data != null) {
                val intent = Intent(this, AudioCaptureService::class.java).apply {
                    action = AudioCaptureService.ACTION_START
                    putExtra(AudioCaptureService.EXTRA_RESULT_CODE, resultCode)
                    putExtra(AudioCaptureService.EXTRA_RESULT_DATA, data)
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    startForegroundService(intent)
                } else {
                    startService(intent)
                }
                pendingResult?.success(true)
            } else {
                pendingResult?.success(false)
            }
            pendingResult = null
        }
    }
}
