#include <NimBLEDevice.h>

#define OPEN_PIN 25
#define CLOSE_PIN 26
#define PULSE_DURATION 200

#define SERVICE_UUID "12345678-1234-1234-1234-1234567890ab"
#define CHARACTERISTIC_UUID "abcd1234-5678-90ab-cdef-1234567890ab"

NimBLEServer *pServer = nullptr;
NimBLECharacteristic *pCharacteristic = nullptr;
bool deviceConnected = false;
bool oldDeviceConnected = false;

// Non-blocking button press variables
unsigned long buttonStartTime = 0;
int activePin = -1;
bool buttonPressed = false;

void startButtonPress(int pin)
{
  if (!buttonPressed) {  // Only if no button is currently being pressed
    digitalWrite(pin, LOW);
    buttonStartTime = millis();
    activePin = pin;
    buttonPressed = true;
    Serial.print("Button press started on pin ");
    Serial.println(pin);
  }
}

void updateButtonPress()
{
  if (buttonPressed && (millis() - buttonStartTime >= PULSE_DURATION)) {
    digitalWrite(activePin, HIGH);
    Serial.print("Button press completed on pin ");
    Serial.println(activePin);
    buttonPressed = false;
    activePin = -1;
  }
}

class MyServerCallbacks : public NimBLEServerCallbacks
{
  void onConnect(NimBLEServer *pServer) override
  {
    deviceConnected = true;
    Serial.println("Client connected");
    
    // Stop advertising when connected
    NimBLEDevice::getAdvertising()->stop();
  }

  void onDisconnect(NimBLEServer *pServer) override
  {
    deviceConnected = false;
    Serial.println("Client disconnected");
  }
};

class MyCharacteristicCallbacks : public NimBLECharacteristicCallbacks
{
  void onWrite(NimBLECharacteristic *pChar) override
  {
    std::string val = pChar->getValue();
    if (val.length() > 0)
    {
      Serial.print("Received command: ");
      Serial.println(val[0]);
      Serial.flush();  // Ensure serial output is sent immediately
      
      if (val[0] == '1')
      {
        Serial.println("Opening exhaust");
        Serial.flush();
        startButtonPress(OPEN_PIN);
      }
      else if (val[0] == '0')
      {
        Serial.println("Closing exhaust");
        Serial.flush();
        startButtonPress(CLOSE_PIN);
      }
      else
      {
        Serial.println("Unknown command");
        Serial.flush();
      }
    }
  }
};

void setup()
{
  Serial.begin(115200);
  delay(2000);
  Serial.println("Starting Varex BLE Controller");

  // Setup pins
  pinMode(OPEN_PIN, OUTPUT);
  digitalWrite(OPEN_PIN, HIGH);
  pinMode(CLOSE_PIN, OUTPUT);
  digitalWrite(CLOSE_PIN, HIGH);
  Serial.println("GPIO pins configured");

  // Initialize BLE
  NimBLEDevice::init("VarexESP32");
  NimBLEDevice::setPower(ESP_PWR_LVL_P9); // Maximum power for better range

  // Create BLE Server
  pServer = NimBLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  // Create BLE Service
  NimBLEService *pService = pServer->createService(SERVICE_UUID);

  // Create BLE Characteristic
  pCharacteristic = pService->createCharacteristic(
      CHARACTERISTIC_UUID,
      NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR);

  pCharacteristic->setCallbacks(new MyCharacteristicCallbacks());
  pService->start();

  // Start advertising
  NimBLEAdvertising *pAdvertising = NimBLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setName("VarexESP32");
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x0);  // set value to 0x00 to not advertise this parameter
  pAdvertising->start();

  Serial.println("BLE Server started!");
  Serial.println("Device name: VarexESP32");
  Serial.print("Service UUID: ");
  Serial.println(SERVICE_UUID);
  Serial.println("Waiting for client connection...");
}

void loop()
{
  // Update non-blocking button press
  updateButtonPress();
  
  // Handle connection state changes
  if (!deviceConnected && oldDeviceConnected)
  {
    delay(500); // Give the bluetooth stack time to get things ready
    pServer->startAdvertising(); // restart advertising
    Serial.println("Restarting advertising...");
    Serial.flush();
    oldDeviceConnected = deviceConnected;
  }
  
  if (deviceConnected && !oldDeviceConnected)
  {
    Serial.println("Device connected and ready for commands");
    Serial.flush();
    oldDeviceConnected = deviceConnected;
  }

  delay(10); // Reduced delay for more responsive button handling
}
