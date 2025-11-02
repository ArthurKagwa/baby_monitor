import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../state/monitor_state.dart';

/// Repository for persisting and retrieving device readings locally
class ReadingsRepository {
  static const String _keyLastTemperature = 'last_temperature';
  static const String _keyLastTempAlert = 'last_temp_alert';
  static const String _keyLastCryState = 'last_cry_state';
  static const String _keyLastConnected = 'last_connected';
  static const String _keyDeviceName = 'device_name';
  static const String _keyTempHistory = 'temp_history';
  static const String _keyCryEvents = 'cry_events';
  static const String _keyCareLogs = 'care_logs';

  /// Save the current device state
  Future<void> saveCurrentState({
    required double? temperature,
    required TempAlertStatus tempAlert,
    required bool crying,
    required String deviceName,
    required List<TempSample> tempHistory,
    required List<CryEvent> cryEvents,
    required List<CareLogEntry> careLogs,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    
    if (temperature != null) {
      await prefs.setDouble(_keyLastTemperature, temperature);
    } else {
      await prefs.remove(_keyLastTemperature);
    }
    
    await prefs.setString(_keyLastTempAlert, tempAlert.toString());
    await prefs.setBool(_keyLastCryState, crying);
    await prefs.setString(_keyLastConnected, DateTime.now().toIso8601String());
    await prefs.setString(_keyDeviceName, deviceName);
    
    // Save temperature history (last 100 samples to avoid storage bloat)
    final historyJson = tempHistory.take(100).map((sample) => {
      'timestamp': sample.timestamp.toIso8601String(),
      'temperature': sample.temperature,
    }).toList();
    await prefs.setString(_keyTempHistory, json.encode(historyJson));
    
    // Save cry events (last 50)
    final cryEventsJson = cryEvents.take(50).map((event) => {
      'start': event.start.toIso8601String(),
      'end': event.end?.toIso8601String(),
    }).toList();
    await prefs.setString(_keyCryEvents, json.encode(cryEventsJson));
    
    // Save care logs (last 100)
    final careLogsJson = careLogs.take(100).map((log) => {
      'timestamp': log.timestamp.toIso8601String(),
      'type': log.type.name,
      'note': log.note,
      'amount': log.amount,
    }).toList();
    await prefs.setString(_keyCareLogs, json.encode(careLogsJson));
  }

  /// Get the last saved device state
  Future<Map<String, dynamic>?> getLastState() async {
    final prefs = await SharedPreferences.getInstance();
    
    final lastConnectedStr = prefs.getString(_keyLastConnected);
    if (lastConnectedStr == null) {
      return null; // No saved state
    }
    
    final temperature = prefs.getDouble(_keyLastTemperature);
    final tempAlertStr = prefs.getString(_keyLastTempAlert);
    final crying = prefs.getBool(_keyLastCryState);
    final deviceName = prefs.getString(_keyDeviceName);
    final lastConnected = DateTime.parse(lastConnectedStr);
    
    // Parse temperature history
    final tempHistoryStr = prefs.getString(_keyTempHistory);
    final List<TempSample> tempHistory = [];
    if (tempHistoryStr != null) {
      try {
        final List<dynamic> historyJson = json.decode(tempHistoryStr);
        for (final item in historyJson) {
          tempHistory.add(TempSample(
            DateTime.parse(item['timestamp']),
            item['temperature'],
          ));
        }
      } catch (_) {}
    }
    
    // Parse cry events
    final cryEventsStr = prefs.getString(_keyCryEvents);
    final List<CryEvent> cryEvents = [];
    if (cryEventsStr != null) {
      try {
        final List<dynamic> eventsJson = json.decode(cryEventsStr);
        for (final item in eventsJson) {
          cryEvents.add(CryEvent(
            start: DateTime.parse(item['start']),
            end: item['end'] != null ? DateTime.parse(item['end']) : null,
          ));
        }
      } catch (_) {}
    }
    
    // Parse care logs
    final careLogsStr = prefs.getString(_keyCareLogs);
    final List<CareLogEntry> careLogs = [];
    if (careLogsStr != null) {
      try {
        final List<dynamic> logsJson = json.decode(careLogsStr);
        for (final item in logsJson) {
          final typeStr = item['type'] as String;
          CareLogType? type;
          if (typeStr == 'feeding') type = CareLogType.feeding;
          else if (typeStr == 'diaper') type = CareLogType.diaper;
          else if (typeStr == 'sleep') type = CareLogType.sleep;
          
          if (type != null) {
            careLogs.add(CareLogEntry(
              timestamp: DateTime.parse(item['timestamp']),
              type: type,
              note: item['note'],
              amount: item['amount'],
            ));
          }
        }
      } catch (_) {}
    }
    
    TempAlertStatus tempAlert = TempAlertStatus.ok;
    if (tempAlertStr != null) {
      if (tempAlertStr.contains('low')) {
        tempAlert = TempAlertStatus.low;
      } else if (tempAlertStr.contains('high')) {
        tempAlert = TempAlertStatus.high;
      }
    }
    
    return {
      'temperature': temperature,
      'tempAlert': tempAlert,
      'crying': crying ?? false,
      'deviceName': deviceName ?? 'Unknown Device',
      'lastConnected': lastConnected,
      'tempHistory': tempHistory,
      'cryEvents': cryEvents,
      'careLogs': careLogs,
    };
  }

  /// Clear all saved state
  Future<void> clearState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyLastTemperature);
    await prefs.remove(_keyLastTempAlert);
    await prefs.remove(_keyLastCryState);
    await prefs.remove(_keyLastConnected);
    await prefs.remove(_keyDeviceName);
    await prefs.remove(_keyTempHistory);
    await prefs.remove(_keyCryEvents);
    await prefs.remove(_keyCareLogs);
  }
}
