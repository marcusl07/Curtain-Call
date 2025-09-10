# Curtain Call

Curtain Call is an iOS app that automatically opens your curtains when your alarm goes off! Using Bluetooth, the app connects to an Arduino Nano powered curtain motor (with an HC-08 Bluetooth sensor), so you wake up to natural light instead of a ringtone.

## Features

- **Bluetooth Curtain Control:** Connects to an Arduino Nano device equipped with an HC-08 Bluetooth sensor and a motor to physically open your curtains.
- **Wake-Up Automation:** Triggers curtain opening as soon as your alarm sounds.
- **Easy Device Discovery:** Scans for and connects to supported curtain controllers.
- **Reliable Motor Activation:** Sends multiple signals to ensure your curtains open every time.
- **SwiftUI Interface:** Simple and intuitive user experience.

## How It Works

- The app scans for Bluetooth devices (e.g., Arduino Nano with HC-08 module).
- When your alarm is triggered, Curtain Call sends a signal to the Arduino Nano (via HC-08) to activate the motor and open the curtains.
- Communication is repeated to ensure the signal is received.

## Requirements
   App:
- iOS device (SwiftUI compatible)
- Xcode (for building from source)
  
   Device:
- Arduino Nano
- HC-08 Bluetooth module
- L9110h motor driver
- 2x PNP power transistors
- ~3Ω and ~100Ω resistor
- ~5V power supply, such as 3x 1.5V AA batteries.
- Motor & winch to control your curtains (connected to the Arduino Nano)
- Gearbox if your motor isn't strong enough
- A box to house the electronics and something to hold the device to the window, like a suction cup.

## Setup

1. Clone the repository:
   ```
   git clone https://github.com/marcusl07/Curtain-Call.git
   ```
2. Open the project in Xcode.
3. Build and run on your iOS device.
4. Set up your Arduino Nano and motor, and connect the HC-08 Bluetooth module following your hardware instructions.

   Hardware schematic:
   <img width="590" height="421" alt="Screenshot 2025-09-10 at 19 21 17" src="https://github.com/user-attachments/assets/3a26d2e3-1b49-48e2-b7b1-b213584c0a56" />


## Usage

1. Launch the Curtain Call app.
2. Tap "Scan" to discover your curtain controller.
3. Connect to your device.
4. Set your alarm in the app.
5. When the alarm goes off, your curtains will open automatically!

## Contributing

Feel free to open issues or submit pull requests to improve the project.

---

For more details and implementation, see [ContentView.swift](https://github.com/marcusl07/Curtain-Call/blob/main/Curtain%20Call/Curtain%20Call/ContentView.swift).
