#include "RCSwitch.h"
#include "clickButton.h"
#include "ELECHOUSE_CC1101_SRC_DRV.h"

SerialLogHandler logHandler;

RCSwitch mySwitch = RCSwitch();
int outputPin = D0;
int buttonPin = D2;
int inputPin = D3;
int ledPin = D7;

// Define SPI pins for CC1101
int CC1101_CSN = A2;
int CC1101_SCLK = A3;
int CC1101_MISO = A4;
int CC1101_MOSI = A5;

// CC1101 GDO0 pin match the outputPin / inputPin
int GDO0_PIN = D0;
int GDO2_PIN = D3;

static String gSwitchConfig = "{}";
static int gTimestamp = 0;
static const size_t kMaxNumberOfSwitches = 5;
static String gSwitchCodes[kMaxNumberOfSwitches];
static bool gSwitchState[kMaxNumberOfSwitches];
static int lastSwitchIndex = -1;
static unsigned long lastSwitchTimestamp = 0;
static const unsigned long kSwitchToggleTimeout = 450;

static bool _getSwitchState(unsigned long switchIndex) {
  return gSwitchState[switchIndex];
}

static bool _setSwitchState(int switchIndex, bool isOn) {
  if (gSwitchState[switchIndex] != isOn) {
    gSwitchState[switchIndex] = isOn;
    Log.info("Switch %d state changed to %d", switchIndex, isOn);
    Particle.publish("switchStateChanged",
        String(switchIndex) + " " + String(isOn));
  }
  return isOn;
}

int switchIndexForCode(String code) {
  for (int i = 0; i < kMaxNumberOfSwitches; i++) {
    if (gSwitchCodes[i].startsWith(code)) {
      return i;
    }
  }
  return -1;
}

static char *bin2tristate(char *bin) {
  static char returnValue[50];
  for (int i=0; i<50; i++) {
    returnValue[i] = '\0';
  }
  int pos = 0;
  int pos2 = 0;
  while (bin[pos]!='\0' && bin[pos+1]!='\0') {
    if (bin[pos]=='0' && bin[pos+1]=='0') {
      returnValue[pos2] = '0';
    } else if (bin[pos]=='1' && bin[pos+1]=='1') {
      returnValue[pos2] = '1';
    } else if (bin[pos]=='0' && bin[pos+1]=='1') {
      returnValue[pos2] = 'F';
    } else {
      return "not applicable";
    }
    pos = pos+2;
    pos2++;
  }
  returnValue[pos2] = '\0';
  return returnValue;
}

void output(unsigned long decimal, unsigned int length, unsigned int delay, unsigned int* raw, unsigned int protocol) {

  if (decimal == 0) {
    Log.info("Unknown encoding.");
  } else {
    char* b = mySwitch.dec2binWzerofill(decimal, length);
    char* tristate = bin2tristate(b);

    Log.trace("Decimal: %lu (%uBit) Binary: %s Tri-State: %s PulseLength: %u microseconds Protocol: %u",
              decimal, length, b, tristate, delay, protocol);

    String tristateCode = String(tristate);
    String switchCode = tristateCode + " " + String(delay) + " " + String(protocol);
    unsigned long timestamp = millis();
    if (timestamp - lastSwitchTimestamp > kSwitchToggleTimeout) {
      Particle.publish("tristate-received", switchCode);
    }
    
    int switchIndex = switchIndexForCode(tristateCode);
    if (switchIndex >= 0 && (switchIndex != lastSwitchIndex || timestamp - lastSwitchTimestamp > kSwitchToggleTimeout)) {
      _setSwitchState(switchIndex, !_getSwitchState(switchIndex));
    }
    lastSwitchIndex = switchIndex;
    lastSwitchTimestamp = timestamp;
  }

  String rawData("Raw data: ");
  for (int i=0; i<= length*2; i++) {
    rawData += raw[i];
    rawData += ",";
  }
  Log.trace(rawData);
}

