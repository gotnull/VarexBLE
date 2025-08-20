#include <NimBLEDevice.h>

#define OPEN_PIN 25        // Connect to CHJ-RXB3 Data 2A (Open)
#define CLOSE_PIN 26       // Connect to CHJ-RXB3 Data 2B (Close)
#define PULSE_DURATION 200 // ms

// BLE service & characteristic UUIDs
#define SERVICE_UUID "12345678-1234-1234-1234-1234567890ab"
#define CHARACTERISTIC_UUID "abcd1234-5678-90ab-cdef-1234567890ab"

NimBLEServer *pServer = nullptr;
NimBLECharacteristic *pCharacteristic = nullptr;

// Press a button (active LOW pulse)
void pressButton(int pin)
{
  digitalWrite(pin, LOW);
  delay(PULSE_DURATION);
  digitalWrite(pin, HIGH);
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
      Serial.flush();
    }
  }
};

void setup()
{
  // Give Serial time to initialize
  Serial.begin(115200);
  delay(2000);
  Serial.println("HELLO ESP32");
  Serial.flush();

  pinMode(OPEN_PIN, OUTPUT);
  pinMode(CLOSE_PIN, OUTPUT);
  digitalWrite(OPEN_PIN, HIGH);  // Idle HIGH
  digitalWrite(CLOSE_PIN, HIGH); // Idle HIGH

  Serial.println("BLE Init...");
  Serial.flush();

  NimBLEDevice::init("Varex-ESP32");

  pServer = NimBLEDevice::createServer();
  Serial.println("BLE Server Created...");
  Serial.flush();

  NimBLEService *pService = pServer->createService(SERVICE_UUID);
  pCharacteristic = pService->createCharacteristic(
      CHARACTERISTIC_UUID,
      NIMBLE_PROPERTY::WRITE);

  Serial.println("BLE Service Created...");
  Serial.flush();

  pCharacteristic->setCallbacks(new MyCallbacks());
  Serial.println("BLE Callbacks set...");
  Serial.flush();

  pService->start();
  Serial.println("BLE Service Started...");
  Serial.flush();

  NimBLEAdvertising *pAdvertising = NimBLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->start();

  Serial.println("BLE Peripheral started. Waiting for Varex Controller app...");
  Serial.flush();
}

void loop()
{
  // Nothing needed here; BLE events handle everything
}
