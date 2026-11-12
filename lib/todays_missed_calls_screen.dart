import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:call_log/call_log.dart';
import 'package:intl/intl.dart';
import 'call_log_service.dart';
import 'caller_tracker_sync_service.dart';

class TodaysMissedCallsScreen extends StatefulWidget {
  const TodaysMissedCallsScreen({Key? key}) : super(key: key);

  @override
  State<TodaysMissedCallsScreen> createState() =>
      _TodaysMissedCallsScreenState();
}

class _TodaysMissedCallsScreenState
    extends State<TodaysMissedCallsScreen>
    with WidgetsBindingObserver {

  late Future<List<CallLogEntry>> _missedCallsFuture;

  Timer? _pollingTimer;

  static const Color background = Color(0xFF0F172A);
  static const Color cardColor = Color(0xFF1E293B);
  static const Color accentColor = Color(0xFFEF4444);

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    _refreshLogs();
    CallerTrackerSyncService.syncNow();
    CallerTrackerSyncService.refreshScheduleFromBackend();

    _startPolling();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    _pollingTimer?.cancel();

    super.dispose();
  }

  // Poll missed calls every one hour
  void _startPolling() {
    _pollingTimer?.cancel();

    _pollingTimer = Timer.periodic(
      const Duration(hours: 1),
      (timer) async {
        if (mounted) {
          await CallerTrackerSyncService.syncNow();
          await _refreshLogs();
        }
      },
    );
  }

  // Refresh when application resumes
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      CallerTrackerSyncService.syncNow();
      CallerTrackerSyncService.refreshScheduleFromBackend();
      _refreshLogs();
    }
  }

  // Load today's missed calls
  Future<List<CallLogEntry>> _loadLogs() async {

    if (!Platform.isAndroid) {
      throw UnsupportedError(
        'Call logs are available only on supported Android devices.',
      );
    }

    final List<CallLogEntry> entries =
        await CallLogService.getTodaysMissedCalls();

    return entries;
  }

  // Refresh missed call list
  Future<void> _refreshLogs() async {

    if (!mounted) return;

    final Future<List<CallLogEntry>> future = _loadLogs();

    setState(() {
      _missedCallsFuture = future;
    });

    try {
      await future;
    } catch (e) {
      debugPrint('Error loading missed calls: $e');
    }
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      backgroundColor: background,

      appBar: AppBar(
        backgroundColor: cardColor,
        elevation: 0,

        title: const Text(
          'Missed Calls Tracker',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),

        actions: [
          IconButton(
            onPressed: _refreshLogs,
            icon: const Icon(
              Icons.refresh_rounded,
              color: accentColor,
            ),
            tooltip: "Refresh",
          ),
        ],
      ),

      body: FutureBuilder<List<CallLogEntry>>(
        future: _missedCallsFuture,

        builder: (context, snapshot) {

          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {

            return const Center(
              child: CircularProgressIndicator(
                color: accentColor,
              ),
            );
          }

          if (snapshot.hasError && !snapshot.hasData) {
            return _buildErrorState(snapshot.error);
          }

          final List<CallLogEntry> logs =
              snapshot.data ?? [];

          return RefreshIndicator(
            color: accentColor,
            backgroundColor: cardColor,
            onRefresh: _refreshLogs,

            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),

              slivers: [

                SliverToBoxAdapter(
                  child: _buildSummary(logs.length),
                ),

                if (logs.isEmpty)

                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _buildEmptyState(),
                  )

                else

                  SliverPadding(
                    padding: const EdgeInsets.all(16),

                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          return _buildCallCard(logs[index]);
                        },
                        childCount: logs.length,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  // Today's missed call summary
  Widget _buildSummary(int count) {

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),

      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF7F1D1D),
            Color(0xFF991B1B),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
      ),

      child: Row(
        children: [

          const CircleAvatar(
            radius: 28,
            backgroundColor: Color(0x33FFFFFF),

            child: Icon(
              Icons.phone_missed_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),

          const SizedBox(width: 16),

          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              const Text(
                "Today's Summary",
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),

              const SizedBox(height: 5),

              Text(
                '$count Missed Call${count == 1 ? '' : 's'}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Individual missed call card
  Widget _buildCallCard(CallLogEntry entry) {

    final bool hasName =
        entry.name?.trim().isNotEmpty == true;

    final bool hasNumber =
        entry.number?.trim().isNotEmpty == true;

    final String displayName = hasName
        ? entry.name!.trim()
        : hasNumber
            ? entry.number!.trim()
            : 'Unknown Caller';

    final int? timestamp = entry.timestamp;

    final String formattedTime = timestamp != null
        ? DateFormat('hh:mm a').format(
            DateTime.fromMillisecondsSinceEpoch(timestamp),
          )
        : 'Time unavailable';

    final String initials = hasName
        ? displayName.substring(0, 1).toUpperCase()
        : '#';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),

      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),

        border: Border.all(
          color: Colors.white.withOpacity(0.06),
        ),
      ),

      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 10,
        ),

        leading: CircleAvatar(
          radius: 25,
          backgroundColor: accentColor.withOpacity(0.15),

          child: Text(
            initials,
            style: const TextStyle(
              color: accentColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),

        title: Text(
          displayName,

          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),

          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),

        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),

          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              Row(
                children: [

                  const Icon(
                    Icons.access_time_rounded,
                    color: Colors.grey,
                    size: 14,
                  ),

                  const SizedBox(width: 5),

                  Text(
                    formattedTime,
                    style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),

              if (hasName && hasNumber) ...[

                const SizedBox(height: 4),

                Text(
                  entry.number!,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),

        trailing: IconButton(
          onPressed: () {},
          icon: const Icon(
            Icons.phone_rounded,
            color: Colors.greenAccent,
          ),
          tooltip: 'Call Back',
        ),
      ),
    );
  }

  // Empty missed calls screen
  Widget _buildEmptyState() {

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [

          const CircleAvatar(
            radius: 42,
            backgroundColor: Color(0xFF1E293B),

            child: Icon(
              Icons.check_circle_outline_rounded,
              color: Colors.greenAccent,
              size: 48,
            ),
          ),

          const SizedBox(height: 20),

          const Text(
            'All Caught Up!',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
          ),

          const SizedBox(height: 8),

          const Text(
            'No missed calls recorded today.',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 14,
            ),
          ),

          const SizedBox(height: 20),

          OutlinedButton.icon(
            onPressed: _refreshLogs,
            icon: const Icon(Icons.refresh),
            label: const Text('Sync & Refresh'),

            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  // Error screen
  Widget _buildErrorState(Object? error) {

    final bool isUnsupported =
        error is UnsupportedError;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),

        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [

            const Icon(
              Icons.error_outline_rounded,
              color: accentColor,
              size: 60,
            ),

            const SizedBox(height: 18),

            Text(
              isUnsupported
                  ? 'Platform Not Supported'
                  : 'Unable to Load Call Logs',

              style: const TextStyle(
                color: Colors.white,
                fontSize: 19,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 10),

            Text(
              isUnsupported
                  ? 'Please run this application on a supported Android device to access missed calls.'
                  : 'Please check call log permissions and plugin configuration, then try again.',

              textAlign: TextAlign.center,

              style: const TextStyle(
                color: Colors.white60,
                fontSize: 14,
                height: 1.5,
              ),
            ),

            const SizedBox(height: 20),

            ElevatedButton.icon(
              onPressed: _refreshLogs,
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),

              style: ElevatedButton.styleFrom(
                backgroundColor: accentColor,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
