#include <NimBLEDevice.h>

#define OPEN_PIN 25
#define CLOSE_PIN 26
#define PULSE_DURATION 200

#define SERVICE_UUID "12345678-1234-1234-1234-1234567890ab"
#define CHARACTERISTIC_UUID "abcd1234-5678-90ab-cdef-1234567890ab"

NimBLECharacteristic *pCharacteristic = nullptr;

void pressButton(int pin)
{
  digitalWrite(pin, LOW);
  delay(PULSE_DURATION);
  digitalWrite(pin, HIGH);
}

class MyCallbacks : public NimBLECharacteristicCallbacks
{
  void onWrite(NimBLECharacteristic *pChar) override
  {
    std::string val = pChar->getValue();
    if (val.length() > 0)
    {
      if (val[0] == '1')
        pressButton(OPEN_PIN);
      else if (val[0] == '0')
        pressButton(CLOSE_PIN);
    }
  }
};

void setup()
{
  Serial.begin(115200);
  delay(2000);

  pinMode(OPEN_PIN, OUTPUT);
  digitalWrite(OPEN_PIN, HIGH);
  pinMode(CLOSE_PIN, OUTPUT);
  digitalWrite(CLOSE_PIN, HIGH);

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
  pAdvertising->setName("Varex-ESP32");
  pAdvertising->start();

  Serial.println("BLE started and advertising only service UUID");
}

void loop() {}
