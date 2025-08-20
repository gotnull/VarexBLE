#include <NimBLEDevice.h>

#define OPEN_PIN 25        // Connect to CHJ-RXB3 Data 2A (Open)
#define CLOSE_PIN 26       // Connect to CHJ-RXB3 Data 2B (Close)
#define PULSE_DURATION 200 // ms

// BLE service & characteristic UUIDs
#define SERVICE_UUID "12345678-1234-1234-1234-1234567890ab"
#define CHARACTERISTIC_UUID "abcd1234-5678-90ab-cdef-1234567890ab"

NimBLEServer *pServer = nullptr;
NimBLECharacteristic *pCharacteristic = nullptr;

void pressButton(int pin)
{
  digitalWrite(pin, LOW); // Active LOW pulse
  delay(PULSE_DURATION);
  digitalWrite(pin, HIGH); // Release
}

// BLE write callback
class MyCallbacks : public NimBLECharacteristicCallbacks
{
  void onWrite(NimBLECharacteristic *pChar) override
  {
    std::string value = pChar->getValue();
    if (value.length() > 0)
    {
      if (value[0] == '1')
      { // Open
        Serial.println("Opening exhaust");
        pressButton(OPEN_PIN);
      }
      else if (value[0] == '0')
      { // Close
        Serial.println("Closing exhaust");
        pressButton(CLOSE_PIN);
      }
    }
  }
};

void setup()
{
  Serial.begin(115200);

  pinMode(OPEN_PIN, OUTPUT);
  pinMode(CLOSE_PIN, OUTPUT);
  digitalWrite(OPEN_PIN, HIGH);  // Idle HIGH (open-drain)
  digitalWrite(CLOSE_PIN, HIGH); // Idle HIGH

  NimBLEDevice::init("Varex-ESP32");
  NimBLEServer *pServer = NimBLEDevice::createServer();

  NimBLEService *pService = pServer->createService(SERVICE_UUID);
  pCharacteristic = pService->createCharacteristic(
      CHARACTERISTIC_UUID,
      NIMBLE_PROPERTY::WRITE);

  pCharacteristic->setCallbacks(new MyCallbacks());
  pService->start();

  NimBLEAdvertising *pAdvertising = NimBLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->start();

  Serial.println("BLE Peripheral started. Waiting for Flutter app...");
}

void loop()
{
  // Nothing needed here, BLE events handle everything
}
