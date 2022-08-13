#include "RCSwitch.h"
#include "clickButton.h"

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
    Serial.println("Unknown encoding.");
  } else {
    char* b = mySwitch.dec2binWzerofill(decimal, length);
    char* tristate = bin2tristate(b);

    Serial.printlnf("Decimal: %lu (%uBit) Binary: %s Tri-State: %s PulseLength: %u microseconds Protocol: %u",
                    decimal, length, b, tristate, delay, protocol);

    Particle.publish("tristate-received",
        String(tristate) + " " + String(delay) + " " + String(protocol));
  }

  Serial.print("Raw data: ");
  for (int i=0; i<= length*2; i++) {
    Serial.print(raw[i]);
    Serial.print(",");
  }
  Serial.println();
  Serial.println();
}

// Switch 1: 1F11FFF00001 165 1
// Switch 2: 1F11FFF00010 165 1
// Switch 3: 1F11FFF00100 165 1
// Switch 4: 1F11FFF01000 165 1
// Switch 5: 1F11FFF10000 165 1

static const char* kSwitchCodes[] {
  "1F11FFF00001 165 1",
  "1F11FFF00010 165 1",
  "1F11FFF00100 165 1",
  "1F11FFF01000 165 1",
  "1F11FFF10000 165 1",
};

const size_t kNumOfSwitches = sizeof(kSwitchCodes)/sizeof(kSwitchCodes[0]);

unsigned long sendTristate(String command) {
  digitalWrite(ledPin, HIGH);
  int pos = command.indexOf(' ');
  int pos2 = command.indexOf(' ', pos + 1);
  String triState = command.substring(0, pos);
  int pulseLength = command.substring(pos+1, pos2).toInt();
  int protocol = command.substring(pos2 + 1).toInt();

  mySwitch.setProtocol(protocol);
  mySwitch.setPulseLength(pulseLength);

  char triStateChars[triState.length() + 1];
  triState.toCharArray(triStateChars, triState.length() + 1);
  triStateChars[triState.length()] = '\0';

  Serial.println(protocol);
  Serial.println(pulseLength);
  Serial.println(triStateChars);

  unsigned long begin = micros();
  mySwitch.sendTriState(triStateChars);
  unsigned long elapsed = micros() - begin;
  digitalWrite(ledPin, LOW);
  return elapsed;
}

ClickButton button(buttonPin, LOW, CLICKBTN_PULLUP);

void setup() {
  Serial.begin(115200);
  Serial.println("Listening");

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
    Serial.printlnf("LONG CLICK %d", -clicks);
    for (int i = 0; i < min(kNumOfSwitches, (unsigned)-clicks); i++) {
      unsigned long elapsed = sendTristate(kSwitchCodes[i]);
      Serial.printlnf("Toggle switch %d takes %lu microseconds.", i+1, elapsed);
      delay(10);
    }
    button.Update();
    button.clicks = 0;
  } else if (clicks > 0 && clicks <= kNumOfSwitches) {
    Serial.printlnf("CLICK %d", clicks);
    unsigned long elapsed = sendTristate(kSwitchCodes[clicks - 1]);
    Serial.printlnf("Toggle switch %d takes %lu microseconds.", clicks, elapsed);
  }
  delay(5);
}
