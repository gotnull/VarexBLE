import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';

final flutterReactiveBle = FlutterReactiveBle();
final serviceUuid = Uuid.parse("12345678-1234-1234-1234-1234567890ab");
final characteristicUuid = Uuid.parse("abcd1234-5678-90ab-cdef-1234567890ab");

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
  StreamSubscription<DiscoveredDevice>? scanSubscription;
  StreamSubscription<ConnectionStateUpdate>? connectionSubscription;
  StreamSubscription<BleStatus>? bleStatusSubscription;
  String statusMessage = "Initializing...";

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
          statusMessage = "BLE Status: $status - Check Location permission in iOS Settings";
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
    super.dispose();
  }

  void scanAndConnect() async {
    debugPrint("Checking BLE status...");
    
    // Check BLE status first
    final status = flutterReactiveBle.status;
    debugPrint("BLE Status: $status");
    
    if (status != BleStatus.ready) {
      debugPrint("BLE not ready. Current status: $status");
      setState(() {
        statusMessage = "BLE not ready: $status. Check permissions in device settings.";
      });
      return;
    }

    setState(() {
      statusMessage = "Scanning for Varex-ESP32...";
    });
    
    debugPrint("Starting BLE scan for all devices...");

    scanSubscription = flutterReactiveBle
        .scanForDevices(
          withServices: [],
          scanMode: ScanMode.lowLatency,
        )
        .listen((DiscoveredDevice device) {
          final name = device.name.isNotEmpty ? device.name : "Unknown";
          debugPrint("Discovered: $name (${device.id}) RSSI: ${device.rssi}");
          
          if (device.name.contains("Varex-ESP32") && this.device == null) {
            this.device = device;
            debugPrint("Found target device! Connecting to: ${device.id}");
            scanSubscription?.cancel();

            setState(() {
              statusMessage = "Found Varex-ESP32! Connecting...";
            });

            exhaustChar = QualifiedCharacteristic(
              serviceId: serviceUuid,
              characteristicId: characteristicUuid,
              deviceId: device.id,
            );

            connectionSubscription = flutterReactiveBle
                .connectToDevice(id: device.id)
                .listen((connectionState) {
                  debugPrint("Connection state: ${connectionState.connectionState}");
                }, onError: (dynamic error) {
                  debugPrint("Connection error: $error");
                });
            setState(() {});
          }
        }, onError: (error) {
          debugPrint("Scan error: $error");
          setState(() {
            statusMessage = "Scan error: $error";
          });
        });
  }

  void sendCommand(String cmd) {
    if (device == null || exhaustChar == null) {
      debugPrint("Device or characteristic not ready");
      return;
    }

    if (exhaustChar != null) {
      flutterReactiveBle.writeCharacteristicWithResponse(
        exhaustChar!,
        value: [cmd.codeUnitAt(0)],
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Varex BLE Control")),
      body: Center(
        child: device == null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(statusMessage, textAlign: TextAlign.center),
                  const SizedBox(height: 20),
                  if (statusMessage.contains("permissions"))
                    const Text(
                      "Go to Settings > Apps > Varex Control > Permissions\nand enable Bluetooth and Location",
                      textAlign: TextAlign.center,
                    ),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text("Connected to ${device!.name}"),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () => sendCommand('1'), // Open
                    child: const Text("Open Exhaust"),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () => sendCommand('0'), // Close
                    child: const Text("Close Exhaust"),
                  ),
                ],
              ),
      ),
    );
  }
}