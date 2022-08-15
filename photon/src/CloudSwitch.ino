#include "RCSwitch.h"
#include "clickButton.h"

SerialLogHandler logHandler;

RCSwitch mySwitch = RCSwitch();
int outputPin = D0;
int buttonPin = D2;
int inputPin = D3;
int ledPin = D7;

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

    Particle.publish("tristate-received",
        String(tristate) + " " + String(delay) + " " + String(protocol));
  }

  String rawData("Raw data: ");
  for (int i=0; i<= length*2; i++) {
    rawData += raw[i];
    rawData += ",";
  }
  Log.trace(rawData);
}

unsigned long sendTristate(String command) {
  Log.info("sendtristate %s", command.c_str());
  digitalWrite(ledPin, HIGH);
  int pos = command.indexOf(' ');
  if (pos < 0) {
    return 0;
  }
  int pos2 = command.indexOf(' ', pos + 1);
  if (pos2 < 0) {
    return 0;
  }
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
  return elapsed;
}

static String gSwitchConfig = "{}";
static int gTimestamp = 0;
static const size_t kMaxNumberOfSwitches = 5;
static String gSwitchCodes[kMaxNumberOfSwitches];

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
  mySwitch.enableTransmit(D0);

  // Register function
  Particle.function("sendtristate", sendTristate);
  Particle.function("setSwitchConfig", setSwitchConfig);

  // Register variable
  Particle.variable("switchConfig", switchConfig);
}

void loop() {
  if (mySwitch.available()) {
    digitalWrite(ledPin, HIGH);
    output(mySwitch.getReceivedValue(), mySwitch.getReceivedBitlength(), mySwitch.getReceivedDelay(), mySwitch.getReceivedRawdata(), mySwitch.getReceivedProtocol());
    mySwitch.resetAvailable();
    delay(300);
    digitalWrite(ledPin, LOW);
  }
    // Update button state
  button.Update();

  int clicks = button.clicks;
  if (clicks < 0) {
    Log.info("LONG CLICK %d", -clicks);
    for (int i = 0; i < min(kMaxNumberOfSwitches, (unsigned)-clicks); i++) {
      unsigned long elapsed = sendTristate(gSwitchCodes[i]);
      Log.info("Toggle switch %d takes %lu microseconds.", i+1, elapsed);
      delay(10);
    }
    button.Update();
    button.clicks = 0;
  } else if (clicks > 0 && clicks <= kMaxNumberOfSwitches) {
    Log.info("CLICK %d", clicks);
    unsigned long elapsed = sendTristate(gSwitchCodes[clicks - 1]);
    Log.info("Toggle switch %d takes %lu microseconds.", clicks, elapsed);
  }
  delay(5);
}
