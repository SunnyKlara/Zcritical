package com.zcritical.t1

import android.app.*
import android.content.Intent
import android.media.*
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import java.io.OutputStream
import java.net.InetSocketAddress
import java.net.Socket

/**
 * Foreground service: capture system audio → TCP stream to ESP32.
 *
 * Requires phone to be connected to WiFi "T1_Audio" (192.168.4.1).
 * Captures system audio via AudioPlaybackCapture (Android 10+).
 * Streams raw PCM (44100Hz 16-bit stereo) to ESP32 TCP port 8080.
 */
class AudioCaptureService : Service() {

    companion object {
        const val TAG = "AudioCapture"
        const val CHANNEL_ID = "audio_capture_channel"
        const val NOTIFICATION_ID = 1001
        const val ACTION_START = "ACTION_START"
        const val ACTION_STOP = "ACTION_STOP"
        const val EXTRA_RESULT_CODE = "EXTRA_RESULT_CODE"
        const val EXTRA_RESULT_DATA = "EXTRA_RESULT_DATA"

        const val ESP32_PORT = 8080
        const val SAMPLE_RATE = 44100

        @Volatile var isRunning = false
        @Volatile var statusMessage = "未启动"
        @Volatile var esp32Ip = "192.168.4.1"
    }

    private var mediaProjection: MediaProjection? = null
    private var audioRecord: AudioRecord? = null
    private var streamThread: Thread? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        Log.i(TAG, "Service created")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.i(TAG, "onStartCommand: action=${intent?.action}")
        when (intent?.action) {
            ACTION_START -> {
                val resultCode = intent.getIntExtra(EXTRA_RESULT_CODE, Activity.RESULT_CANCELED)
                val resultData = intent.getParcelableExtra<Intent>(EXTRA_RESULT_DATA)
                if (resultCode == Activity.RESULT_OK && resultData != null) {
                    startForeground(NOTIFICATION_ID, buildNotification("正在启动..."))
                    startCaptureAndStream(resultCode, resultData)
                } else {
                    Log.e(TAG, "Invalid result code or data")
                    statusMessage = "权限获取失败"
                    stopSelf()
                }
            }
            ACTION_STOP -> {
                stopCapture()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
        }
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        stopCapture()
        super.onDestroy()
        Log.i(TAG, "Service destroyed")
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID, "音频投射", NotificationManager.IMPORTANCE_LOW
            ).apply { description = "正在将音频投射到 Zcritical T1 设备" }
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }

    private fun buildNotification(text: String): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Zcritical T1 音频投射")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setOngoing(true)
            .build()
    }

    private fun updateNotification(text: String) {
        statusMessage = text
        Log.i(TAG, "Status: $text")
        try {
            val nm = getSystemService(NotificationManager::class.java)
            nm.notify(NOTIFICATION_ID, buildNotification(text))
        } catch (e: Exception) {
            Log.w(TAG, "Failed to update notification: ${e.message}")
        }
    }

    private fun startCaptureAndStream(resultCode: Int, resultData: Intent) {
        Log.i(TAG, "Starting capture pipeline...")

        val mpm = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        mediaProjection = mpm.getMediaProjection(resultCode, resultData)
        if (mediaProjection == null) {
            Log.e(TAG, "MediaProjection is null")
            updateNotification("音频捕获权限失败")
            stopSelf()
            return
        }
        Log.i(TAG, "MediaProjection obtained")

        val minBuf = AudioRecord.getMinBufferSize(
            SAMPLE_RATE, AudioFormat.CHANNEL_IN_STEREO, AudioFormat.ENCODING_PCM_16BIT
        )
        val bufSize = minBuf * 2
        Log.i(TAG, "AudioRecord buffer size: $bufSize (min=$minBuf)")

        try {
            val captureConfig = AudioPlaybackCaptureConfiguration.Builder(mediaProjection!!)
                .addMatchingUsage(AudioAttributes.USAGE_MEDIA)
                .addMatchingUsage(AudioAttributes.USAGE_GAME)
                .addMatchingUsage(AudioAttributes.USAGE_UNKNOWN)
                .build()

            audioRecord = AudioRecord.Builder()
                .setAudioPlaybackCaptureConfig(captureConfig)
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setSampleRate(SAMPLE_RATE)
                        .setChannelMask(AudioFormat.CHANNEL_IN_STEREO)
                        .build()
                )
                .setBufferSizeInBytes(bufSize)
                .build()
        } catch (e: Exception) {
            Log.e(TAG, "AudioRecord creation failed: ${e.message}")
            updateNotification("音频录制创建失败")
            stopSelf()
            return
        }

        if (audioRecord?.state != AudioRecord.STATE_INITIALIZED) {
            Log.e(TAG, "AudioRecord not initialized, state=${audioRecord?.state}")
            updateNotification("音频录制初始化失败")
            stopSelf()
            return
        }

        Log.i(TAG, "AudioRecord initialized, starting recording...")
        audioRecord?.startRecording()
        isRunning = true

        streamThread = Thread {
            streamLoop(bufSize)
        }.apply {
            name = "AudioStreamThread"
            start()
        }

        updateNotification("正在连接 ESP32...")
    }

    private fun streamLoop(bufSize: Int) {
        val buffer = ByteArray(bufSize)
        var connectRetries = 0
        val maxConnectRetries = 10
        Log.i(TAG, "Stream thread started, connecting to ${esp32Ip}:$ESP32_PORT")

        while (isRunning) {
            var socket: Socket? = null
            var output: OutputStream? = null
            try {
                socket = Socket()
                socket.tcpNoDelay = true
                socket.connect(InetSocketAddress(esp32Ip, ESP32_PORT), 5000)
                output = socket.getOutputStream()

                Log.i(TAG, "TCP connected to ESP32!")
                updateNotification("正在投射音频 ♪")
                connectRetries = 0

                while (isRunning && !socket.isClosed) {
                    val bytesRead = audioRecord?.read(buffer, 0, buffer.size) ?: -1
                    if (bytesRead > 0) {
                        output.write(buffer, 0, bytesRead)
                    } else if (bytesRead < 0) {
                        Log.w(TAG, "AudioRecord read error: $bytesRead")
                        break
                    }
                }
            } catch (e: Exception) {
                if (isRunning) {
                    connectRetries++
                    Log.w(TAG, "TCP error ($connectRetries/$maxConnectRetries): ${e.message}")
                    if (connectRetries >= maxConnectRetries) {
                        updateNotification("连接失败，已停止重试")
                        Log.e(TAG, "Max retries reached, stopping")
                        isRunning = false
                        break
                    }
                    updateNotification("连接失败，重试中 ($connectRetries/$maxConnectRetries)")
                    try { Thread.sleep(3000) } catch (_: InterruptedException) { break }
                }
            } finally {
                try { output?.close() } catch (_: Exception) {}
                try { socket?.close() } catch (_: Exception) {}
            }
        }
        Log.i(TAG, "Stream thread exiting")
    }

    private fun stopCapture() {
        Log.i(TAG, "Stopping capture...")
        isRunning = false
        statusMessage = "已停止"

        try { audioRecord?.stop() } catch (_: Exception) {}
        try { audioRecord?.release() } catch (_: Exception) {}
        audioRecord = null

        try { mediaProjection?.stop() } catch (_: Exception) {}
        mediaProjection = null

        streamThread?.interrupt()
        streamThread = null
        Log.i(TAG, "Capture stopped")
    }
}
