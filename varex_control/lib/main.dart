import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

final flutterReactiveBle = FlutterReactiveBle();
final serviceUuid = Uuid.parse("12345678-1234-1234-1234-1234567890ab");
final characteristicUuid = Uuid.parse("abcd1234-5678-90ab-cdef-1234567890ab");

void main() {
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

  @override
  void initState() {
    super.initState();
    scanAndConnect();
  }

  void scanAndConnect() {
    flutterReactiveBle.scanForDevices(withServices: [serviceUuid]).listen((d) {
      if (d.name.contains("Varex-ESP32") && device == null) {
        device = d;
        exhaustChar = QualifiedCharacteristic(
          serviceId: serviceUuid,
          characteristicId: characteristicUuid,
          deviceId: device!.id,
        );
        flutterReactiveBle.connectToDevice(id: device!.id).listen((_) {});
        setState(() {});
      }
    });
  }

  void sendCommand(String cmd) {
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
            ? const Text("Scanning for Varex-ESP32...")
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
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
