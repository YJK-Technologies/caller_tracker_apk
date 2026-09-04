import 'package:call_log/call_log.dart';
import 'package:permission_handler/permission_handler.dart';

class CallLogService {
  static Future<List<CallLogEntry>> getTodaysMissedCalls() async {
    // Request Call Log & Phone permissions
    Map<Permission, PermissionStatus> statuses = await [
      Permission.phone,
    ].request();

    if (statuses[Permission.phone] != PermissionStatus.granted) {
      return [];
    }

    // Get timestamp for midnight today (00:00:00)
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final fromTimestamp = startOfToday.millisecondsSinceEpoch;

    // Fetch missed calls from today onwards
    final entries = await CallLog.query(
      dateFrom: fromTimestamp,
      type: CallType.missed,
    );

    return entries.toList();
  }
}