int sendTristateCode(String command) {
  Log.info("sendTristateCode %s", command.c_str());
  int pos = command.indexOf(' ');
  if (pos < 0) {
    return -1;
  }
  int pos2 = command.indexOf(' ', pos + 1);
  if (pos2 < 0) {
    return -1;
  }
  ELECHOUSE_cc1101.SetTx();
  digitalWrite(ledPin, HIGH);
  String triState = command.substring(0, pos);
  int pulseLength = command.substring(pos+1, pos2).toInt();
  int protocol = command.substring(pos2 + 1).toInt();

  mySwitch.setProtocol(protocol);
  mySwitch.setPulseLength(pulseLength);

  const char* triStateChars = triState.c_str();
  
  Log.info("protocol=%d, pulseLength=%d, tristate=%s", protocol, pulseLength, triStateChars);

  unsigned long begin = micros();
  mySwitch.sendTriState((char *)triStateChars);
  unsigned long elapsed = micros() - begin;
  digitalWrite(ledPin, LOW);
  Log.info("sendTriStateCode in %lu microsecond", elapsed);
  ELECHOUSE_cc1101.SetRx();
  return elapsed;
}

int setSwitchConfig(String switchConfig) {
    JSONValue jsonObj = JSONValue::parseCopy(switchConfig);
    JSONObjectIterator iter(jsonObj);
    int timestamp = 0;
    JSONArrayIterator codesIter;
    while(iter.next()) {
      const char *name = (const char *) iter.name();
      if (strcmp(name, "timestamp") == 0) {
        timestamp = iter.value().toInt();
      } else if (strcmp(name, "codes") == 0) {
        codesIter = JSONArrayIterator(iter.value());
      }
    }
  if (timestamp > gTimestamp) {
    Log.info("Received new switch config timestamp=%d", timestamp);
    gSwitchConfig = switchConfig;
    gTimestamp = timestamp;
    Particle.publish("switchConfigChanged", String(timestamp));
    for(size_t ii = 0; codesIter.next() && ii < kMaxNumberOfSwitches; ii++) {
      const char *switchCode = codesIter.value().toString().data();
      Log.info("switch code %u: %s", ii, switchCode);
      gSwitchCodes[ii] = switchCode;
    }
  }
  return 0;
}

String switchConfig() {
  return gSwitchConfig;
}

unsigned long _toggleSwitch(int switchIndex) {
  Log.info("_toggleSwitch switchIndex=%d", switchIndex);
  if (switchIndex < 0 || switchIndex >= kMaxNumberOfSwitches) {
    return -1;
  }
  unsigned long result = sendTristateCode(gSwitchCodes[switchIndex]);
  if (result <= 0) {
    return -1;
  } 
  return _setSwitchState(switchIndex, !_getSwitchState(switchIndex));
}

int toggleSwitch(String switchIndex) {
  if (switchIndex.length() == 0 || !isdigit(switchIndex.charAt(0))) {
    return -1;
  }
  Log.info("toggleSwitch: %s", switchIndex.c_str());
  return _toggleSwitch(switchIndex.toInt());
}

int turnOnSwitch(String command) {
  if (command.length() == 0 || !isdigit(command.charAt(0))) {
    return -1;
  }
  int switchIndex = command.toInt();
  if (switchIndex < 0 || switchIndex >= kMaxNumberOfSwitches) {
    return -1;
  }
  Log.info("turnOnSwitch: %d", switchIndex);
  if (!_getSwitchState(switchIndex)) {
    _toggleSwitch(switchIndex);
  }
  return 1;
}

int turnOffSwitch(String command) {
  if (command.length() == 0 || !isdigit(command.charAt(0))) {
    return -1;
  }
  int switchIndex = command.toInt();
  if (switchIndex < 0 || switchIndex >= kMaxNumberOfSwitches) {
    return -1;
  }
  Log.info("turnOffSwitch: %d", switchIndex);
  if (_getSwitchState(switchIndex)) {
    _toggleSwitch(switchIndex);
  }
  return 0;
}

String switchesState() {
  String switchState;
  for (int i = 0; i < kMaxNumberOfSwitches; i++) {
    switchState += String(gSwitchState[i]);
    if (i < kMaxNumberOfSwitches - 1) {
      switchState += " ";
    }
  }
  return switchState;
}

int sendTristate(String command) {
  Log.info("sendTristate %s", command.c_str());
  int switchIndex = switchIndexForCode(command);
  if (switchIndex >= 0) {
      return _toggleSwitch(switchIndex);
  }
  return sendTristateCode(command);
}

