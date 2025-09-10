import SwiftUI
import CoreBluetooth
import UserNotifications
import AVFoundation
import AudioToolbox

@main
struct ArduinoAlarmApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// MARK: - Bluetooth Manager
class BluetoothManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    @Published var isConnected = false
    @Published var statusMessage = "Initializing Bluetooth..."
    @Published var discoveredDevices: [CBPeripheral] = []
    
    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var targetCharacteristic: CBCharacteristic?
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    func startScanning() {
        guard centralManager.state == .poweredOn else {
            statusMessage = "Waiting for Bluetooth... Current state: \(centralManager.state.rawValue)"
            return
        }
        
        statusMessage = "Scanning for devices..."
        discoveredDevices.removeAll()
        
        // Scan for ALL devices - HC-08 often doesn't advertise services
        centralManager.scanForPeripherals(withServices: nil, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ])
        
        // Stop scanning after 10 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            if !self.isConnected {
                self.centralManager.stopScan()
                self.statusMessage = "Scan complete. Found \(self.discoveredDevices.count) devices."
            }
        }
    }
    
    func connect(to peripheral: CBPeripheral) {
        statusMessage = "Connecting to \(peripheral.name ?? "device")..."
        centralManager.stopScan()
        connectedPeripheral = peripheral
        peripheral.delegate = self
        centralManager.connect(peripheral, options: nil)
    }
    
    func sendAlarmSignal() {
        print("🔵 sendAlarmSignal called")
        
        guard let peripheral = connectedPeripheral else {
            print("❌ No connected peripheral")
            statusMessage = "Not connected to device"
            return
        }
        
        guard let characteristic = targetCharacteristic else {
            print("❌ No target characteristic")
            statusMessage = "No characteristic found"
            return
        }
        
        print("🔵 Peripheral state: \(peripheral.state.rawValue)")
        print("🔵 Characteristic: \(characteristic.uuid)")
        
        // Try to wake up the connection first by reading RSSI
        peripheral.readRSSI()
        
        // Small delay to let the connection wake up
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.sendAlarmData()
        }
    }
    
    private func sendAlarmData() {
        guard let peripheral = connectedPeripheral,
              let characteristic = targetCharacteristic else {
            return
        }
        
        let data = "1".data(using: .utf8)!
        
        // Send the signal multiple times to ensure delivery
        for i in 0..<3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.3) {
                // Use the appropriate write type based on characteristic properties
                if characteristic.properties.contains(.writeWithoutResponse) {
                    print("🔵 Writing without response (attempt \(i + 1))...")
                    peripheral.writeValue(data, for: characteristic, type: .withoutResponse)
                    self.statusMessage = "Sent '1' to Arduino (without response)!"
                    print("✅ Sent data: \(data.map { String($0) }.joined(separator: " ")) (ASCII values)")
                } else if characteristic.properties.contains(.write) {
                    print("🔵 Writing with response (attempt \(i + 1))...")
                    peripheral.writeValue(data, for: characteristic, type: .withResponse)
                    self.statusMessage = "Sent '1' to Arduino (with response)!"
                    print("✅ Sent data: \(data.map { String($0) }.joined(separator: " ")) (ASCII values)")
                } else {
                    self.statusMessage = "❌ Characteristic not writable"
                    print("❌ Characteristic not writable")
                }
            }
        }
    }
    
    // MARK: - CBCentralManagerDelegate
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            statusMessage = "Bluetooth ready"
            startScanning()
        case .poweredOff:
            statusMessage = "Turn on Bluetooth"
        case .unauthorized:
            statusMessage = "Bluetooth not authorized"
        default:
            statusMessage = "Bluetooth unavailable"
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        if !discoveredDevices.contains(peripheral) {
            discoveredDevices.append(peripheral)
            print("Found: \(peripheral.name ?? "Unknown") - RSSI: \(RSSI)")
            
            // Auto-connect if we find HC-08
            if let name = peripheral.name, name.uppercased().contains("HC-08") {
                statusMessage = "Found HC-08! Connecting..."
                connect(to: peripheral)
            }
        }
        statusMessage = "Scanning... Found \(discoveredDevices.count) devices"
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        statusMessage = "Connected! Finding services..."
        isConnected = true
        peripheral.discoverServices(nil)
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        statusMessage = "Disconnected"
        isConnected = false
        connectedPeripheral = nil
        targetCharacteristic = nil
        
        // Try to reconnect after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            self.startScanning()
        }
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        statusMessage = "Connection failed"
        startScanning()
    }
    
    // MARK: - CBPeripheralDelegate
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        
        statusMessage = "Found \(services.count) services"
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        
        let targetUUID = CBUUID(string: "FFE1")
        
        print("=== Service: \(service.uuid) ===")
        for characteristic in characteristics {
            print("Found characteristic: \(characteristic.uuid)")
            
            // Look specifically for FFE1
            if characteristic.uuid == targetUUID {
                targetCharacteristic = characteristic
                let props = characteristic.properties
                print("*** FOUND FFE1! ***")
                print("  - Write: \(props.contains(.write))")
                print("  - WriteWithoutResponse: \(props.contains(.writeWithoutResponse))")
                print("  - Read: \(props.contains(.read))")
                print("  - Notify: \(props.contains(.notify))")
                
                if props.contains(.writeWithoutResponse) {
                    statusMessage = "✅ Ready! FFE1 found (WriteWithoutResponse)"
                } else if props.contains(.write) {
                    statusMessage = "✅ Ready! FFE1 found (Write)"
                } else {
                    statusMessage = "❌ FFE1 found but not writable"
                }
                return
            }
        }
        
        statusMessage = "❌ FFE1 not found in \(service.uuid)"
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("Write error: \(error.localizedDescription)")
            statusMessage = "❌ Write failed: \(error.localizedDescription)"
        } else {
            print("Write successful!")
            statusMessage = "✅ Successfully sent to Arduino!"
        }
    }
}

