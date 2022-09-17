# Cloud Switch Hub Setup

## HW Setup

You can use Particle [Photon](https://store.particle.io/collections/wifi/products/photon)
or [Argon](https://store.particle.io/collections/wifi/products/argon).
Both 433MHz and 315MHz RF remoted control switches can be supported. 
The RF transmitter and receiver can be purchased from 
[ebay](https://www.ebay.com/sch/i.html?_from=R40&_trksid=p2334524.m570.l1313&_nkw=315+433+mhz+rf+transmitter+and+receiver+with+antenna&_sacat=0&LH_TitleDesc=0&_odkw=433+mhz+rf+transmitter+and+receiver+with+antenna&_osacat=0&LH_PrefLoc=2).

- 3.3v conntect to VCC/BAT/+ of transmitter and receiver
- GND connect to GND/- of transmitter and receiver
- D0 connect to the Data Pin of transmitter
- D3 connect to the Data Pin of receiver

Push Button is optional.

- D2 connect to pin on one end of the  button.
- GND connect to pin on the other end of the button.

Refer to the [HW pictures](#hw-pictures) below.

## Photon Setup

Follow the instructions at [Connect Your Photon](https://docs.particle.io/quickstart/photon/#connect-your-photon)
to setup the devices. You need to sign up for a partile.io account and claim the device and set a name to the device.
The name will be used in the [Configure for Device](#build-and-flash) step below.

## Install IDE

Follow the instructions at [Quick start: Workbench](https://docs.particle.io/quickstart/workbench/)
to install the IDE (VS Code + Particle Workbench).

## Build and flash

- Open the projects.
- Open Particle Workbench and click "Login" to login to Particle account.
- Click "Configure for Device" under Development Workflow -> TARGET
- Choose deviceOS@3.3.0 -> photon then input the name of the device
- Click "Local compile" to compile the code. 
  (Cloud compilation will fail due to error in the RCSwitch library which is fixed locally.)
- Connect the photon over USB, click "Local flash". The LED on Photon will blinking then breath.

## Try it

- Press any button on the Remote Control, the blue LED will light up for a second. 
  This indicates a RF code is received and the FW is working correctly. 
- Go to [Particle devices console](https://console.particle.io/devices), click on the Photon device and go to the device page. (See screenshot below.)
- Press a button on the Remote Control, the Photon RF receiver wlll decode the RF signal into tristate code and publish it to the device console.
- Find the tristate-received event and copy the data string. E.g. `1F11FFF10000 162 1`
- Paste the tristate code string to the input box for function *f* `sendtristate`, then click the "CALL" button
- When Photon received the function call with the tristate code, it will replay the RF signal using the RF transmitter.
- The Switch will toggle when receive the signal.

![Particle Device Console](../docs/Particle_Console.png)

Now you can run the [Cloud Swtich iOS app](../ios) to setup and control the Cloud Swtiches using your phone.

## Button Control

The big black button on the breadboard can be used to toggle the switches. After you assign the tristate
codes to the buttons in the iOS app, the configuration for the five buttons will be sent to the photons.
If you click the button, Cloud Switch will send the tristate code to toggle the switch same as you press the button
in the phone app. Single click the button toggle the first switch, double click toggle the second switch,
triple click toggle the third switch, etc. If the N click then hold, it will toggle the first n switches.
E.g. click, click, hold will toggle the first 3 switches.

## Switch Configuration

The following Particle Cloud Functions are used to support configure the Cloud Switch Hub:

- `tristate-received`: 

  Event published when Photon detect a RF signal. 
  
  e.g. `tristate-received "1F11FFF00001 165 1"`
  
- `setSwitchConfig`: 

  Cloud function to set the configuration for switches. Switch configuration is a JSON contains name and code of
  switches and a timestamp. The switch configuration is only updated if the received timestamp is newer than the
  current configuration timestamp
  
  e.g. ` {"names":["Family Room","Living Room","Switch 3","Switch 4","Chrismas Tree"],"codes":["1F11FFF00001 166 1","1F11FFF00010 166 1","1F11FFF00100 166 1","1F11FFF01000 166 1","1F11FFF10000 165 1"],"timestamp":1660583150}`
  
- `switchConfig`:
 
  Cloud variable to retrieve the switch configuration in JSON.

- `switchConfigChanged`: 
  
  Event published when switch configuration is updated. The new timestamp is included in the event data.
  e.g. `switchConfigChanged 1660583150`

## Switch State tracking

The RF controlled Switch can only recieve the RF signal to toggle the switch. There is no way to retrieve the 
current on/off state of the switch. To support state traking, the user need to manually sync the initial on/off
state of the switch with the state keep tracked by Photon. After that, the photon can update the state based on
the RF signal it received and sent. However if the switch is turn on/off manually on the switch, the state will
out of sync. The following Cloud Functions can be used to turn on/off switches and sync switch state.

### Cloud functions

These cloud function will return the new state for the switch. 0: OFF; 1: ON; -1: the input is invalid or switchIndex out of range. 

- `setSwitchState <switchIndex> <new switch state>`

  Set the switch state to the new state without send switch code (RF signal) to the switch. Use to sync the switch state.
  
- `getSwitchState <switchIndex>`

  Get the current switch state.
  
- `turnOnSwitch <switchIndex>`

  Send RF signal to the switch and update the state to ON if the current state is OFF.

- `turnOffSwitch <switchIndex>`

  Send RF signal to the switch and update the state to OFF if the current state is OFF.
  
- `toggleSwitch <switchIndex>`

  Send RF signal to the switch and update the state.

- `sendtristate <tristatecode>`

  This can be used to send RF single for the code passed in. If the tristatecode match any code in
  switch configuration, the switch state will still get updated. If the code doesn't match any configuration,
  the code will be send as is.

### Cloud variable

- `switchState`

  Return the state of all switches as a string seperated by space . E.g. `1 0 0 0 0`
  
### Event

- `switchStateChanged`

  Published when a switch's state is changed. The data is index of the switch and the new state.
  E.g. `0 1` when switch 0 is turned on.


## Dependency:

- [RCSwitch](https://github.com/suda/rcswitch)
- [clickButton](https://github.com/pkourany/clickButton)


<a name="hw-pictures"></a>
## HW pictures

![Circuit Top](../docs/Circuit_Top.png)

![Circuit Front](../docs/Circuit_Front.png)

![Circuit Back](../docs/Circuit_Back.png)

