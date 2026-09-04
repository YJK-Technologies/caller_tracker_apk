import 'package:flutter/material.dart';
import 'package:call_log/call_log.dart';
import 'package:intl/intl.dart';
import 'call_log_service.dart';

class TodaysMissedCallsScreen extends StatefulWidget {
  const TodaysMissedCallsScreen({Key? key}) : super(key: key);

  @override
  State<TodaysMissedCallsScreen> createState() => _TodaysMissedCallsScreenState();
}

class _TodaysMissedCallsScreenState extends State<TodaysMissedCallsScreen> {
  late Future<List<CallLogEntry>> _missedCallsFuture;

  @override
  void initState() {
    super.initState();
    _refreshLogs();
  }

  void _refreshLogs() {
    setState(() {
      _missedCallsFuture = CallLogService.getTodaysMissedCalls();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Today's Missed Calls"),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshLogs,
          ),
        ],
      ),
      body: FutureBuilder<List<CallLogEntry>>(
        future: _missedCallsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text("Error fetching call logs: ${snapshot.error}"),
            );
          }

          final logs = snapshot.data ?? [];

          if (logs.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.phone_callback, size: 64, color: Colors.grey),
                  SizedBox(height: 12),
                  Text(
                    "No missed calls today!",
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => _refreshLogs(),
            child: ListView.builder(
              itemCount: logs.length,
              itemBuilder: (context, index) {
                final entry = logs[index];
                final callTime = DateTime.fromMillisecondsSinceEpoch(entry.timestamp ?? 0);
                final formattedTime = DateFormat('hh:mm a').format(callTime);

                final displayName = entry.name?.isNotEmpty == true 
                    ? entry.name! 
                    : (entry.number?.isNotEmpty == true ? entry.number! : 'Unknown Caller');

                final simInfo = entry.simDisplayName?.isNotEmpty == true
                    ? entry.simDisplayName!
                    : "SIM Slot: ${entry.phoneAccountId ?? 'Active'}";

                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  elevation: 2,
                  child: ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Colors.redAccent,
                      child: Icon(Icons.call_missed, color: Colors.white),
                    ),
                    title: Text(
                      displayName,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text("Time: $formattedTime • $simInfo"),
                    trailing: Text(
                      entry.number ?? '',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}