import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/notification_service.dart';
import '../services/readings_repository.dart';
import '../theme.dart';

enum ConnectionStatus { connected, reconnecting, disconnected }

enum TempAlertStatus { ok, low, high }

enum AlertSound { softChime, standard, loud }

class MonitorEvent {
  MonitorEvent(this.timestamp, this.message);

  final DateTime timestamp;
  final String message;

  String get formattedTime {
    final hours = timestamp.hour.toString().padLeft(2, '0');
    final minutes = timestamp.minute.toString().padLeft(2, '0');
    return '$hours:$minutes';
  }
}

/// Lightweight sample for recent temperature readings.
class TempSample {
  TempSample(this.timestamp, this.temperature);

  final DateTime timestamp;
  final double temperature;
}

class CryEvent {
  CryEvent({required this.start, this.end});

  final DateTime start;
  DateTime? end;

  Duration? get duration => end?.difference(start);
}

enum CareLogType { feeding, diaper, sleep }

class CareLogEntry {
  CareLogEntry({required this.timestamp, required this.type, this.note, this.amount});

  final DateTime timestamp;
  final CareLogType type;
  final String? note;
  final String? amount; // e.g., '90 ml' or duration
}



class BabyMonitorState extends ChangeNotifier {
  BabyMonitorState() {
    _addEvent('App opened');
    _muteTicker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _advanceMuteTimer(),
    );

    Future.microtask(() async {
      await NotificationService().initialize();
      await _loadLastState();
      await _initBle();
    });
    
