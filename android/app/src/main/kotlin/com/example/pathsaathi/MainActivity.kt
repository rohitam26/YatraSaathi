package com.example.pathsaathi

import android.Manifest
import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.telephony.SmsManager
import android.telephony.TelephonyManager
import androidx.annotation.NonNull
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicBoolean

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.pathsaathi/direct_sms"
    private val SMS_PERMISSION_REQUEST_CODE = 9871

    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isDirectSmsSupported" -> {
                    val hasTelephony = packageManager.hasSystemFeature(PackageManager.FEATURE_TELEPHONY)
                    result.success(hasTelephony)
                }

                "checkSmsPermission" -> {
                    val granted = ContextCompat.checkSelfPermission(
                        this,
                        Manifest.permission.SEND_SMS
                    ) == PackageManager.PERMISSION_GRANTED
                    result.success(granted)
                }

                "requestSmsPermission" -> {
                    if (ContextCompat.checkSelfPermission(
                            this,
                            Manifest.permission.SEND_SMS
                        ) == PackageManager.PERMISSION_GRANTED
                    ) {
                        result.success(true)
                    } else {
                        pendingPermissionResult = result
                        ActivityCompat.requestPermissions(
                            this,
                            arrayOf(Manifest.permission.SEND_SMS),
                            SMS_PERMISSION_REQUEST_CODE
                        )
                    }
                }

                "getSimStatus" -> {
                    val simInfo = checkSimStatus()
                    result.success(simInfo)
                }

                "sendDirectSms" -> {
                    val phone = call.argument<String>("phoneNumber")
                    val message = call.argument<String>("message")

                    if (phone.isNullOrBlank() || message.isNullOrBlank()) {
                        result.success(
                            mapOf(
                                "status" to "FAILED",
                                "error" to "INVALID_ARGUMENTS",
                                "message" to "Phone number or message body cannot be empty."
                            )
                        )
                        return@setMethodCallHandler
                    }

                    executeSendSms(phone.trim(), message.trim(), result)
                }

                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == SMS_PERMISSION_REQUEST_CODE) {
            val isGranted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingPermissionResult?.success(isGranted)
            pendingPermissionResult = null
        }
    }

    private fun checkSimStatus(): Map<String, Any> {
        val telephonyManager = getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
        if (telephonyManager == null) {
            return mapOf(
                "isAvailable" to false,
                "state" to "UNAVAILABLE",
                "isDualSim" to false,
                "simCount" to 0
            )
        }

        val stateCode = telephonyManager.simState
        val stateStr = when (stateCode) {
            TelephonyManager.SIM_STATE_READY -> "READY"
            TelephonyManager.SIM_STATE_ABSENT -> "ABSENT"
            TelephonyManager.SIM_STATE_PIN_REQUIRED -> "PIN_REQUIRED"
            TelephonyManager.SIM_STATE_PUK_REQUIRED -> "PUK_REQUIRED"
            TelephonyManager.SIM_STATE_NETWORK_LOCKED -> "NETWORK_LOCKED"
            else -> "NOT_READY"
        }

        var isDualSim = false
        var simCount = 1

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val activeModemCount = telephonyManager.activeModemCount
            isDualSim = activeModemCount > 1
            simCount = activeModemCount
        } else {
            val phoneCount = telephonyManager.phoneCount
            isDualSim = phoneCount > 1
            simCount = phoneCount
        }

        return mapOf(
            "isAvailable" to (stateCode == TelephonyManager.SIM_STATE_READY),
            "state" to stateStr,
            "isDualSim" to isDualSim,
            "simCount" to simCount
        )
    }

    private fun executeSendSms(
        phoneNumber: String,
        message: String,
        result: MethodChannel.Result
    ) {
        // 1. Permission Check
        val hasPermission = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.SEND_SMS
        ) == PackageManager.PERMISSION_GRANTED
        if (!hasPermission) {
            result.success(
                mapOf(
                    "status" to "FAILED",
                    "error" to "PERMISSION_DENIED",
                    "message" to "SEND_SMS permission has not been granted by user."
                )
            )
            return
        }

        // 2. SIM Readiness Check
        val telephonyManager = getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
        if (telephonyManager?.simState != TelephonyManager.SIM_STATE_READY) {
            result.success(
                mapOf(
                    "status" to "FAILED",
                    "error" to "SIM_NOT_READY",
                    "message" to "Active SIM card is not ready or cellular network is disconnected."
                )
            )
            return
        }

        // 3. Obtain SmsManager
        val smsManager: SmsManager = try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                getSystemService(SmsManager::class.java)
            } else {
                @Suppress("DEPRECATION")
                SmsManager.getDefault()
            }
        } catch (e: Exception) {
            result.success(
                mapOf(
                    "status" to "FAILED",
                    "error" to "SMS_MANAGER_ERROR",
                    "message" to "Could not initialize Android SmsManager: ${e.message}"
                )
            )
            return
        }

        val uniqueAction = "com.example.pathsaathi.SMS_SENT_${System.currentTimeMillis()}_${(1000..9999).random()}"
        val hasReplied = AtomicBoolean(false)
        val mainHandler = Handler(Looper.getMainLooper())

        val sentReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                try {
                    context?.unregisterReceiver(this)
                } catch (_: Exception) {}

                if (!hasReplied.compareAndSet(false, true)) return

                val resultCode = resultCode
                mainHandler.post {
                    if (resultCode == Activity.RESULT_OK) {
                        result.success(
                            mapOf(
                                "status" to "SENT",
                                "message" to "SMS successfully transmitted to cellular carrier radio.",
                                "resultCode" to resultCode
                            )
                        )
                    } else {
                        val errorReason = when (resultCode) {
                            SmsManager.RESULT_ERROR_GENERIC_FAILURE -> "GENERIC_FAILURE"
                            SmsManager.RESULT_ERROR_NO_SERVICE -> "NO_SERVICE"
                            SmsManager.RESULT_ERROR_NULL_PDU -> "NULL_PDU"
                            SmsManager.RESULT_ERROR_RADIO_OFF -> "RADIO_OFF"
                            else -> "ERROR_CODE_$resultCode"
                        }
                        result.success(
                            mapOf(
                                "status" to "FAILED",
                                "error" to errorReason,
                                "message" to "Carrier network rejected SMS transmission ($errorReason).",
                                "resultCode" to resultCode
                            )
                        )
                    }
                }
            }
        }

        // Register receiver for sent broadcast
        val filter = IntentFilter(uniqueAction)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(sentReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(sentReceiver, filter)
        }

        // 15-second watchdog timer in case radio broadcast never arrives
        mainHandler.postDelayed({
            if (hasReplied.compareAndSet(false, true)) {
                try {
                    unregisterReceiver(sentReceiver)
                } catch (_: Exception) {}
                result.success(
                    mapOf(
                        "status" to "FAILED",
                        "error" to "TIMEOUT",
                        "message" to "Carrier dispatch confirmation timed out after 15 seconds."
                    )
                )
            }
        }, 15000)

        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_ONE_SHOT
        } else {
            PendingIntent.FLAG_ONE_SHOT
        }

        val sentIntent = PendingIntent.getBroadcast(
            this,
            (1000..9999).random(),
            Intent(uniqueAction),
            flags
        )

        try {
            val parts = smsManager.divideMessage(message)
            if (parts.size > 1) {
                val sentIntents = ArrayList<PendingIntent>()
                for (i in 0 until parts.size) {
                    // Attach sent intent to the final part
                    if (i == parts.size - 1) {
                        sentIntents.add(sentIntent)
                    } else {
                        sentIntents.add(
                            PendingIntent.getBroadcast(
                                this,
                                (10000..99999).random(),
                                Intent("DUMMY_ACTION_$i"),
                                flags
                            )
                        )
                    }
                }
                smsManager.sendMultipartTextMessage(phoneNumber, null, parts, sentIntents, null)
            } else {
                smsManager.sendTextMessage(phoneNumber, null, message, sentIntent, null)
            }
        } catch (e: Exception) {
            if (hasReplied.compareAndSet(false, true)) {
                try {
                    unregisterReceiver(sentReceiver)
                } catch (_: Exception) {}
                result.success(
                    mapOf(
                        "status" to "FAILED",
                        "error" to "DISPATCH_EXCEPTION",
                        "message" to "Exception dispatching SMS via SmsManager: ${e.message}"
                    )
                )
            }
        }
    }
}
