# Cloud Switch

Cloud Swtich turns a RF 433MHz/315MHz Remote Control Switch Outlet into a Smart Swtich that can be
controlled over internet using cell phone app or Google Assistant.

![Cloud Switch Diagram](docs/Cloud_Switch.png)

## How does it work

1. When user press a button on the Remote Control, the Remote Control will send a radio signal
at the frequency about 433MHz. The signal is used to toggle the switch.
2. The RF receiver module decodes the radio signal and output tristate (H/L/Float) signal on the data pin.
3. Photon reads the output of data pin and convert it into tristate code then publish it to [partical cloud](https://www.particle.io/).
4. The app on the cell phone subscribes to the tristate code then assigns it to a button.
5. Later when user press the button in the app, the app will call the cloud function with the tristate code.
6. Phonon handle the cloud function and send the tristate signal to the data pin of the RF transmitter.
7. RF transmitter convert the tristate code back to the radio signal and toggle the switch.

## Build instructions:

- Follow the README in [photon](./photon/) folder to setup the Photon device then build and flash the firmware.
- Follow the README in [iOS](./iOS/) folder to build the iOS app.

## Switch Configuration Sync.

The latest firmware and iOS app support sync switch configurations between multiple iOS apps and the Cloud Switch device (photon).
If you setup or update the switch configuration in one iOS app for a connected Cloud Switch device, the names and codes assigned to
the buttons will be sent to the connected Cloud Switch. The Cloud Switch will broadcast the configuration to all connected iOS apps.
If a new app log in and reconnected to the Cloud Switch, the switch configuration will be retrieved from the Cloud Switch.
The big black push button on the Cloud Switch board also use the same configuration to toggle switches.


## Integrate with Google Assistant using [IFTTT](https://ifttt.com/)

* Go to [IFTTT](https://ifttt.com/) and create an IFTTT Applet
* Set IF condition to 'Say a simple phrase'. E.g. "Turn on light in family room"
* Set Action to call Particle function. `{"label":"core_function","value":"RemoteSwitch:::sendtristate"}`
* Set Input to the tristate code string. e.g. `1F11FFF00001 165 1`
* Now say the phrase to Google Assistant and the Photon will response and toggle the switch.

![IFTTT Applet](docs/IFTTT_Google_Assistant_Integration.png)

