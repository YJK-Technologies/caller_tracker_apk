package com.example.caller_tracker_apk

import android.content.Context
import android.content.pm.PackageManager
import android.telephony.SubscriptionManager
import android.telephony.TelephonyManager
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.yjk.caller_tracker/device"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getDeviceMobileNumber" -> {
                    try {
                        result.success(readDeviceMobileNumber())
                    } catch (e: Exception) {
                        result.success(null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun readDeviceMobileNumber(): String? {
        val hasPhoneNumberPermission =
            ContextCompat.checkSelfPermission(
                this,
                android.Manifest.permission.READ_PHONE_NUMBERS
            ) == PackageManager.PERMISSION_GRANTED

        val hasPhoneStatePermission =
            ContextCompat.checkSelfPermission(
                this,
                android.Manifest.permission.READ_PHONE_STATE
            ) == PackageManager.PERMISSION_GRANTED

        if (!hasPhoneNumberPermission || !hasPhoneStatePermission) {
            return null
        }

        // Prefer active SIM subscription numbers. Android/carriers can return
        // an empty string even when the SIM is active.
        try {
            val subscriptionManager =
                getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE)
                    as SubscriptionManager

            val subscriptions = subscriptionManager.activeSubscriptionInfoList
            if (subscriptions != null) {
                for (subscription in subscriptions) {
                    val number = subscription.number?.trim()
                    if (!number.isNullOrEmpty()) return number
                }
            }
        } catch (_: SecurityException) {
        } catch (_: Exception) {
        }

        // Fallback for single-SIM/device implementations.
        try {
            val telephonyManager =
                getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
            val number = telephonyManager.line1Number?.trim()
            if (!number.isNullOrEmpty()) return number
        } catch (_: SecurityException) {
        } catch (_: Exception) {
        }

        return null
    }
}
