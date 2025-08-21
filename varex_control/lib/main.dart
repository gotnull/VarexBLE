import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';

final flutterReactiveBle = FlutterReactiveBle();
final serviceUuid = Uuid.parse("12345678-1234-1234-1234-1234567890ab");
final characteristicUuid = Uuid.parse("abcd1234-5678-90ab-cdef-1234567890ab");
final statusCharacteristicUuid = Uuid.parse("dcba4321-8765-ba09-fedc-4321876543ba");

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

  runApp(const MaterialApp(home: BleControlPage()));
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
                  isConnecting = true; // Still connecting until services are discovered
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
          .listen((data) {
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
      }, onError: (error) {
        debugPrint("Status subscription error: $error");
      });
    }
  }

  void sendCommand(String cmd) {
    if (device == null || exhaustChar == null || !isConnected) {
      debugPrint("Device or characteristic not ready");
      return;
    }

    setState(() {
      lastCommandStatus = cmd == '1' ? "OPENING..." : "CLOSING...";
    });

    flutterReactiveBle.writeCharacteristicWithResponse(
      exhaustChar!,
      value: [cmd.codeUnitAt(0)],
    ).catchError((error) {
      debugPrint("Write error: $error");
      setState(() {
        lastCommandStatus = "ERROR: $error";
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Varex BLE Control"),
        actions: [
          if (!isConnected && !isScanning && !isConnecting)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: scanAndConnect,
            ),
        ],
      ),
      body: Center(
        child: !isConnected
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isScanning || isConnecting
                        ? Icons.bluetooth_searching
                        : Icons.bluetooth_disabled,
                    size: 64,
                    color: isScanning || isConnecting ? Colors.blue : Colors.grey,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    statusMessage,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 20),
                  if (statusMessage.contains("permissions"))
                    const Text(
                      "Go to Settings > Privacy > Location Services\nand enable for this app",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                  if (!isScanning && !isConnecting && !statusMessage.contains("permissions"))
                    ElevatedButton(
                      onPressed: scanAndConnect,
                      child: const Text("Scan for Device"),
                    ),
                  if (isScanning || isConnecting)
                    const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: CircularProgressIndicator(),
                    ),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.bluetooth_connected,
                    size: 64,
                    color: Colors.green,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    "Connected to ${device!.name}",
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    statusMessage,
                    style: const TextStyle(color: Colors.green),
                  ),
                  const SizedBox(height: 10),
                  if (lastCommandStatus.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: lastCommandStatus.contains("ERROR") 
                            ? Colors.red.withOpacity(0.1)
                            : lastCommandStatus.contains("COMPLETE")
                            ? Colors.green.withOpacity(0.1)
                            : Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: lastCommandStatus.contains("ERROR") 
                              ? Colors.red
                              : lastCommandStatus.contains("COMPLETE")
                              ? Colors.green
                              : Colors.orange,
                        ),
                      ),
                      child: Text(
                        lastCommandStatus,
                        style: TextStyle(
                          color: lastCommandStatus.contains("ERROR") 
                              ? Colors.red
                              : lastCommandStatus.contains("COMPLETE")
                              ? Colors.green
                              : Colors.orange,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  const SizedBox(height: 30),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () => sendCommand('1'),
                        icon: const Icon(Icons.open_in_full),
                        label: const Text("OPEN"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: () => sendCommand('0'),
                        icon: const Icon(Icons.close_fullscreen),
                        label: const Text("CLOSE"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }
}