// MARK: - Alarm Manager
class AlarmManager: ObservableObject {
    @Published var alarmTime = Date()
    @Published var isAlarmSet = false
    @Published var alarmMessage = "No alarm set"
    
    private var timer: Timer?
    private var audioPlayer: AVAudioPlayer?
    var bluetoothManager: BluetoothManager?
    
    init() {
        requestNotificationPermission()
        setupAudioSession()
    }
    
    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
    
    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to setup audio session: \(error)")
        }
    }
    
    private func playAlarmSound() {
        // Try to use Sencha system alert sound first
        if let soundPath = Bundle.main.path(forResource: "/System/Library/Audio/UISounds/New/Sencha_Alert", ofType: "caf") {
            let soundURL = URL(fileURLWithPath: soundPath)
            
            do {
                audioPlayer = try AVAudioPlayer(contentsOf: soundURL)
                audioPlayer?.numberOfLoops = 5 // Play 6 times total
                audioPlayer?.volume = 1.0
                audioPlayer?.play()
                print("Playing Sencha alert sound")
                return
            } catch {
                print("Failed to play Sencha sound: \(error)")
            }
        }
        
        // Fallback to system sound ID for alert
        print("Using fallback system sound")
        let systemSoundID: SystemSoundID = 1005 // System alert sound
        AudioServicesPlaySystemSound(systemSoundID)
    }
    
    private func stopAlarmSound() {
        audioPlayer?.stop()
        audioPlayer = nil
    }
    
    func setAlarm() {
        isAlarmSet = true
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        alarmMessage = "Alarm set for \(formatter.string(from: alarmTime))"
        
        scheduleNotification()
        startTimer()
    }
    
    func cancelAlarm() {
        isAlarmSet = false
        alarmMessage = "Alarm cancelled"
        timer?.invalidate()
        timer = nil
        stopAlarmSound()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
    
    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            self.checkAlarmTime()
        }
    }
    
    private func checkAlarmTime() {
        let calendar = Calendar.current
        let now = Date()
        
        let alarmHour = calendar.component(.hour, from: alarmTime)
        let alarmMinute = calendar.component(.minute, from: alarmTime)
        let alarmSecond = calendar.component(.second, from: alarmTime)
        let nowHour = calendar.component(.hour, from: now)
        let nowMinute = calendar.component(.minute, from: now)
        let nowSecond = calendar.component(.second, from: now)
        
        // Calculate time difference in seconds
        let alarmTimeInSeconds = alarmHour * 3600 + alarmMinute * 60 + alarmSecond
        let nowTimeInSeconds = nowHour * 3600 + nowMinute * 60 + nowSecond
        let timeDifference = alarmTimeInSeconds - nowTimeInSeconds
        
        // Pre-connect 30 seconds before alarm
        if timeDifference == 30 && !bluetoothManager!.isConnected {
            print("🔵 Pre-connecting 30 seconds before alarm...")
            alarmMessage = "🔗 Pre-connecting to device..."
            bluetoothManager?.startScanning()
        }
        
        // Trigger alarm at exact time
        if alarmHour == nowHour && alarmMinute == nowMinute {
            triggerAlarm()
        }
    }
    
    private func triggerAlarm() {
        alarmMessage = "🚨 ALARM! Sending signal..."
        playAlarmSound()
        
        // Send Bluetooth signal only once
        bluetoothManager?.sendAlarmSignal()
        
        // Reset alarm state immediately after sending signal
        isAlarmSet = false
        timer?.invalidate()
        timer = nil
        
        // Cancel alarm after 30 seconds to stop the sound
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            self.stopAlarmSound()
            self.alarmMessage = "Alarm finished"
        }
    }
    
    private func scheduleNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Arduino Alarm"
        content.body = "Time to wake up!"
        content.sound = .default
        
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: alarmTime)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: "alarm", content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request)
    }
    
    func handleNotificationAction() {
        print("Notification action triggered - attempting to send Bluetooth signal")
        bluetoothManager?.sendAlarmSignal()
        DispatchQueue.main.async {
            self.alarmMessage = "🚨 Signal sent from notification!"
        }
    }
}

