import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shimmer/shimmer.dart';
import 'package:vibration/vibration.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

final flutterReactiveBle = FlutterReactiveBle();
final serviceUuid = Uuid.parse("12345678-1234-1234-1234-1234567890ab");
final characteristicUuid = Uuid.parse("abcd1234-5678-90ab-cdef-1234567890ab");
final statusCharacteristicUuid = Uuid.parse(
  "dcba4321-8765-ba09-fedc-4321876543ba",
);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isAndroid || Platform.isIOS) {
    // Request permissions and verify they're granted
    var locationStatus = await Permission.location.request();
    var bluetoothScanStatus = await Permission.bluetoothScan.request();
    var bluetoothConnectStatus = await Permission.bluetoothConnect.request();

    debugPrint("Location permission status: $locationStatus");
    debugPrint("Bluetooth scan permission status: $bluetoothScanStatus");
    debugPrint("Bluetooth connect permission status: $bluetoothConnectStatus");

    // Check if all required permissions are granted
    if (locationStatus != PermissionStatus.granted ||
        bluetoothScanStatus != PermissionStatus.granted ||
        bluetoothConnectStatus != PermissionStatus.granted) {
      debugPrint("WARNING: Not all BLE permissions granted!");
    }
  }

  runApp(const VarexApp());
}

class VarexApp extends StatelessWidget {
  const VarexApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Varex Control',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'System',
        useMaterial3: true,
        colorScheme: const ColorScheme.dark(
          primary: VarexColors.primary,
          secondary: VarexColors.secondary,
          surface: VarexColors.cardBackground,
          background: VarexColors.background,
        ),
      ),
      home: const BleControlPage(),
    );
  }
}

// Clean color palette like Flighty
class VarexColors {
  static const background = Color(0xFF000000);
  static const cardBackground = Color(0xFF1C1C1E);
  static const primary = Color(0xFF007AFF);
  static const secondary = Color(0xFF34C759);
  static const destructive = Color(0xFFFF3B30);
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFF8E8E93);
  static const separator = Color(0xFF38383A);
}

class BleControlPage extends StatefulWidget {
  const BleControlPage({super.key});

  @override
  BleControlPageState createState() => BleControlPageState();
}

class BleControlPageState extends State<BleControlPage> {
  DiscoveredDevice? device;
  QualifiedCharacteristic? exhaustChar;
  QualifiedCharacteristic? statusChar;
  StreamSubscription<DiscoveredDevice>? scanSubscription;
  StreamSubscription<ConnectionStateUpdate>? connectionSubscription;
  StreamSubscription<BleStatus>? bleStatusSubscription;
  StreamSubscription<List<int>>? statusSubscription;
  String statusMessage = "Initializing...";
  String lastCommandStatus = "";
  bool isConnected = false;
  bool isScanning = false;
  bool isConnecting = false;

  @override
  void initState() {
    super.initState();

    // Monitor BLE status changes
    bleStatusSubscription = flutterReactiveBle.statusStream.listen((status) {
      debugPrint("BLE Status changed to: $status");
      if (status == BleStatus.ready && device == null) {
        scanAndConnect();
      } else if (status != BleStatus.ready) {
        setState(() {
          statusMessage =
              "BLE Status: $status - Check Location permission in iOS Settings";
        });
      }
    });

    scanAndConnect();
  }

  @override
  void dispose() {
    scanSubscription?.cancel();
    connectionSubscription?.cancel();
    bleStatusSubscription?.cancel();
    statusSubscription?.cancel();
    super.dispose();
  }

  void scanAndConnect() async {
    if (isScanning || isConnected) return;

    debugPrint("Checking BLE status...");

    // Check BLE status first
    final status = flutterReactiveBle.status;
    debugPrint("BLE Status: $status");

    if (status != BleStatus.ready) {
      debugPrint("BLE not ready. Current status: $status");
      setState(() {
        statusMessage =
            "BLE not ready: $status. Check permissions in device settings.";
      });
      return;
    }

    setState(() {
      statusMessage = "Scanning for VarexESP32...";
      isScanning = true;
    });

    debugPrint("Starting BLE scan for devices with service UUID...");

    scanSubscription = flutterReactiveBle
        .scanForDevices(
          withServices: [serviceUuid],
          scanMode: ScanMode.lowLatency,
        )
        .listen(
          (DiscoveredDevice device) {
            final name = device.name.isNotEmpty ? device.name : "Unknown";
            debugPrint("Discovered: $name (${device.id}) RSSI: ${device.rssi}");

            if (device.name.contains("VarexESP32") && this.device == null) {
              this.device = device;
              debugPrint("Found target device! Connecting to: ${device.id}");
              scanSubscription?.cancel();

              setState(() {
                statusMessage = "Found VarexESP32! Connecting...";
                isScanning = false;
                isConnecting = true;
              });

              connectToDevice(device);
            }
          },
          onError: (error) {
            debugPrint("Scan error: $error");
            setState(() {
              statusMessage = "Scan error: $error";
              isScanning = false;
            });
          },
        );

    // Stop scanning after 10 seconds if no device found
    Timer(const Duration(seconds: 10), () {
      if (isScanning && device == null) {
        scanSubscription?.cancel();
        setState(() {
          statusMessage = "No VarexESP32 found. Tap to retry.";
          isScanning = false;
        });
      }
    });
  }