    // Save state periodically when connected
    _stateSaveTicker = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _saveCurrentState(),
    );
  }

  final ReadingsRepository _repository = ReadingsRepository();

  static const String _deviceName = 'baby_monitor';
  static const Set<String> _fallbackDeviceNames = {
    'baby_monitor',
    'smartbabymonitor',
  };
  static final Guid _serviceUuid = Guid('12345678-9abc-4def-8000-00000000babe');
  static final Guid _statusCharacteristicUuid =
      Guid('12345678-9abc-4def-8000-00000000feed');
  static final Guid _configCharacteristicUuid =
      Guid('12345678-9abc-4def-8000-00000000c0ff');

  final List<MonitorEvent> _events = <MonitorEvent>[];
  List<MonitorEvent> get events => List.unmodifiable(_events);

  
  // Theme
  ThemeType _themeType = ThemeType.beige;
  ThemeType get themeType => _themeType;

  // Connection state
  ConnectionStatus _connectionStatus = ConnectionStatus.disconnected;
  ConnectionStatus get connectionStatus => _connectionStatus;

  BluetoothDevice? _device;
  BluetoothCharacteristic? _statusChar;
  BluetoothCharacteristic? _configChar;
  StreamSubscription<BluetoothAdapterState>? _adapterStateSub;
  StreamSubscription<List<ScanResult>>? _scanResultsSub;
  StreamSubscription<BluetoothConnectionState>? _connectionSub;
  StreamSubscription<List<int>>? _statusDataSub;
  StreamSubscription<bool>? _scanStateSub;
  Timer? _muteTicker;
  Timer? _reconnectTimer;
  Timer? _dataTimeoutTimer;
  Timer? _periodicCheckTimer;
  Timer? _stateSaveTicker;
  StringBuffer? _pendingStatusPayload;
  DateTime? _lastNotificationTime;
  DateTime? _lastChunkTime;

  bool _isScanning = false;
  bool _isConnecting = false;
  bool _suppressScanCompleteEvent = false;
  Duration _reconnectDelay = const Duration(seconds: 2);

  static const Duration _minReconnectDelay = Duration(seconds: 2);
  static const Duration _maxReconnectDelay = Duration(seconds: 30);

  // Data fields
  double? _temperature;
  double? get temperature =>
      _connectionStatus == ConnectionStatus.connected ? _temperature : null;

  // Recent temperature history (in-memory, bounded).
  final List<TempSample> _tempHistory = <TempSample>[];
  List<TempSample> get tempHistory => List.unmodifiable(_tempHistory);
  static const int _maxTempHistory = 2880; // cap samples (approx 24h @ 30s samples)

  // Offline state
  DateTime? _lastConnectedTime;
  DateTime? get lastConnectedTime => _lastConnectedTime;
  String? _lastDeviceName;
  String? get lastDeviceName => _lastDeviceName;

  // Cry events history
  final List<CryEvent> _cryEvents = <CryEvent>[];
  List<CryEvent> get cryEvents => List.unmodifiable(_cryEvents);
  static const int _maxCryEvents = 200;

  // Care logs (in-memory)
  final List<CareLogEntry> _careLogs = <CareLogEntry>[];
  List<CareLogEntry> get careLogs => List.unmodifiable(_careLogs);
  static const int _maxCareLogs = 500;

  TempAlertStatus _tempAlert = TempAlertStatus.ok;
  TempAlertStatus get tempAlert => _tempAlert;

  double _comfortMin = 22.0;
  double _comfortMax = 26.0;
  double get comfortMin => _comfortMin;
  double get comfortMax => _comfortMax;

  bool _fanRunning = false;
  bool get fanRunning => _fanRunning && _connectionStatus == ConnectionStatus.connected;

  bool _fanManualOverride = false;
  bool get fanManualOverride => _fanManualOverride;

  bool _crying = false;
  bool get crying => _crying && _connectionStatus == ConnectionStatus.connected;

  DateTime? _cryStartedAt;
  DateTime? _cryLastEndedAt;

  bool get recentlyCrying {
    if (_cryLastEndedAt == null) return false;
    return DateTime.now().difference(_cryLastEndedAt!) <
        const Duration(minutes: 5);
  }

  Duration? get timeSinceLastCry {
    if (_crying && _cryStartedAt != null) {
      return DateTime.now().difference(_cryStartedAt!);
    }
    if (_cryLastEndedAt != null) {
      return DateTime.now().difference(_cryLastEndedAt!);
    }
    return null;
  }

  // Alerts and mute
  bool cryAlertsEnabled = true;
  bool temperatureAlertsEnabled = true;
  AlertSound alertSound = AlertSound.standard;

  DateTime? _mutedUntil;
  DateTime? get mutedUntil => _mutedUntil;

  bool get isMuted {
    if (_mutedUntil == null) return false;
    return DateTime.now().isBefore(_mutedUntil!);
  }

  Duration? get muteRemaining {
    if (!isMuted) return null;
    return _mutedUntil!.difference(DateTime.now());
  }

  // Theme controls
  void setTheme(ThemeType type) {
    if (_themeType == type) return;
    _themeType = type;
    _addEvent('Theme changed to ${type.label}');
  }

  /// Load last saved state from repository
  Future<void> _loadLastState() async {
    try {
      final lastState = await _repository.getLastState();
      if (lastState != null) {
        _lastConnectedTime = lastState['lastConnected'] as DateTime?;
        _lastDeviceName = lastState['deviceName'] as String?;
        
        // Load historical data
        final tempHistory = lastState['tempHistory'] as List<TempSample>?;
        if (tempHistory != null) {
          _tempHistory.addAll(tempHistory);
        }
        
        final cryEvents = lastState['cryEvents'] as List<CryEvent>?;
        if (cryEvents != null) {
          _cryEvents.addAll(cryEvents);
        }
        
        final careLogs = lastState['careLogs'] as List<CareLogEntry>?;
        if (careLogs != null) {
          _careLogs.addAll(careLogs);
        }
        
        notifyListeners();
      }
    } catch (e) {
      log('Failed to load last state: $e', name: 'MonitorState');
    }
  }

  /// Save current state to repository
  Future<void> _saveCurrentState() async {
    if (_connectionStatus == ConnectionStatus.connected) {
      try {
        await _repository.saveCurrentState(
          temperature: _temperature,
          tempAlert: _tempAlert,
          crying: _crying,
          deviceName: _device?.platformName ?? _deviceName,
          tempHistory: _tempHistory,
          cryEvents: _cryEvents,
          careLogs: _careLogs,
        );
        _lastConnectedTime = DateTime.now();
        _lastDeviceName = _device?.platformName ?? _deviceName;
      } catch (e) {
        log('Failed to save current state: $e', name: 'MonitorState');
      }
    }
  }

  String get connectionLabel {
    switch (_connectionStatus) {
      case ConnectionStatus.connected:
        final String? platformName = _device?.platformName;
        final String name =
            (platformName != null && platformName.isNotEmpty)
                ? platformName
                : _deviceName;
        return 'Connected to $name';
      case ConnectionStatus.reconnecting:
        return 'Reconnecting…';
      case ConnectionStatus.disconnected:
        return 'Not connected';
    }
  }

  void requestReconnect() {
    _addEvent('Manual reconnect requested');
    _resetReconnectBackoff();
    _restartConnection();
  }

  void toggleMute(Duration duration) {
    if (isMuted) {
      _mutedUntil = null;
      _addEvent('Alerts unmuted');
    } else {
      _mutedUntil = DateTime.now().add(duration);
      final minutes = duration.inMinutes;
      final display = minutes >= 1 ? '$minutes min' : '${duration.inSeconds} s';
      _addEvent('Alerts muted for $display');
    }
  }

  void setMuteWindow(Duration? duration) {
    if (duration == null) {
      _mutedUntil = null;
      _addEvent('Mute cancelled');
    } else {
      _mutedUntil = DateTime.now().add(duration);
      _addEvent('Alerts muted for ${_formatDuration(duration)}');
    }
  }

  void toggleCryAlerts(bool value) {
    if (cryAlertsEnabled == value) return;
    cryAlertsEnabled = value;
    _addEvent('Cry alerts ${value ? 'enabled' : 'disabled'}');
  }

  void toggleTemperatureAlerts(bool value) {
    if (temperatureAlertsEnabled == value) return;
    temperatureAlertsEnabled = value;
    _addEvent('Temperature alerts ${value ? 'enabled' : 'disabled'}');
  }

  void setAlertSound(AlertSound sound) {
    if (alertSound == sound) return;
    alertSound = sound;
    _addEvent('Alert sound set to ${_alertSoundLabel(sound)}');
  }

  void setComfortTemperature(double min, double max) {
    if (_comfortMin == min && _comfortMax == max) return;
    _comfortMin = min;
    _comfortMax = max;
    _addEvent('Comfort range: ${min.toStringAsFixed(1)}°C - ${max.toStringAsFixed(1)}°C');
    notifyListeners();
    
    // Send to ESP32 if connected
    _sendTemperatureConfig();
  }

  void setFanOverride(bool override) {
    if (_fanManualOverride == override) return;
    _fanManualOverride = override;
    _addEvent(override ? 'Fan manually disabled' : 'Fan set to automatic');
    notifyListeners();
    
    // Send to ESP32 if connected
    _sendFanOverrideConfig();
  }

  Future<void> _sendFanOverrideConfig() async {
    if (_configChar == null || _connectionStatus != ConnectionStatus.connected) {
      return;
    }
    
    try {
      final config = json.encode({
        'fan_override': _fanManualOverride,
      });
      await _configChar!.write(utf8.encode(config), withoutResponse: false);
      log('Sent fan override config to ESP32: $config', name: 'MonitorState');
    } catch (e) {
      log('Failed to send fan override config: $e', name: 'MonitorState');
    }
  }

  Future<void> _sendTemperatureConfig() async {
    if (_configChar == null || _connectionStatus != ConnectionStatus.connected) {
      return;
    }
    
    try {
      final config = json.encode({
        'temp_low': _comfortMin,
        'temp_high': _comfortMax,
      });
      await _configChar!.write(utf8.encode(config), withoutResponse: false);
      log('Sent temperature config to ESP32: $config', name: 'MonitorState');
    } catch (e) {
      log('Failed to send temperature config: $e', name: 'MonitorState');
    }
  }

  Future<void> _initBle() async {
    if (Platform.isAndroid) {
      final permissions = <Permission>[
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
      ];

      final statuses = await permissions.request();
      bool anyDenied = false;
      for (final Permission permission in permissions) {
        final PermissionStatus? permissionStatus = statuses[permission];
        if (permissionStatus == null ||
            permissionStatus.isDenied ||
            permissionStatus.isPermanentlyDenied) {
          anyDenied = true;
        }
      }
      if (anyDenied) {
        _addEvent(
          'Bluetooth permission denied. Scanning may not work until granted.',
        );
      }
    } else {
      final status = await Permission.location.request();
      if (status != PermissionStatus.granted) {
        _addEvent('Location permission denied. BLE scan may not work.');
      }
    }

    _adapterStateSub = FlutterBluePlus.adapterState.listen((state) {
      if (state == BluetoothAdapterState.on) {
        if (_connectionStatus != ConnectionStatus.connected && !_isScanning) {
          _startScan();
        }
      } else {
        _handleAdapterDisabled(state);
      }
    });

    _scanResultsSub ??= FlutterBluePlus.scanResults.listen(
      _handleScanResults,
      onError: (Object error, StackTrace stackTrace) {
        _addEvent('Scan error: $error');
        _isScanning = false;
        _setConnectionStatus(ConnectionStatus.disconnected);
      },
    );

    _scanStateSub ??= FlutterBluePlus.isScanning.listen((bool scanning) {
      final bool wasScanning = _isScanning;
      _isScanning = scanning;

      if (!scanning && wasScanning && !_isConnecting) {
        if (_suppressScanCompleteEvent) {
          _suppressScanCompleteEvent = false;
          return;
        }

        if (_connectionStatus != ConnectionStatus.connected) {
          _setConnectionStatus(ConnectionStatus.disconnected);
          if (_device == null) {
            _addEvent('Scan completed. Device not found.');
          }
          _scheduleReconnectAttempt();
        }
      }
    });

    final BluetoothAdapterState adapterState =
        await FlutterBluePlus.adapterState.first;
    if (adapterState == BluetoothAdapterState.on) {
      _startScan();
    } else {
      _addEvent('Bluetooth is ${adapterState.name}. Turn it on to connect.');
      _setConnectionStatus(ConnectionStatus.disconnected);
    }
  }

  void _handleAdapterDisabled(BluetoothAdapterState state) {
    _setConnectionStatus(ConnectionStatus.disconnected);
    _addEvent('Bluetooth adapter ${state.name}.');
    _disposeCurrentConnection();
    _isScanning = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  Future<void> _restartConnection() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _disposeCurrentConnection();
    if (await FlutterBluePlus.adapterState.first == BluetoothAdapterState.on) {
      _startScan();
    }
  }

  Future<void> _startScan() async {
    if (_isScanning || _isConnecting) return;
    _setConnectionStatus(ConnectionStatus.reconnecting);
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    try {
      _isScanning = true;
      await FlutterBluePlus.startScan(
        withServices: [_serviceUuid],
        timeout: const Duration(seconds: 12),
      );
    } on Exception catch (error) {
      _isScanning = false;
      _suppressScanCompleteEvent = false;
      _addEvent('Scan failed: ${error.runtimeType}: $error');
      _setConnectionStatus(ConnectionStatus.disconnected);
      _scheduleReconnectAttempt();
    }
  }

  void _handleScanResults(List<ScanResult> results) {
    if (_isConnecting || _connectionStatus == ConnectionStatus.connected) {
      return;
    }

    final String serviceTarget = _serviceUuid.toString().toLowerCase();

  for (final ScanResult result in results) {
    final String advName = result.advertisementData.advName;
    final String platformName = result.device.platformName;
    final String name = advName.isNotEmpty
      ? advName
      : platformName.isNotEmpty
        ? platformName
        : '';

      final String normalizedName = name.trim().toLowerCase();
      final bool matchesName =
          normalizedName.isNotEmpty && _fallbackDeviceNames.contains(normalizedName);
      final bool matchesService = result.advertisementData.serviceUuids
          .map((Guid uuid) => uuid.toString().toLowerCase())
          .contains(serviceTarget);

      if (matchesName || matchesService) {
        unawaited(_connectToDevice(result.device));
        break;
      }
    }
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    if (_isConnecting) return;
    _isConnecting = true;
    if (_isScanning) {
      _suppressScanCompleteEvent = true;
    }
    await FlutterBluePlus.stopScan();
    _isScanning = false;

    _device = device;
    _addEvent(
        'Connecting to ${device.platformName.isEmpty ? _deviceName : device.platformName}');

    _connectionSub?.cancel();
    _connectionSub = device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.connected) {
        _setConnectionStatus(ConnectionStatus.connected);
      } else if (state == BluetoothConnectionState.disconnected) {
        _handleDeviceDisconnection();
      }
    });

    try {
      await device.connect(
        timeout: const Duration(seconds: 10),
        mtu: null, // Disable MTU negotiation - causes ESP32 to disconnect
      );
    } on FlutterBluePlusException catch (error) {
      _addEvent(
        'Connection failed [${error.description}] (code ${error.code})',
      );
      _device = null;
      _isConnecting = false;
      _setConnectionStatus(ConnectionStatus.disconnected);
      _scheduleReconnectAttempt();
      return;
    } on Exception catch (error) {
      _addEvent('Connection failed: ${error.runtimeType}: $error');
      _device = null;
      _isConnecting = false;
      _setConnectionStatus(ConnectionStatus.disconnected);
      _scheduleReconnectAttempt();
      return;
    }

    // Skip MTU request - causes disconnection issues with ESP32
    // The ESP32 BLE library appears to disconnect when MTU is negotiated

    _isConnecting = false;
    
    // Keep a local reference to the device in case _device gets cleared
    final BluetoothDevice connectedDevice = device;
    
    // Add delay after connection to let ESP32 stabilize
    debugPrint('BLE: Waiting 1 second for ESP32 to stabilize...');
    await Future.delayed(const Duration(milliseconds: 1000));
    
    // Try to request MTU after stabilization
    if (Platform.isAndroid) {
      try {
        debugPrint('BLE: Requesting MTU 185...');
        final mtu = await connectedDevice.requestMtu(185);
        debugPrint('BLE: MTU negotiated: $mtu');
      } catch (e) {
        debugPrint('BLE: MTU request failed (continuing anyway): $e');
      }
    }
    
    // Check if still connected before proceeding
    final connectionState = await connectedDevice.connectionState.first;
    debugPrint('BLE: Connection state after delay: $connectionState');
    
    if (connectionState != BluetoothConnectionState.connected) {
      debugPrint('BLE: Device disconnected during stabilization delay');
      _addEvent('Device disconnected before service discovery');
      return;
    }
    
    debugPrint('BLE: Starting service discovery...');
    await _discoverStatusCharacteristic(connectedDevice);
  }

  Future<void> _discoverStatusCharacteristic([BluetoothDevice? deviceParam]) async {
    debugPrint('BLE: _discoverStatusCharacteristic called');
    final BluetoothDevice? device = deviceParam ?? _device;
    if (device == null) {
      debugPrint('BLE: Device is null, cannot discover services');
      return;
    }

    debugPrint('BLE: Starting service discovery on device: ${device.platformName}...');
    List<BluetoothService> services;
    try {
      services = await device.discoverServices();
      debugPrint('BLE: Discovered ${services.length} services');
    } on Exception catch (error) {
      _addEvent('Service discovery failed: $error');
      debugPrint('BLE: Service discovery failed: $error');
      return;
    }

    BluetoothService? targetService;
    for (final BluetoothService service in services) {
      debugPrint('BLE: Found service: ${service.uuid}');
      if (service.uuid == _serviceUuid) {
        targetService = service;
        break;
      }
    }

    if (targetService == null) {
      _addEvent('SmartBaby service not found on device.');
      debugPrint('BLE: Target service $_serviceUuid not found');
      return;
    }

    debugPrint('BLE: Found target service, looking for characteristics...');
    BluetoothCharacteristic? statusChar;
    BluetoothCharacteristic? configChar;
    for (final BluetoothCharacteristic characteristic
        in targetService.characteristics) {
      debugPrint('BLE: Found characteristic: ${characteristic.uuid}');
      if (characteristic.uuid == _statusCharacteristicUuid) {
        statusChar = characteristic;
      } else if (characteristic.uuid == _configCharacteristicUuid) {
        configChar = characteristic;
      }
    }

    if (statusChar == null) {
      _addEvent('SmartBaby status characteristic missing.');
      debugPrint('BLE: Status characteristic not found');
      return;
    }

    _statusChar = statusChar;
    _configChar = configChar; // May be null on older firmware
    debugPrint('BLE: Found status characteristic, setting up...');

    _statusDataSub?.cancel();
    _statusDataSub = statusChar.onValueReceived.listen(
      (value) => _handleStatusData(value, fromNotification: true),
      onError: (Object error, StackTrace stackTrace) {
        _addEvent('Data stream error: $error');
      },
    );
    debugPrint('BLE: Set up notification listener for characteristic');

    try {
      await statusChar.setNotifyValue(true);
      debugPrint('BLE: Enabled notifications for characteristic');
    } on Exception catch (error) {
      _addEvent('Failed to enable notifications: $error');
    }

    try {
      final List<int> initialValue = await statusChar.read();
      debugPrint('BLE: Initial read result: ${initialValue.length} bytes');
      if (initialValue.isNotEmpty) {
        _handleStatusData(initialValue, fromNotification: false);
      }
    } on Exception catch (error) {
      _addEvent('Initial read failed: $error');
      debugPrint('BLE: Initial read failed: $error');
    }

    _dataTimeoutTimer = Timer(const Duration(seconds: 5), () {
      if (_temperature == null) {
        _addEvent('No data received from device within timeout, disconnecting');
        _handleDeviceDisconnection();
      }
    });

    // Read current temperature config from ESP32 if available
    if (_configChar != null) {
      try {
        final List<int> configValue = await _configChar!.read();
        if (configValue.isNotEmpty) {
          final configJson = utf8.decode(configValue);
          final config = json.decode(configJson) as Map<String, dynamic>;
          final double? tempLow = (config['temp_low'] as num?)?.toDouble();
          final double? tempHigh = (config['temp_high'] as num?)?.toDouble();
          if (tempLow != null && tempHigh != null) {
            _comfortMin = tempLow;
            _comfortMax = tempHigh;
            debugPrint('BLE: Read temperature config from ESP32: low=$tempLow, high=$tempHigh');
            notifyListeners();
          }
        }
      } catch (e) {
        debugPrint('BLE: Failed to read config characteristic: $e');
      }
    }
  }

  void _handleStatusData(List<int> raw, {bool fromNotification = false}) {
    _dataTimeoutTimer?.cancel();
    
    // Track when we receive notifications
    if (fromNotification) {
      _lastNotificationTime = DateTime.now();
    }
    
    // Only process BLE data if device is connected
    if (_connectionStatus != ConnectionStatus.connected) {
      return;
    }
    
    if (raw.isEmpty) {
      return;
    }

    String chunk;
    try {
      chunk = utf8.decode(raw, allowMalformed: true);
    } on FormatException catch (error) {
      debugPrint('BLE: Failed to decode payload chunk: $error');
      return;
    }

    if (chunk.trim().isEmpty) {
      return;
    }

    log('BLE: Received data chunk (${raw.length} bytes): $chunk', name: 'MonitorState');

    // Clear stale incomplete chunks after 500ms
    final now = DateTime.now();
    if (_lastChunkTime != null && 
        now.difference(_lastChunkTime!) > const Duration(milliseconds: 500)) {
      log('BLE: Clearing stale chunk buffer', name: 'MonitorState');
      _pendingStatusPayload = null;
    }
    _lastChunkTime = now;

    (_pendingStatusPayload ??= StringBuffer()).write(chunk);
    final String accumulated = _pendingStatusPayload!.toString();
    final String trimmed = accumulated.trimRight();
    
    log('BLE: Accumulated buffer (${trimmed.length} chars): $trimmed', name: 'MonitorState');

    // Wait for full JSON object (our payloads always end with '}')
    if (!trimmed.endsWith('}')) {
      log('BLE: Waiting for more chunks (current: ${trimmed.length} chars)', name: 'MonitorState');
      return;
    }

    dynamic decoded;
    try {
      decoded = json.decode(trimmed);
    } on FormatException catch (error) {
      _pendingStatusPayload = null;
      _addEvent('Received malformed monitor data.');
      log('BLE: Malformed payload ($error): $trimmed', name: 'MonitorState');
      return;
    } on Exception catch (error) {
      _pendingStatusPayload = null;
      _addEvent('Error parsing data: $error');
      log('BLE: Error parsing payload: $error', name: 'MonitorState');
      return;
    }

    _pendingStatusPayload = null;

    if (decoded is! Map<String, dynamic>) {
      log('BLE: Unexpected payload type: ${decoded.runtimeType}', name: 'MonitorState');
      return;
    }

    _applyStatusUpdate(Map<String, dynamic>.from(decoded));
  }

  void _applyStatusUpdate(Map<String, dynamic> data) {
    log('_applyStatusUpdate called with data: $data', name: 'MonitorState');
    final num? tempValue = data['temp_c'] as num?;
    bool temperatureChanged = false;
    if (tempValue != null) {
      final double nextTemp =
          double.parse(tempValue.toDouble().toStringAsFixed(1));
      log('Comparing temps - current: $_temperature, next: $nextTemp', name: 'MonitorState');
      if (_temperature == null || (_temperature! - nextTemp).abs() >= 0.05) {
        _temperature = nextTemp;
        temperatureChanged = true;
        log('BLE: Temperature updated $_temperature °C (changed: $temperatureChanged)', name: 'MonitorState');
        // Append to temp history (bounded). Avoid overly frequent duplicates.
        try {
          final now = DateTime.now();
          if (_tempHistory.isEmpty ||
              now.difference(_tempHistory.last.timestamp) >= const Duration(seconds: 30) ||
              (_tempHistory.last.temperature - nextTemp).abs() >= 0.05) {
            _tempHistory.add(TempSample(now, nextTemp));
            if (_tempHistory.length > _maxTempHistory) {
              _tempHistory.removeRange(0, _tempHistory.length - _maxTempHistory);
            }
          }
        } catch (_) {
          // Ignore history errors to avoid disrupting state updates.
        }
      } else {
        log('BLE: Temperature unchanged (diff: ${(_temperature! - nextTemp).abs()})', name: 'MonitorState');
      }
    }

    final String? tempAlertValue = data['temp_alert'] as String?;
    if (tempAlertValue != null) {
      final TempAlertStatus nextAlert =
          _mapTempAlert(tempAlertValue) ?? _tempAlert;
      if (nextAlert != _tempAlert) {
        _tempAlert = nextAlert;
        switch (nextAlert) {
          case TempAlertStatus.ok:
            _addEvent('Temperature back in range');
            // Clear temperature alert notification
            unawaited(NotificationService().clearTemperatureAlert());
            break;
          case TempAlertStatus.low:
            _addEvent(
              'Temperature low ${_temperature?.toStringAsFixed(1) ?? '--'} °C',
            );
            // Show notification if alerts enabled
            if (temperatureAlertsEnabled && _temperature != null) {
              unawaited(NotificationService().showTemperatureAlert(
                status: 'low',
                temperature: _temperature!,
                isMuted: isMuted,
              ));
            }
            break;
          case TempAlertStatus.high:
            _addEvent(
              'Temperature high ${_temperature?.toStringAsFixed(1) ?? '--'} °C',
            );
            // Show notification if alerts enabled
            if (temperatureAlertsEnabled && _temperature != null) {
              unawaited(NotificationService().showTemperatureAlert(
                status: 'high',
                temperature: _temperature!,
                isMuted: isMuted,
              ));
            }
            break;
        }
      } else if (temperatureChanged && nextAlert != TempAlertStatus.ok && 
                 temperatureAlertsEnabled && _temperature != null) {
        // Update notification with new temperature while still in alert state
        final status = nextAlert == TempAlertStatus.low ? 'low' : 'high';
        unawaited(NotificationService().showTemperatureAlert(
          status: status,
          temperature: _temperature!,
          isMuted: isMuted,
        ));
      }
      if (tempAlertValue.toLowerCase() == 'na') {
        _temperature = null;
        _tempAlert = TempAlertStatus.ok;
        unawaited(NotificationService().clearTemperatureAlert());
      }
    }

    final dynamic cryValue = data['cry'];
    final bool nextCrying = cryValue == true || cryValue == "true";
    final int? cryAgeMs = (data['cry_age_ms'] as num?)?.toInt();
    final DateTime now = DateTime.now();

    // Handle fan state
    final dynamic fanValue = data['fan'];
    final bool nextFanRunning = fanValue == true || fanValue == "true";
    log('BLE: Fan state - received: $fanValue, parsed: $nextFanRunning, current: $_fanRunning', name: 'MonitorState');
    if (nextFanRunning != _fanRunning) {
      _fanRunning = nextFanRunning;
      _addEvent(nextFanRunning ? 'Fan turned on' : 'Fan turned off');
      log('BLE: Fan state CHANGED to $_fanRunning', name: 'MonitorState');
    }
    
    // Handle fan override state
    final dynamic fanOverrideValue = data['fan_override'];
    final bool nextFanOverride = fanOverrideValue == true || fanOverrideValue == "true";
    if (nextFanOverride != _fanManualOverride) {
      _fanManualOverride = nextFanOverride;
      log('BLE: Fan override state updated to $_fanManualOverride', name: 'MonitorState');
    }

    if (nextCrying != _crying) {
      if (nextCrying) {
        _cryStartedAt = cryAgeMs != null
            ? now.subtract(Duration(milliseconds: cryAgeMs))
            : now;
        // Record structured cry event (start)
        try {
          final ev = CryEvent(start: _cryStartedAt!);
          _cryEvents.insert(0, ev);
          if (_cryEvents.length > _maxCryEvents) {
            _cryEvents.removeRange(_maxCryEvents, _cryEvents.length);
          }
        } catch (_) {}
        _addEvent('Cry detected');
        log('CRY DETECTED - Attempting to show notification. cryAlertsEnabled=$cryAlertsEnabled, isMuted=$isMuted', 
            name: 'MonitorState');
        // Show cry notification if alerts enabled
        if (cryAlertsEnabled) {
          final duration = now.difference(_cryStartedAt!);
          log('Calling NotificationService.showCryAlert with duration: $duration', name: 'MonitorState');
          unawaited(NotificationService().showCryAlert(
            duration: duration,
            isMuted: isMuted,
          ));
        } else {
          log('Cry alerts are DISABLED - notification not shown', name: 'MonitorState');
        }
      } else {
        _cryLastEndedAt = cryAgeMs != null
            ? now.subtract(Duration(milliseconds: cryAgeMs))
            : now;
        // Close the latest cry event if present
        try {
          if (_cryEvents.isNotEmpty && _cryEvents.first.end == null) {
            _cryEvents.first.end = _cryLastEndedAt;
          } else {
            // No open event found — insert completed event
            _cryEvents.insert(0, CryEvent(start: _cryLastEndedAt!, end: _cryLastEndedAt));
            if (_cryEvents.length > _maxCryEvents) {
              _cryEvents.removeRange(_maxCryEvents, _cryEvents.length);
            }
          }
        } catch (_) {}
        _addEvent('Cry cleared');
        // Clear cry notification
        unawaited(NotificationService().clearCryAlert());
      }
      _crying = nextCrying;
    } else {
      if (nextCrying && cryAgeMs != null) {
        _cryStartedAt = now.subtract(Duration(milliseconds: cryAgeMs));
        // Adjust last open cry event start time if we have recorded one
        try {
          if (_cryEvents.isNotEmpty && _cryEvents.first.end == null) {
            final existing = _cryEvents.first;
            _cryEvents[0] = CryEvent(start: _cryStartedAt!, end: existing.end);
          }
        } catch (_) {}
        // Update ongoing cry notification with duration
        if (cryAlertsEnabled) {
          final duration = now.difference(_cryStartedAt!);
          log('Updating ongoing cry notification with duration: $duration', name: 'MonitorState');
          unawaited(NotificationService().showCryAlert(
            duration: duration,
            isMuted: isMuted,
          ));
        }
      } else if (!nextCrying && cryAgeMs != null) {
        _cryLastEndedAt = now.subtract(Duration(milliseconds: cryAgeMs));
      }
    }

    notifyListeners();
    log('notifyListeners() called - temp: $_temperature, alert: $_tempAlert, crying: $_crying', name: 'MonitorState');
  }

  void _handleDeviceDisconnection() {
    _dataTimeoutTimer?.cancel();
    _periodicCheckTimer?.cancel();
    _periodicCheckTimer = null;
    _statusDataSub?.cancel();
    _statusDataSub = null;
    _statusChar = null;
    _configChar = null;
    _pendingStatusPayload = null;
    _device = null;
    if (_connectionStatus != ConnectionStatus.disconnected) {
      _setConnectionStatus(ConnectionStatus.disconnected);
    }
    _scheduleReconnectAttempt();
  }

  void _scheduleReconnectAttempt() {
    if (_reconnectTimer?.isActive ?? false) {
      return;
    }
    final Duration delay = _reconnectDelay;
    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      if (_connectionStatus == ConnectionStatus.connected ||
          _isScanning ||
          _isConnecting) {
        return;
      }
      unawaited(_startScan());
    });

    final int nextMs = (_reconnectDelay.inMilliseconds * 2).clamp(
      _minReconnectDelay.inMilliseconds,
      _maxReconnectDelay.inMilliseconds,
    );
    _reconnectDelay = Duration(milliseconds: nextMs);
  }

  void _resetReconnectBackoff() {
    _reconnectDelay = _minReconnectDelay;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  void _periodicCheck() async {
    if (_statusChar == null || _connectionStatus != ConnectionStatus.connected) {
      return;
    }
    
    // Skip periodic read if we received a notification in the last 2 seconds
    if (_lastNotificationTime != null) {
      final timeSinceNotification = DateTime.now().difference(_lastNotificationTime!);
      if (timeSinceNotification < const Duration(seconds: 2)) {
        return;
      }
    }
    
    try {
      // Clear any pending data before reading to avoid mixing notification and read data
      _pendingStatusPayload = null;
      final List<int> data = await _statusChar!.read();
      log('BLE: Periodic read returned ${data.length} bytes', name: 'MonitorState');
      if (data.isNotEmpty) {
        _handleStatusData(data, fromNotification: false);
      }
    } catch (e) {
      log('BLE: Periodic read error: $e', name: 'MonitorState');
      // Ignore read errors during periodic check
    }
  }

  TempAlertStatus? _mapTempAlert(String value) {
    switch (value.toLowerCase()) {
      case 'ok':
        return TempAlertStatus.ok;
      case 'low':
        return TempAlertStatus.low;
      case 'high':
        return TempAlertStatus.high;
    }
    return null;
  }

  void _advanceMuteTimer() {
    if (_mutedUntil == null) {
      return;
    }
    if (DateTime.now().isAfter(_mutedUntil!)) {
      _mutedUntil = null;
      _addEvent('Mute ended');
    } else {
      notifyListeners();
    }
  }

  Future<void> _disposeCurrentConnection() async {
    _dataTimeoutTimer?.cancel();
    _periodicCheckTimer?.cancel();
    _periodicCheckTimer = null;
    _statusDataSub?.cancel();
    _statusDataSub = null;
    _statusChar = null;
    _configChar = null;
    _pendingStatusPayload = null;
    _connectionSub?.cancel();
    _connectionSub = null;
    final BluetoothDevice? device = _device;
    _device = null;
    if (device != null) {
      try {
        await device.disconnect();
      } catch (_) {
        // Ignore disconnect errors during cleanup.
      }
    }
  }

  void _setConnectionStatus(ConnectionStatus status) {
    if (_connectionStatus == status) return;
    final ConnectionStatus previous = _connectionStatus;
    _connectionStatus = status;
    if (status != ConnectionStatus.connected) {
      // Don't immediately clear crying/fan state - keep last known state
      // They will be cleared after reconnecting or after a longer period
      _periodicCheckTimer?.cancel();
      _periodicCheckTimer = null;
      // Clear all notifications when disconnected
      unawaited(NotificationService().clearCryAlert());
      unawaited(NotificationService().clearTemperatureAlert());
    } else {
      // Start periodic check when connected
      _periodicCheckTimer?.cancel();
      _periodicCheckTimer = Timer.periodic(const Duration(seconds: 1), (_) => _periodicCheck());
    }
    switch (status) {
      case ConnectionStatus.connected:
        debugPrint('BLE: Connection status changed to CONNECTED');
        _resetReconnectBackoff();
        _addEvent(
          previous == ConnectionStatus.disconnected
              ? 'Device connected'
              : 'Connection restored',
        );
        // Save state when connected
        unawaited(_saveCurrentState());
        // Show connection notification only if previously disconnected
        if (previous == ConnectionStatus.disconnected) {
          unawaited(NotificationService().showConnectionAlert(isConnected: true));
        }
        break;
      case ConnectionStatus.reconnecting:
        _addEvent('Scanning for $_deviceName…');
        break;
      case ConnectionStatus.disconnected:
        _addEvent(
          previous == ConnectionStatus.connected
              ? 'Connection lost'
              : 'Not connected',
        );
        // Show disconnection notification only if previously connected
        if (previous == ConnectionStatus.connected) {
          unawaited(NotificationService().showConnectionAlert(isConnected: false));
        }
        break;
    }
  }

  void _addEvent(String message) {
    _events.insert(0, MonitorEvent(DateTime.now(), message));
    if (_events.length > 30) {
      _events.removeLast();
    }
    notifyListeners();
  }

  /// Add a care log entry (feeding, diaper, sleep). Stored in-memory.
  void addCareLog({required CareLogType type, String? amount, String? note}) {
    try {
      final entry = CareLogEntry(timestamp: DateTime.now(), type: type, note: note, amount: amount);
      _careLogs.insert(0, entry);
      if (_careLogs.length > _maxCareLogs) {
        _careLogs.removeRange(_maxCareLogs, _careLogs.length);
      }
      _addEvent('Log added: ${type.name}');
    } catch (_) {}
  }

  String _formatDuration(Duration duration) {
    if (duration.inMinutes >= 1) {
      final minutes = duration.inMinutes;
      return '$minutes min';
    }
    final seconds = duration.inSeconds;
    return '$seconds s';
  }

  String _alertSoundLabel(AlertSound sound) {
    switch (sound) {
      case AlertSound.softChime:
        return 'Soft chime';
      case AlertSound.standard:
        return 'Standard';
      case AlertSound.loud:
        return 'Loud';
    }
  }

  @override
  void dispose() {
    _dataTimeoutTimer?.cancel();
    _periodicCheckTimer?.cancel();
    _muteTicker?.cancel();
    _stateSaveTicker?.cancel();
    _adapterStateSub?.cancel();
    _scanResultsSub?.cancel();
    _scanStateSub?.cancel();
    _connectionSub?.cancel();
    _statusDataSub?.cancel();
    _reconnectTimer?.cancel();
    // Save state one last time before disposing
    unawaited(_saveCurrentState());
    final BluetoothDevice? device = _device;
    if (device != null) {
      unawaited(device.disconnect());
    }
    super.dispose();
  }
}
