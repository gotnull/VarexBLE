#include <NimBLEDevice.h>

#define OPEN_PIN 25
#define CLOSE_PIN 26
#define PULSE_DURATION 200

#define SERVICE_UUID "12345678-1234-1234-1234-1234567890ab"
#define CHARACTERISTIC_UUID "abcd1234-5678-90ab-cdef-1234567890ab"
#define STATUS_CHARACTERISTIC_UUID "dcba4321-8765-ba09-fedc-4321876543ba"

NimBLEServer *pServer = nullptr;
NimBLECharacteristic *pCharacteristic = nullptr;
NimBLECharacteristic *pStatusCharacteristic = nullptr;
bool deviceConnected = false;
bool oldDeviceConnected = false;

// Non-blocking button press variables
unsigned long buttonStartTime = 0;
int activePin = -1;
bool buttonPressed = false;

// Command queue to prevent overlapping commands
#define QUEUE_SIZE 10
char commandQueue[QUEUE_SIZE];
int queueHead = 0;
int queueTail = 0;
bool queueFull = false;

// Add command to queue
void queueCommand(char cmd)
{
  if (!queueFull)
  {
    commandQueue[queueTail] = cmd;
    queueTail = (queueTail + 1) % QUEUE_SIZE;
    if (queueTail == queueHead)
    {
      queueFull = true;
    }
  }
}

// Get next command from queue
char getNextCommand()
{
  if (queueHead == queueTail && !queueFull)
  {
    return 0; // Queue empty
  }

  char cmd = commandQueue[queueHead];
  queueHead = (queueHead + 1) % QUEUE_SIZE;
  queueFull = false;
  return cmd;
}

void sendStatusUpdate(const char *status)
{
  if (deviceConnected && pStatusCharacteristic != nullptr)
  {
    pStatusCharacteristic->setValue(status);
    pStatusCharacteristic->notify();
  }
}

void startButtonPress(int pin, char cmd)
{
  if (!buttonPressed)
  { // Only if no button is currently being pressed
    buttonStartTime = millis();
    activePin = pin;
    buttonPressed = true;

    // Print command info all at once to prevent corruption
    if (cmd == '1')
    {
      digitalWrite(OPEN_PIN, LOW);
      Serial.println("CMD:1 OPEN_START PIN:11");
      sendStatusUpdate("OPEN_STARTED");
    }
    else if (cmd == '0')
    {
      digitalWrite(CLOSE_PIN, LOW);
      Serial.println("CMD:0 CLOSE_START PIN:10");
      sendStatusUpdate("CLOSE_STARTED");
    }
    Serial.flush();
  }
}

void updateButtonPress()
{
  if (buttonPressed && (millis() - buttonStartTime >= PULSE_DURATION))
  {
    digitalWrite(activePin, HIGH);

    // Print completion info and send status update
    if (activePin == OPEN_PIN)
    {
      Serial.println("OPEN_COMPLETE PIN:11");
      sendStatusUpdate("OPEN_COMPLETE");
    }
    else if (activePin == CLOSE_PIN)
    {
      Serial.println("CLOSE_COMPLETE PIN:10");
      sendStatusUpdate("CLOSE_COMPLETE");
    }
    Serial.flush();

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
    if (val.length() > 0 && (val[0] == '1' || val[0] == '0'))
    {
      // Add command to queue instead of executing immediately
      queueCommand(val[0]);
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
  pinMode(CLOSE_PIN, OUTPUT);
  digitalWrite(OPEN_PIN, LOW);
  digitalWrite(CLOSE_PIN, LOW);
  Serial.println("GPIO pins configured");

  // Initialize BLE
  NimBLEDevice::init("VarexESP32");
  NimBLEDevice::setPower(ESP_PWR_LVL_P9); // Maximum power for better range

  // Create BLE Server
  pServer = NimBLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  // Create BLE Service
  NimBLEService *pService = pServer->createService(SERVICE_UUID);

  // Create BLE Write Characteristic (for commands)
  pCharacteristic = pService->createCharacteristic(
      CHARACTERISTIC_UUID,
      NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR);

  pCharacteristic->setCallbacks(new MyCharacteristicCallbacks());

  // Create BLE Status Characteristic (for notifications)
  pStatusCharacteristic = pService->createCharacteristic(
      STATUS_CHARACTERISTIC_UUID,
      NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY);

  pStatusCharacteristic->setValue("READY");
  pService->start();

  // Start advertising
  NimBLEAdvertising *pAdvertising = NimBLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setName("VarexESP32");
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x0); // set value to 0x00 to not advertise this parameter
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

  // Process queued commands when not busy
  if (!buttonPressed)
  {
    char nextCmd = getNextCommand();
    if (nextCmd != 0)
    {
      if (nextCmd == '1')
      {
        startButtonPress(OPEN_PIN, '1');
      }
      else if (nextCmd == '0')
      {
        startButtonPress(CLOSE_PIN, '0');
      }
    }
  }

  // Handle connection state changes
  if (!deviceConnected && oldDeviceConnected)
  {
    delay(500);                  // Give the bluetooth stack time to get things ready
    pServer->startAdvertising(); // restart advertising
    Serial.println("ADVERTISING_RESTART");
    Serial.flush();
    oldDeviceConnected = deviceConnected;
  }

  if (deviceConnected && !oldDeviceConnected)
  {
    Serial.println("CLIENT_CONNECTED");
    Serial.flush();
    oldDeviceConnected = deviceConnected;
  }

  delay(5); // Very short delay for responsive handling
}