  void connectToDevice(DiscoveredDevice device) {
    connectionSubscription = flutterReactiveBle
        .connectToDevice(id: device.id)
        .listen(
          (connectionState) {
            debugPrint("Connection state: ${connectionState.connectionState}");

            switch (connectionState.connectionState) {
              case DeviceConnectionState.connecting:
                setState(() {
                  statusMessage = "Connecting to ${device.name}...";
                  isConnecting = true;
                });
                break;
              case DeviceConnectionState.connected:
                debugPrint("Connected! Discovering services...");
                setState(() {
                  statusMessage = "Connected! Discovering services...";
                  isConnecting =
                      true; // Still connecting until services are discovered
                });
                discoverServices(device);
                break;
              case DeviceConnectionState.disconnecting:
                setState(() {
                  statusMessage = "Disconnecting...";
                  isConnected = false;
                  isConnecting = false;
                });
                break;
              case DeviceConnectionState.disconnected:
                setState(() {
                  statusMessage = "Disconnected. Tap to reconnect.";
                  isConnected = false;
                  isConnecting = false;
                  this.device = null;
                  exhaustChar = null;
                });
                break;
            }
          },
          onError: (dynamic error) {
            debugPrint("Connection error: $error");
            setState(() {
              statusMessage = "Connection failed: $error";
              isConnected = false;
              isConnecting = false;
            });
          },
        );
  }

  void discoverServices(DiscoveredDevice device) async {
    try {
      await flutterReactiveBle.discoverAllServices(device.id);
      final services = await flutterReactiveBle.getDiscoveredServices(
        device.id,
      );
      debugPrint("Discovered ${services.length} services");

      bool serviceFound = false;
      for (final service in services) {
        debugPrint("Service: ${service.id}");
        if (service.id == serviceUuid) {
          serviceFound = true;
          for (final characteristic in service.characteristics) {
            debugPrint("  Characteristic: ${characteristic.id}");

            if (characteristic.id == characteristicUuid) {
              exhaustChar = QualifiedCharacteristic(
                serviceId: serviceUuid,
                characteristicId: characteristicUuid,
                deviceId: device.id,
              );
            }

            if (characteristic.id == statusCharacteristicUuid) {
              statusChar = QualifiedCharacteristic(
                serviceId: serviceUuid,
                characteristicId: statusCharacteristicUuid,
                deviceId: device.id,
              );

              // Subscribe to status notifications
              subscribeToStatusUpdates();
            }
          }

          // Check if we found the required characteristics
          if (exhaustChar != null) {
            setState(() {
              statusMessage = "Ready to control exhaust";
              isConnected = true;
              isConnecting = false; // Connection process complete
            });
            return;
          }
        }
      }

      if (!serviceFound) {
        setState(() {
          statusMessage = "Service not found on device";
          isConnecting = false;
        });
      }
    } catch (e) {
      debugPrint("Service discovery error: $e");
      setState(() {
        statusMessage = "Service discovery failed: $e";
        isConnecting = false;
      });
    }
  }

  void subscribeToStatusUpdates() {
    if (statusChar != null) {
      statusSubscription = flutterReactiveBle
          .subscribeToCharacteristic(statusChar!)
          .listen(
            (data) {
              final status = String.fromCharCodes(data);
              debugPrint("Status update: $status");

              setState(() {
                lastCommandStatus = status;
              });

              // Show temporary status message
              if (status.contains("COMPLETE")) {
                setState(() {
                  statusMessage = status.replaceAll("_", " ").toLowerCase();
                });

                // Reset status message after 2 seconds
                Timer(const Duration(seconds: 2), () {
                  if (mounted) {
                    setState(() {
                      statusMessage = "Ready to control exhaust";
                    });
                  }
                });
              }
            },
            onError: (error) {
              debugPrint("Status subscription error: $error");
            },
          );
    }
  }

