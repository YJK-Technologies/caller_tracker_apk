import 'package:flutter/material.dart';
import 'caller_tracker_sync_service.dart';
import 'todays_missed_calls_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await CallerTrackerSyncService.initialize();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Caller Tracker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.redAccent,
      ),
      home: const TodaysMissedCallsScreen(),
    );
  }
}
