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
          primary: Color(0xFF00D4FF),
          secondary: Color(0xFFFF6B9D),
          surface: Color(0xFF0A0A0A),
        ),
      ),
      home: const BleControlPage(),
    );
  }
}

// Custom gradient definitions
class VarexGradients {
  static const primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF00D4FF), Color(0xFF0099CC), Color(0xFF0066FF)],
  );

  static const secondaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFF6B9D), Color(0xFFFF4081), Color(0xFFE91E63)],
  );

  static const backgroundGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF0A0A0A), Color(0xFF000000), Color(0xFF0A0A0A)],
  );

  static const glowGradient = RadialGradient(
    colors: [Color(0x4400D4FF), Color(0x2200D4FF), Color(0x0000D4FF)],
  );
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
      backgroundColor: Colors.black,
      body: Container(
        decoration: const BoxDecoration(
          gradient: VarexGradients.backgroundGradient,
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Custom App Bar
              _buildCustomAppBar(),

              // Main Content
              Expanded(
                child: !isConnected
                    ? _buildConnectionScreen()
                    : _buildControlScreen(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCustomAppBar() {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: VarexGradients.primaryGradient,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: const Color(0x4D00D4FF),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: PhosphorIcon(
              PhosphorIcons.lightning(),
              color: Colors.white,
              size: 24,
            ),
          ).animate().scale(delay: 100.ms, duration: 600.ms),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'VAREX',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    foreground: Paint()
                      ..shader = VarexGradients.primaryGradient.createShader(
                        const Rect.fromLTWH(0, 0, 200, 50),
                      ),
                  ),
                ).animate().slideX(delay: 200.ms, duration: 600.ms),
                Text(
                  'Exhaust Control System',
                  style: TextStyle(
                    fontSize: 14,
                    color: const Color(0xB3FFFFFF),
                    fontWeight: FontWeight.w500,
                  ),
                ).animate().slideX(delay: 300.ms, duration: 600.ms),
              ],
            ),
          ),
          if (!isConnected && !isScanning && !isConnecting)
            _buildGlowButton(
              onPressed: scanAndConnect,
              icon: PhosphorIcons.magnifyingGlass(),
              gradient: VarexGradients.primaryGradient,
            ).animate().scale(delay: 400.ms, duration: 600.ms),
        ],
      ),
    );
  }

  Widget _buildConnectionScreen() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Animated Bluetooth Icon
          Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: isScanning || isConnecting
                      ? VarexGradients.primaryGradient
                      : null,
                  color: isScanning || isConnecting
                      ? null
                      : Colors.grey.withValues(alpha: 0.2),
                  boxShadow: isScanning || isConnecting
                      ? [
                          BoxShadow(
                            color: const Color(
                              0xFF00D4FF,
                            ).withValues(alpha: 0.4),
                            blurRadius: 40,
                            spreadRadius: 10,
                          ),
                        ]
                      : null,
                ),
                child: PhosphorIcon(
                  isScanning || isConnecting
                      ? PhosphorIcons.bluetoothConnected()
                      : PhosphorIcons.bluetooth(),
                  color: Colors.white,
                  size: 48,
                ),
              )
              .animate(onPlay: (controller) => controller.repeat())
              .shimmer(
                duration: 2000.ms,
                color: isScanning || isConnecting
                    ? const Color(0xFF00D4FF)
                    : Colors.transparent,
              )
              .scale(
                begin: const Offset(1.0, 1.0),
                end: const Offset(1.1, 1.1),
                duration: 1000.ms,
              ),

          const SizedBox(height: 40),

          // Status Message
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.2),
                width: 1,
              ),
            ),
            child: Text(
              statusMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ).animate().slideY(delay: 200.ms, duration: 600.ms),

          const SizedBox(height: 40),

          // Permission Instructions
          if (statusMessage.contains("permissions"))
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 32),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
              ),
              child: Column(
                children: [
                  PhosphorIcon(
                    PhosphorIcons.warning(),
                    color: Colors.orange,
                    size: 24,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    "Location Permission Required",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "Go to Settings > Privacy > Location Services\nand enable for this app",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Colors.white70),
                  ),
                ],
              ),
            ).animate().slideY(delay: 400.ms, duration: 600.ms),

          const SizedBox(height: 40),

          // Scan Button or Progress
          if (!isScanning &&
              !isConnecting &&
              !statusMessage.contains("permissions"))
            _buildGlowButton(
              onPressed: scanAndConnect,
              icon: PhosphorIcons.magnifyingGlass(),
              gradient: VarexGradients.primaryGradient,
              text: "SCAN FOR DEVICE",
              isLarge: true,
            ).animate().slideY(delay: 600.ms, duration: 600.ms),

          if (isScanning || isConnecting)
            Column(
              children: [
                SizedBox(
                  width: 60,
                  height: 60,
                  child: CircularProgressIndicator(
                    strokeWidth: 4,
                    valueColor: AlwaysStoppedAnimation(
                      Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                if (isScanning)
                  Shimmer.fromColors(
                    baseColor: Colors.white.withValues(alpha: 0.5),
                    highlightColor: const Color(0xFF00D4FF),
                    child: const Text(
                      'SCANNING...',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                if (isConnecting)
                  Shimmer.fromColors(
                    baseColor: Colors.white.withValues(alpha: 0.5),
                    highlightColor: const Color(0xFF00D4FF),
                    child: const Text(
                      'CONNECTING...',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
              ],
            ).animate().fadeIn(delay: 300.ms),
        ],
      ),
    );
  }

  Widget _buildControlScreen() {
    return Column(
      children: [
        // Connection Status Header
        Container(
          margin: const EdgeInsets.all(20),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: VarexGradients.glowGradient,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: const Color(0xFF00D4FF).withValues(alpha: 0.3),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF00D4FF).withValues(alpha: 0.2),
                blurRadius: 30,
                spreadRadius: 5,
              ),
            ],
          ),
          child: Column(
            children: [
              // Connected Icon
              Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: VarexGradients.primaryGradient,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF00D4FF).withValues(alpha: 0.5),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: PhosphorIcon(
                      PhosphorIcons.checkCircle(),
                      color: Colors.white,
                      size: 32,
                    ),
                  )
                  .animate(onPlay: (controller) => controller.repeat())
                  .shimmer(
                    duration: 3000.ms,
                    color: Colors.white.withValues(alpha: 0.3),
                  ),

              const SizedBox(height: 16),

              Text(
                "CONNECTED",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  foreground: Paint()
                    ..shader = VarexGradients.primaryGradient.createShader(
                      const Rect.fromLTWH(0, 0, 200, 50),
                    ),
                  letterSpacing: 2,
                ),
              ),

              const SizedBox(height: 8),

              Text(
                device!.name,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),

              const SizedBox(height: 8),

              Text(
                statusMessage,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        ).animate().slideY(delay: 100.ms, duration: 600.ms),

        // Command Status
        if (lastCommandStatus.isNotEmpty)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: _getStatusColor().withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _getStatusColor().withValues(alpha: 0.5),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: _getStatusColor().withValues(alpha: 0.3),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                PhosphorIcon(
                  _getStatusIcon(),
                  color: _getStatusColor(),
                  size: 20,
                ),
                const SizedBox(width: 12),
                Text(
                  lastCommandStatus,
                  style: TextStyle(
                    color: _getStatusColor(),
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ).animate().slideX(delay: 200.ms, duration: 400.ms),

        const Spacer(),

        // Control Buttons
        Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Text(
                'EXHAUST CONTROL',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white.withValues(alpha: 0.8),
                  letterSpacing: 2,
                ),
              ).animate().slideY(delay: 300.ms, duration: 600.ms),

              const SizedBox(height: 40),

              Row(
                children: [
                  Expanded(
                    child: _buildControlButton(
                      onPressed: () => sendCommand('1'),
                      icon: PhosphorIcons.arrowsOut(),
                      text: 'OPEN',
                      gradient: VarexGradients.primaryGradient,
                      delay: 400,
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: _buildControlButton(
                      onPressed: () => sendCommand('0'),
                      icon: PhosphorIcons.arrowsIn(),
                      text: 'CLOSE',
                      gradient: VarexGradients.secondaryGradient,
                      delay: 500,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildGlowButton({
    required VoidCallback onPressed,
    required PhosphorIconData icon,
    required Gradient gradient,
    String? text,
    bool isLarge = false,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: EdgeInsets.all(isLarge ? 20 : 12),
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(isLarge ? 20 : 16),
          boxShadow: [
            BoxShadow(
              color: gradient.colors.first.withValues(alpha: 0.4),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PhosphorIcon(icon, color: Colors.white, size: isLarge ? 24 : 20),
            if (text != null) ...[
              const SizedBox(width: 12),
              Text(
                text,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: isLarge ? 16 : 14,
                  letterSpacing: 1,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildControlButton({
    required VoidCallback onPressed,
    required PhosphorIconData icon,
    required String text,
    required Gradient gradient,
    required int delay,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        height: 80,
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: gradient.colors.first.withValues(alpha: 0.4),
              blurRadius: 25,
              spreadRadius: 3,
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            PhosphorIcon(icon, color: Colors.white, size: 32),
            const SizedBox(height: 8),
            Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 16,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    ).animate().scale(delay: delay.ms, duration: 600.ms);
  }

  Color _getStatusColor() {
    if (lastCommandStatus.contains("ERROR")) return Colors.red;
    if (lastCommandStatus.contains("COMPLETE")) return const Color(0xFF00D4FF);
    return Colors.orange;
  }

  PhosphorIconData _getStatusIcon() {
    if (lastCommandStatus.contains("ERROR")) return PhosphorIcons.xCircle();
    if (lastCommandStatus.contains("COMPLETE")) {
      return PhosphorIcons.checkCircle();
    }
    return PhosphorIcons.clock();
  }
}