  void sendCommand(String cmd) async {
    if (device == null || exhaustChar == null || !isConnected) {
      debugPrint("Device or characteristic not ready");
      return;
    }

    // Haptic feedback
    if (await Vibration.hasVibrator() == true) {
      Vibration.vibrate(duration: 50);
    }

    // Light haptic feedback
    HapticFeedback.lightImpact();

    setState(() {
      lastCommandStatus = cmd == '1' ? "OPENING..." : "CLOSING...";
    });

    flutterReactiveBle
        .writeCharacteristicWithResponse(
          exhaustChar!,
          value: [cmd.codeUnitAt(0)],
        )
        .catchError((error) {
          debugPrint("Write error: $error");
          setState(() {
            lastCommandStatus = "ERROR: $error";
          });
        });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VarexColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(),
            Expanded(
              child: !isConnected
                  ? _buildConnectionScreen()
                  : _buildControlScreen(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: VarexColors.cardBackground,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.settings_input_antenna,
              color: VarexColors.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Varex Control',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: VarexColors.textPrimary,
                  ),
                ),
                Text(
                  'Exhaust System',
                  style: TextStyle(
                    fontSize: 14,
                    color: VarexColors.textSecondary,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          if (!isConnected && !isScanning && !isConnecting)
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: VarexColors.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: IconButton(
                onPressed: scanAndConnect,
                icon: const Icon(Icons.refresh, color: Colors.white, size: 20),
                padding: EdgeInsets.zero,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildConnectionScreen() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const SizedBox(height: 40),
          
          // Status Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: VarexColors.cardBackground,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: isScanning || isConnecting 
                        ? VarexColors.primary 
                        : VarexColors.separator,
                    borderRadius: BorderRadius.circular(32),
                  ),
                  child: Icon(
                    isScanning || isConnecting 
                        ? Icons.bluetooth_searching 
                        : Icons.bluetooth_disabled,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  statusMessage,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: VarexColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Permission Warning
          if (statusMessage.contains("permissions"))
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: VarexColors.destructive.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: VarexColors.destructive.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_rounded,
                    color: VarexColors.destructive,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Location Permission Required',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: VarexColors.destructive,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Enable in Settings > Privacy',
                          style: TextStyle(
                            fontSize: 12,
                            color: VarexColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          const Spacer(),

          // Action Button
          if (!isScanning && !isConnecting && !statusMessage.contains("permissions"))
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: scanAndConnect,
                style: ElevatedButton.styleFrom(
                  backgroundColor: VarexColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  'Scan for Device',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),

          // Loading State
          if (isScanning || isConnecting)
            Column(
              children: [
                SizedBox(
                  width: 40,
                  height: 40,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation(VarexColors.primary),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  isScanning ? 'Scanning...' : 'Connecting...',
                  style: TextStyle(
                    fontSize: 14,
                    color: VarexColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildControlScreen() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Connection Status Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: VarexColors.cardBackground,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: VarexColors.secondary,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Icon(
                    Icons.check_circle_outline,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Connected',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: VarexColors.textPrimary,
                        ),
                      ),
                      Text(
                        device!.name,
                        style: TextStyle(
                          fontSize: 14,
                          color: VarexColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: VarexColors.secondary,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Status Card
          if (lastCommandStatus.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _getStatusColor().withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _getStatusColor().withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _getStatusMaterialIcon(),
                    color: _getStatusColor(),
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    lastCommandStatus,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _getStatusColor(),
                    ),
                  ),
                ],
              ),
            ),

          const Spacer(),

          // Control Section
          Text(
            'Exhaust Control',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: VarexColors.textPrimary,
            ),
          ),

          const SizedBox(height: 24),

          // Control Buttons
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 120,
                  decoration: BoxDecoration(
                    color: VarexColors.secondary,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => sendCommand('1'),
                      borderRadius: BorderRadius.circular(16),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.open_in_full,
                            color: Colors.white,
                            size: 32,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'OPEN',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Container(
                  height: 120,
                  decoration: BoxDecoration(
                    color: VarexColors.destructive,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => sendCommand('0'),
                      borderRadius: BorderRadius.circular(16),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.close_fullscreen,
                            color: Colors.white,
                            size: 32,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'CLOSE',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }


  Color _getStatusColor() {
    if (lastCommandStatus.contains("ERROR")) return VarexColors.destructive;
    if (lastCommandStatus.contains("COMPLETE")) return VarexColors.secondary;
    return VarexColors.primary;
  }

  IconData _getStatusMaterialIcon() {
    if (lastCommandStatus.contains("ERROR")) return Icons.error_outline;
    if (lastCommandStatus.contains("COMPLETE")) return Icons.check_circle_outline;
    return Icons.access_time;
  }
}
