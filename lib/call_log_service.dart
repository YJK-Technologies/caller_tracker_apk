import 'package:call_log/call_log.dart';
import 'package:permission_handler/permission_handler.dart';

class CallLogService {
  static Future<List<CallLogEntry>> getTodaysMissedCalls() async {
    // call_log access requires Android call-log/phone permission.
    final status = await Permission.phone.request();
    if (!status.isGranted) return [];

    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);

    final entries = await CallLog.query(
      dateFrom: startOfToday.millisecondsSinceEpoch,
      dateTo: now.millisecondsSinceEpoch,
      type: CallType.missed,
    );

    return entries.toList();
  }
}
