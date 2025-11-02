import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/monitor_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/tips_screen.dart';
import 'screens/logs_screen.dart';
import 'state/monitor_state.dart';
import 'theme.dart';
import 'services/notification_service.dart';

void main() {
  runApp(const SmartBabyApp());
}

class SmartBabyApp extends StatelessWidget {
  const SmartBabyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => BabyMonitorState(),
      child: Consumer<BabyMonitorState>(
        builder: (context, state, _) {
          // Register notification action handler so notifications can trigger app actions
          NotificationService().setActionHandler((actionId) {
            switch (actionId) {
              case 'mute':
                state.setMuteWindow(const Duration(minutes: 30));
                break;
              case 'open':
                // no-op here; tapping notification will already open the app
                break;
            }
          });
          return MaterialApp(
            title: 'Baby Monitor',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.themeData(state.themeType),
            home: const RootShell(),
          );
        },
      ),
    );
  }
}

class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final screens = const [
      MonitorScreen(key: ValueKey('monitor')),
      LogsScreen(key: ValueKey('logs')),
      TipsScreen(key: ValueKey('tips')),
      SettingsScreen(key: ValueKey('settings')),
    ];

    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        child: screens[_selectedIndex],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.monitor_heart_outlined),
            selectedIcon: Icon(Icons.monitor_heart),
            label: 'Monitor',
          ),
          NavigationDestination(
            icon: Icon(Icons.analytics_outlined),
            selectedIcon: Icon(Icons.analytics),
            label: 'Logs',
          ),
          NavigationDestination(
            icon: Icon(Icons.child_care_outlined),
            selectedIcon: Icon(Icons.child_care),
            label: 'Tips',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
