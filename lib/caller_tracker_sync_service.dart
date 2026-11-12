import 'dart:async';
import 'dart:io';

import 'package:call_log/call_log.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'dart:convert';

/// Supply these values at build time:
/// --dart-define=CALLER_TRACKER_API_BASE_URL=https://your-host:5547
/// --dart-define=CALLER_TRACKER_COMPANY_CODE=YJKT
/// --dart-define=CALLER_TRACKER_LOCATION_CODE=PON001
/// --dart-define=CALLER_TRACKER_CREATED_BY=USERCODE
class CallerTrackerSyncService {
  static const String apiBaseUrl = String.fromEnvironment(
    'CALLER_TRACKER_API_BASE_URL',
    defaultValue: 'http://192.168.29.123:5547',
  );

  static const String companyCode = String.fromEnvironment(
    'CALLER_TRACKER_COMPANY_CODE',
    defaultValue: 'YJKT',
  );

  static const String locationCode = String.fromEnvironment(
    'CALLER_TRACKER_LOCATION_CODE',
    defaultValue: 'YJKT001',
  );

  static const String createdBy = String.fromEnvironment(
    'CALLER_TRACKER_CREATED_BY',
    defaultValue: 'YJKADMIN',
  );

  static const String _configPath = '/callerTracker/config';
  static const String _syncPath = '/syncCallerTracker';
  static const String _lastSuccessKey = 'caller_tracker_last_success_ms';
  static const String _deviceMobileKey = 'caller_tracker_device_mobile';
  static const String _taskName = 'callerTrackerPeriodicSync';
  static const MethodChannel _deviceChannel = MethodChannel(
    'com.yjk.caller_tracker/device',
  );

  static bool _running = false;

  static Future<void> initialize() async {
    if (!Platform.isAndroid) return;

    await Workmanager().initialize(callbackDispatcher);
    await refreshScheduleFromBackend();
  }

  static Future<void> refreshScheduleFromBackend() async {
    if (apiBaseUrl.isEmpty) {
      // API URL is not configured. Sync remains disabled.
      return;
    }

    try {
      final config = await _getBackendConfig();

      if (config['enabled'] != true) {
        await Workmanager().cancelByUniqueName(_taskName);
        return;
      }

      final int configuredMinutes =
          (config['intervalMinutes'] as num?)?.toInt() ?? 60;

      // Android WorkManager minimum periodic interval is 15 minutes.
      final int workManagerMinutes = configuredMinutes < 15
          ? 15
          : configuredMinutes;

      await Workmanager().registerPeriodicTask(
        _taskName,
        _taskName,
        frequency: Duration(minutes: workManagerMinutes),

        // Correct enum for periodic tasks.
        existingWorkPolicy: ExistingPeriodicWorkPolicy.update,

        constraints: Constraints(networkType: NetworkType.connected),
      );
    } catch (e) {
      // Keep the existing registered periodic job; retry on next app launch.
      // Do not reset the last-success watermark here.
    }
  }

  static Future<Map<String, dynamic>> _getBackendConfig() async {
    final uri = Uri.parse('$apiBaseUrl$_configPath');
    final response = await http.get(uri).timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception('Config API failed: ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic> || decoded['success'] != true) {
      throw Exception('Invalid backend configuration response');
    }

    final config = decoded['config'];
    if (config is! Map<String, dynamic>) {
      throw Exception('Backend config object is missing');
    }
    return config;
  }

  static Future<String?> _getDeviceMobileNumber() async {
    final prefs = await SharedPreferences.getInstance();

    // Reuse only a previously obtained number; never ask the user to type it.
    final cached = _normalizeMobile(prefs.getString(_deviceMobileKey) ?? '');
    if (cached != null) return cached;

    try {
      final raw = await _deviceChannel.invokeMethod<String>(
        'getDeviceMobileNumber',
      );
      final normalized = _normalizeMobile(raw ?? '');
      if (normalized != null) {
        await prefs.setString(_deviceMobileKey, normalized);
      }
      return normalized;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  static String? _normalizeMobile(String raw) {
    var value = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (value.length == 12 && value.startsWith('91')) {
      value = value.substring(2);
    } else if (value.length == 11 && value.startsWith('0')) {
      value = value.substring(1);
    }

    if (!RegExp(r'^[6-9][0-9]{9}$').hasMatch(value)) return null;
    return value;
  }

  static Future<bool> syncNow() async {
    if (!Platform.isAndroid || _running) return false;
    if (apiBaseUrl.isEmpty ||
        companyCode.isEmpty ||
        locationCode.isEmpty ||
        createdBy.isEmpty) {
      return false;
    }

    _running = true;
    try {
      final config = await _getBackendConfig();
      if (config['enabled'] != true) return true;

      // The app must already have runtime permissions. A background worker
      // cannot reliably show a permission prompt.
      final callPermission = await Permission.phone.status;
      if (!callPermission.isGranted) return false;

      final deviceMobile = await _getDeviceMobileNumber();
      if (deviceMobile == null) {
        // Android/carrier may not expose the SIM's own number.
        // Never substitute a caller number for MobileNo.
        return false;
      }

      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      final nowMs = now.millisecondsSinceEpoch;

      // First run: look back 24 hours. Later runs: strictly after last
      // successful watermark. A small overlap is intentionally avoided.
      final lastSuccess = prefs.getInt(_lastSuccessKey);
      final fromMs =
          lastSuccess ??
          now.subtract(const Duration(hours: 24)).millisecondsSinceEpoch;

      final entries = await CallLog.query(
        dateFrom: fromMs + (lastSuccess == null ? 0 : 1),
        dateTo: nowMs,
        type: CallType.missed,
      );

      final List<Map<String, String>> calls = [];
      for (final entry in entries) {
        final number = _normalizeMobile(entry.number ?? '');
        final timestamp = entry.timestamp;
        if (number == null || timestamp == null) continue;

        calls.add({
          'MissedCallNo': number,
          'MissedCallDate': DateTime.fromMillisecondsSinceEpoch(
            timestamp,
          ).toIso8601String(),
        });
      }

      final int batchSize = (config['maxBatchSize'] as num?)?.toInt() ?? 100;
      if (batchSize < 1) throw Exception('Invalid backend batch size');

      // Do not move the watermark until every batch succeeds.
      for (var start = 0; start < calls.length; start += batchSize) {
        final end = (start + batchSize < calls.length)
            ? start + batchSize
            : calls.length;
        final batch = calls.sublist(start, end);
        await _postBatch(deviceMobile, batch);
      }

      // If there are no valid calls, this still records a successful scan.
      await prefs.setInt(_lastSuccessKey, nowMs);
      return true;
    } catch (e) {
      // Keep the old watermark. The next run retries this time range.
      return false;
    } finally {
      _running = false;
    }
  }

  static Future<void> _postBatch(
    String mobileNo,
    List<Map<String, String>> calls,
  ) async {
    final uri = Uri.parse('$apiBaseUrl$_syncPath');
    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'MobileNo': mobileNo,
            'company_code': companyCode,
            // Keep the field name used by the uploaded controller/SP.
            'location_code': locationCode,
            'created_by': createdBy,
            'calls': calls,
          }),
        )
        .timeout(const Duration(seconds: 60));

    if (response.statusCode != 200) {
      throw Exception(
        'Sync API failed (${response.statusCode}): ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic> || decoded['success'] != true) {
      throw Exception('Backend did not confirm successful sync');
    }
  }
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task == CallerTrackerSyncService._taskName) {
      final ok = await CallerTrackerSyncService.syncNow();
      return ok;
    }
    return true;
  });
}