// MARK: - Notification Delegate
class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()
    weak var alarmManager: AlarmManager?
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        
        switch response.actionIdentifier {
        case "SEND_SIGNAL":
            alarmManager?.handleNotificationAction()
        case UNNotificationDefaultActionIdentifier:
            // User tapped the notification itself
            alarmManager?.handleNotificationAction()
        default:
            break
        }
        
        completionHandler()
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show notification even when app is in foreground
        completionHandler([.alert, .sound, .badge])
    }
}

// MARK: - Main View
struct ContentView: View {
    @StateObject private var bluetoothManager = BluetoothManager()
    @StateObject private var alarmManager = AlarmManager()
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Connection Status
                    VStack(spacing: 10) {
                        HStack {
                            Circle()
                                .fill(bluetoothManager.isConnected ? .green : .red)
                                .frame(width: 12, height: 12)
                            Text("Bluetooth Status")
                                .font(.headline)
                        }
                        
                        Text(bluetoothManager.statusMessage)
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    
                    // Alarm Controls
                    VStack(spacing: 15) {
                        Text("Set Alarm")
                            .font(.headline)
                        
                        DatePicker("Alarm Time",
                                 selection: $alarmManager.alarmTime,
                                 displayedComponents: .hourAndMinute)
                            .datePickerStyle(.wheel)
                            .labelsHidden()
                        
                        Text(alarmManager.alarmMessage)
                            .font(.caption)
                            .foregroundColor(alarmManager.isAlarmSet ? .green : .secondary)
                        
                        HStack(spacing: 15) {
                            Button("Set Alarm") {
                                alarmManager.setAlarm()
                            }
                            .disabled(!bluetoothManager.isConnected || alarmManager.isAlarmSet)
                            .buttonStyle(.borderedProminent)
                            
                            Button("Cancel") {
                                alarmManager.cancelAlarm()
                            }
                            .disabled(!alarmManager.isAlarmSet)
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    
                    // Test Controls
                    VStack(spacing: 10) {
                        Text("Test & Debug")
                            .font(.headline)
                        
                        Button("Send Test Signal") {
                            bluetoothManager.sendAlarmSignal()
                        }
                        .disabled(!bluetoothManager.isConnected)
                        .buttonStyle(.bordered)
                        
                        Button("Refresh Scan") {
                            bluetoothManager.startScanning()
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                }
                .padding()
            }
            .navigationTitle("Curtain Call")
            .onAppear {
                // Connect the alarm manager to bluetooth manager
                alarmManager.bluetoothManager = bluetoothManager
            }
        }
    }
}

#Preview {
    ContentView()
}