int setSwitchState(String command) {
  Log.info("setSwitchState %s", command.c_str());
  int pos = command.indexOf(' ');
  if (pos < 0) {
    return -1;
  }
  int switchIndex = command.substring(0, pos).toInt();
  bool isOn = command.substring(pos+1).toInt() != 0;
  if (switchIndex < 0 || switchIndex >= kMaxNumberOfSwitches) {
    return -1;
  }
  return _setSwitchState(switchIndex, isOn);
}

int getSwitchState(String command) {
  Log.info("setSwitchState %s", command.c_str());
  if (command.length() == 0 || !isdigit(command.charAt(0))) {
    return -1;
  }
  int switchIndex = command.toInt();
  if (switchIndex < 0 || switchIndex >= kMaxNumberOfSwitches) {
    return -1;
  }
  return _getSwitchState(switchIndex);
}

ClickButton button(buttonPin, LOW, CLICKBTN_PULLUP);

void setup() {
  Serial.begin(115200);
  Log.info("Cloud Switch started.");

  // Setup button timers (all in milliseconds / ms)
  // (These are default if not set, but changeable for convenience)
  button.debounceTime   = 20;   // Debounce timer in ms
  button.multiclickTime = 250;  // Time limit for multi clicks
  button.longClickTime  = 1000; // time until "held-down clicks" register

  pinMode(inputPin, INPUT_PULLDOWN);
  mySwitch.enableReceive(inputPin);

  pinMode(ledPin, OUTPUT);
  digitalWrite(ledPin, LOW);

  // Transmitter is connected to Spark Core Pin D0
  mySwitch.enableTransmit(outputPin);

  // CC1101 library setup (you need to customize this)
  ELECHOUSE_cc1101.setSpiPin(CC1101_SCLK, CC1101_MISO, CC1101_MOSI, CC1101_CSN);
  ELECHOUSE_cc1101.Init(); 
  ELECHOUSE_cc1101.setMHZ(433.92);
  ELECHOUSE_cc1101.setModulation(2); // Set modulation to ASK/OOK (value varies by library)
  // Ensure the CC1101 is configured to output rx raw signal on GDO2 and input tx raw signal on GDO0
  // This typically involves setting the IOCFG0 register.
  ELECHOUSE_cc1101.SpiWriteReg(CC1101_IOCFG0, 0x2E); // Serial Data Output with HI_Z
  ELECHOUSE_cc1101.SpiWriteReg(CC1101_IOCFG2, 0x0D); // Serial RX Data
  ELECHOUSE_cc1101.setGDO(GDO0_PIN, GDO2_PIN);

  ELECHOUSE_cc1101.SetRx();

  // Register function
  Particle.function("sendtristate", sendTristate);
  Particle.function("setSwitchConfig", setSwitchConfig);
  Particle.function("toggleSwitch", toggleSwitch);
  Particle.function("turnOnSwitch", turnOnSwitch);
  Particle.function("turnOffSwitch", turnOffSwitch);
  Particle.function("setSwitchState", setSwitchState);
  Particle.function("getSwitchState", getSwitchState);

  // Register variable
  Particle.variable("switchConfig", switchConfig);
  Particle.variable("switchState", switchesState);
}

void loop() {
  if (mySwitch.available()) {
    digitalWrite(ledPin, HIGH);
    output(mySwitch.getReceivedValue(), mySwitch.getReceivedBitlength(), mySwitch.getReceivedDelay(), mySwitch.getReceivedRawdata(), mySwitch.getReceivedProtocol());
    mySwitch.resetAvailable();
    delay(50);
    digitalWrite(ledPin, LOW);
  }
    // Update button state
  button.Update();

  int clicks = button.clicks;
  if (clicks < 0) {
    Log.info("LONG CLICK %d", -clicks);
    for (int i = 0; i < min(kMaxNumberOfSwitches, (unsigned)-clicks); i++) {
      unsigned long elapsed = _toggleSwitch(i);
      Log.info("Toggle switch %d takes %lu microseconds.", i+1, elapsed);
      delay(10);
    }
    button.Update();
    button.clicks = 0;
  } else if (clicks > 0 && clicks <= kMaxNumberOfSwitches) {
    Log.info("CLICK %d", clicks);
    unsigned long elapsed = _toggleSwitch(clicks - 1);
    Log.info("Toggle switch %d takes %lu microseconds.", clicks, elapsed);
  }
  delay(5);
}
