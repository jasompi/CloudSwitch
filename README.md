# Google Assistant controlled Remote Switch

## Remote Control for RF 433MHz RC Outlet Switch using [Particle Photon](https://docs.particle.io/photon/)

The code could support most of the RF 433MHz RC Switch. To setup the switch:

* Build and flash the code to Photon
* Go to [Particle devices console](https://console.particle.io/devices), click on the Photon device and go to the device page. (See screenshot below.)
* Press a button on the Remote Control, the Photon RF receiver wlll decode the RF signal and publish it to the device console.
* Find the tristate-received event and copy the data string. E.g. `1F11FFF10000 162 1`
* Paste the string to the input box for function *f* `sendtristate`, then click the "CALL" button
* When Photon received the function call with the tristate, it will replay the RF signal using the RF transmitter.
* The Switch will toggle when receive the signal.

![Particle Device Console](Particle_Console.png)

## Integrate with Google Assistant using [IFTTT](https://ifttt.com/)

* Go to [IFTTT](https://ifttt.com/) and create an IFTTT Applet
* Set IF condition to 'Say a simple phrase'. E.g. "Turn on light in family room"
* Set Action to call Particle function. `{"label":"core_function","value":"RemoteSwitch:::sendtristate"}`
* Set Input to the tristate data string. e.g. `1F11FFF00001 175 1`
* Now say the phrase to Google Assistant and the Photon will response and toggle the switch.

![IFTTT Applet](IFTTT_Google_Assistant_Integration.png)

## HW setup

[![RF RC Switch](RC_Switch.jpg)](https://www.amazon.com/dp/B0065PASNI/ref=pe_309540_26725410_item)

![Circuit Top](Circuit_Top.png)

![Circuit Front](Circuit_Front.png)

![Circuit Back](Circuit_Back.png)

