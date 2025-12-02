//
//  BLECentralViewController.swift
//  Based on https://github.com/adafruit/Basic-Chat (MIT License)
//  Copyright (c) 2017 Trevor Beaton for Adafruit Industries
//  Copyright (c) 2019 Mobilinkd LLC
//

import CoreBluetooth
import Foundation
import UIKit

var txCharacteristic: CBCharacteristic?
var rxCharacteristic: CBCharacteristic?
var otaFlashCharacteristic: CBCharacteristic?
var otaIdentityCharacteristic: CBCharacteristic?
var blePeripheral: CBPeripheral?
var characteristicASCIIValue = String()

extension Data {
  struct HexEncodingOptions: OptionSet {
    let rawValue: Int
    static let upperCase = HexEncodingOptions(rawValue: 1 << 0)
  }

  func hexEncodedString(options: HexEncodingOptions = []) -> String {
    let format = options.contains(.upperCase) ? "%02hhX" : "%02hhx"
    return map { String(format: format, $0) }.joined()
  }
}

extension String {
  var localized: String {
    return NSLocalizedString(self, tableName: nil, bundle: Bundle.main, value: "", comment: "")
  }
}

extension Notification.Name {
  static let bleDataReceived = Notification.Name(
    "bleDataReceived")
  static let bleDataSendRequest = Notification.Name(
    "bleDataSendRequest")
  static let bleDisconnected = Notification.Name(
    "bleDisconnected")
  static let bleDisconnectRequest = Notification.Name(
    "bleDisconnectRequest")

}

class BLECentralViewController: UIViewController, CBCentralManagerDelegate,
  CBPeripheralDelegate, UITableViewDelegate, UITableViewDataSource
{
  let indicator: UIActivityIndicatorView = UIActivityIndicatorView(
    style: UIActivityIndicatorView.Style.medium)

  //Data
  var centralManager: CBCentralManager!
  var RSSIs = [NSNumber]()
  var data = NSMutableData()
  var writeData: String = ""
  var peripherals: [CBPeripheral] = []
  var characteristicValue = [CBUUID: NSData]()
  var timer = Timer()
  var characteristics = [String: CBCharacteristic]()

  //UI
  @IBOutlet weak var baseTableView: UITableView!
  @IBOutlet weak var refreshButton: UIBarButtonItem!

  @IBAction func refreshAction(_ sender: AnyObject) {
    disconnectFromDevice()
    self.peripherals = []
    self.RSSIs = []
    self.baseTableView.reloadData()
    startScan()
  }

  @IBAction func unwindToBleCentral(segue: UIStoryboardSegue) {
    //nothing goes here
  }

  override func viewDidLoad() {
    print("BLECentralViewController.viewDidLoad")

    super.viewDidLoad()
    self.baseTableView.delegate = self
    self.baseTableView.dataSource = self
    self.baseTableView.reloadData()

    // The key player in this app is the CBCentralManager. CBCentralManager
    // objects are used to manage discovered or connected remote peripheral
    // devices (represented by CBPeripheral objects), including scanning
    // for, discovering, and connecting to advertising peripherals.

    centralManager = CBCentralManager(delegate: self, queue: nil)
    let backButton = UIBarButtonItem(
      title: "Disconnect", style: .plain, target: nil, action: nil)
    navigationItem.backBarButtonItem = backButton

    indicator.frame = CGRect(x: 0.0, y: 0.0, width: 80.0, height: 80.0)
    indicator.center = view.center
    view.addSubview(indicator)
    indicator.bringSubviewToFront(view)
  }

  override func viewDidAppear(_ animated: Bool) {
    disconnectFromDevice()
    self.peripherals = []
    self.RSSIs = []
    self.baseTableView.reloadData()
    super.viewDidAppear(animated)
    startScan()
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    print("Stop Scanning")
    centralManager?.stopScan()
  }

  /*
     * Now that the CBCentalManager exists, it's time to start searching for
     * devices. You can do this by calling the "scanForPeripherals" method.
     */
  func startScan() {
    peripherals = []

    print("Now Scanning...")
    self.timer.invalidate()
    centralManager?.scanForPeripherals(
      withServices: [BLEService_UUID],
      options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    Timer.scheduledTimer(
      timeInterval: 17, target: self, selector: #selector(self.cancelScan), userInfo: nil,
      repeats: false)
  }

  /*We also need to stop scanning at some point so we'll also create a function that calls "stopScan"*/
  @objc func cancelScan() {
    self.centralManager?.stopScan()
    print("BLE Scan Stopped")
    print("Number of Peripherals Found: \(peripherals.count)")
  }

  func refreshScanView() {
    baseTableView.reloadData()
  }

  //-Terminate all Peripheral Connection
  /*
     Call this when things either go wrong, or you're done with the connection.
     This cancels any subscriptions if there are any, or straight disconnects if not.
     (didUpdateNotificationStateForCharacteristic will cancel the connection if a subscription is involved)
     */
  func disconnectFromDevice() {
    if blePeripheral != nil {
      // Disable notification first.
      blePeripheral!.setNotifyValue(false, for: rxCharacteristic!)
      // Then request device disconnection.
      centralManager?.cancelPeripheralConnection(blePeripheral!)
    }
  }

  func restoreCentralManager() {
    //Restores Central Manager delegate if something went wrong
    centralManager?.delegate = self
  }

  /*
     Called when the central manager discovers a peripheral while scanning. Also, once peripheral is connected, cancel scanning.
     */
  func centralManager(
    _ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
    advertisementData: [String: Any], rssi RSSI: NSNumber
  ) {

    // It seems we get duplicates -- don't know why yet.  Filter them.
    var index = 0
    for aPeripheral in self.peripherals {
      if peripheral.identifier == aPeripheral.identifier {
        self.RSSIs[index] = RSSI
        refreshScanView()
        print("skipping already known peripheral: \(String(describing: peripheral.name))")
        return
      }
      index += 1
    }

    self.peripherals.append(peripheral)
    self.RSSIs.append(RSSI)
    peripheral.delegate = self
    self.baseTableView.reloadData()

    print("Found new pheripheral devices with services")
    print("Peripheral name: \(String(describing: peripheral.name))")
    print("**********************************")
    print("Advertisement Data : \(advertisementData)")
  }

  //Peripheral Connections: Connecting, Connected, Disconnected

  //-Connection
  func connectToDevice(_ device: CBPeripheral) {
    indicator.startAnimating()
    FirmwareUpdater.shared.reset()
    centralManager?.connect(device, options: nil)
  }

  /*
     Invoked when a connection is successfully created with a peripheral.
     This method is invoked when a call to connect(_:options:) is successful. You typically implement this method to set the peripheral’s delegate and to discover its services.
     */
  //-Connected
  func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    print("Connection complete")
    print("Peripheral info: \(String(describing: peripheral))")
    //Stop Scan- We don't need to scan once we've connected to a peripheral. We got what we came for.
    centralManager?.stopScan()
    print("Scan Stopped")
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(self.disconnectAllConnection),
      name: .bleDisconnectRequest,
      object: nil)

    //Erase data that we might have
    data.length = 0
    blePeripheral = peripheral
    //Discovery callback
    peripheral.delegate = self
    //Only look for services that matches transmit uuid
    peripheral.discoverServices([BLEService_UUID, BLEServiceOTAUUID])
  }

  @objc func bleSend(notification: NSNotification) {
    print("bleSend")
    if let data = notification.object as? Data {
      print("sending: \((data.hexEncodedString() as String))")
      if blePeripheral != nil 
      {
        blePeripheral!.writeValue(
          data, for: txCharacteristic!,
          type: CBCharacteristicWriteType.withoutResponse)
      }
    }
  }

  /*
     Invoked when the central manager fails to create a connection with a peripheral.
     */

  func centralManager(
    _ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?
  ) {
    indicator.stopAnimating()
    if error != nil {
      print("Failed to connect to peripheral")
      return
    }
  }

  @objc func disconnectAllConnection() {
    if blePeripheral != nil {
      print("disconnectAllConnection")
      centralManager.cancelPeripheralConnection(blePeripheral!)
      blePeripheral = nil
    }
  }

  /*
     Invoked when you discover the peripheral’s available services.
     This method is invoked when your app calls the discoverServices(_:) method. If the services of the peripheral are successfully discovered, you can access them through the peripheral’s services property. If successful, the error parameter is nil. If unsuccessful, the error parameter returns the cause of the failure.
     */
  func peripheral(
    _ peripheral: CBPeripheral,
    didDiscoverServices error: Error?
  ) {
    if (error) != nil {
      print("Error discovering services: \(error!.localizedDescription)")
      return
    }

    guard let services = peripheral.services else {
      return
    }

    for service in services {
      peripheral.discoverCharacteristics(nil, for: service)
    }
    print("Discovered Services: \(services)")
  }

  /*
     Invoked when you discover the characteristics of a specified service.
     This method is invoked when your app calls the discoverCharacteristics(_:for:) method. If the characteristics of the specified service are successfully discovered, you can access them through the service's characteristics property. If successful, the error parameter is nil. If unsuccessful, the error parameter returns the cause of the failure.
     */
  func peripheral(
    _ peripheral: CBPeripheral,
    didDiscoverCharacteristicsFor service: CBService,
    error: Error?
  ) {
    if (error) != nil {
      print("Error discovering services: \(error!.localizedDescription)")
      return
    }

    guard let characteristics = service.characteristics else {
      return
    }

    print("Found \(characteristics.count) characteristics!")

    for characteristic in characteristics {
      if characteristic.uuid.isEqual(BLE_Characteristic_uuid_Rx) {
        rxCharacteristic = characteristic
        peripheral.setNotifyValue(true, for: rxCharacteristic!)
        print("Rx Characteristic: \(characteristic.uuid)")
      }

      if characteristic.uuid.isEqual(BLE_Characteristic_uuid_Tx) {
        txCharacteristic = characteristic
        print("Tx Characteristic: \(characteristic.uuid)")
      }

      if characteristic.uuid.isEqual(BLECharacteristicOTAFlashUUID) {
        otaFlashCharacteristic = characteristic
        print("OTA Flash Characteristic: \(characteristic.uuid)")
      }

      if characteristic.uuid.isEqual(BLECharacterisitcOTAIdentityUUID) {
        otaIdentityCharacteristic = characteristic
        // Read identity characteristic to get the current version
        peripheral.readValue(for: otaIdentityCharacteristic!)
        print("OTA Identity Characteristic: \(characteristic.uuid)")
      }
    }
  }

  func peripheral(
    _ peripheral: CBPeripheral,
    didUpdateValueFor characteristic: CBCharacteristic, error: Error?
  ) {
    if error != nil {
      print("\(error.debugDescription)")
      return
    }

    if characteristic == rxCharacteristic {
      if let data = characteristic.value {
        characteristicASCIIValue = data.hexEncodedString()
        print("Value Received: \((characteristicASCIIValue as String))")
        NotificationCenter.default.post(
          name: .bleDataReceived,
          object: data)
      }
    }

    if characteristic == otaIdentityCharacteristic {
      if let data = characteristic.value {
        print("OTA Identity: \(data.hexEncodedString())")

        guard let url = FirmwareUpdater.shared.urlForBoard(boardId: data[0]) else {
          print("No firmware available for this board")
          FirmwareUpdater.shared.reset()
          return
        }

        print("Firmware URL: \(url)")
        // The version is in the last 3 bytes of the value. Format as "major.minor.patch"
        let localVersion =
          "\(data[data.count - 3]).\(data[data.count - 2]).\(data[data.count - 1])"
        print("Local version: \(localVersion)")
        FirmwareUpdater.shared.checkForFirmwareUpdate(
          url: url,
          localVersion: localVersion)
      }
    }
  }

  func peripheral(
    _ peripheral: CBPeripheral,
    didUpdateNotificationStateFor characteristic: CBCharacteristic,
    error: Error?
  ) {
    indicator.stopAnimating()

    guard error == nil else {
      print("Error changing notification state:\(String(describing: error?.localizedDescription))")
      return
    }

    if characteristic.isNotifying {
      print("Subscribed. Notification has begun for: \(characteristic.uuid)")
      print(
        "Using a negotiated MTU of: \(peripheral.maximumWriteValueLength(for: .withoutResponse))")

      // Only move to the next scene after notification registration is complete.
      let storyboard = UIStoryboard(name: "Main", bundle: nil)

      let menuViewController =
        storyboard.instantiateViewController(withIdentifier: "TncConfigMenuViewController")
        as! TncConfigMenuViewController

      menuViewController.peripheral = peripheral

      NotificationCenter.default.addObserver(
        self,
        selector: #selector(self.bleSend),
        name: .bleDataSendRequest,
        object: nil)
      print("bleSend notifications subscribed")

      navigationController?.pushViewController(menuViewController, animated: true)
    }
  }

  func centralManager(
    _ central: CBCentralManager,
    didDisconnectPeripheral peripheral: CBPeripheral, error: Error?
  ) {
    print("Disconnected")

    if error != nil {
      print("didDisconnectPeripheral: \(error.debugDescription)")
    }

    NotificationCenter.default.post(
      name: .bleDisconnected,
      object: nil)
    blePeripheral = nil
    NotificationCenter.default.removeObserver(
      self, name: .bleDataSendRequest, object: nil)
    NotificationCenter.default.removeObserver(
      self, name: .bleDisconnectRequest, object: nil)
    indicator.stopAnimating()
    print("bleSend notifications unsubscribed")
  }

  func peripheral(
    _ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?
  ) {
    guard error == nil else {
      print("Error discovering services: error")
      return
    }
  }

  func peripheral(
    _ peripheral: CBPeripheral, didWriteValueFor descriptor: CBDescriptor, error: Error?
  ) {
    guard error == nil else {
      print("Error discovering services: error")
      return
    }
  }

  //Table View Functions
  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    return self.peripherals.count
  }

  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    //Connect to device where the peripheral is connected
    let cell = tableView.dequeueReusableCell(withIdentifier: "BlueCell") as! PeripheralTableViewCell
    let peripheral = self.peripherals[indexPath.row]
    let RSSI = self.RSSIs[indexPath.row]

    if peripheral.name == nil {
      cell.peripheralLabel.text = "nil"
    } else {
      cell.peripheralLabel.text = peripheral.name
    }
    if Int(truncating: RSSI) == 100 {
      cell.rssiLabel.text = "Last Connected Device".localized
    } else {
      cell.rssiLabel.text = "RSSI:".localized + " \(RSSI)"
    }

    return cell
  }

  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    let device = peripherals[indexPath.row]
    self.connectToDevice(device)
  }

  func unauthorized() {
    print("Bluetooth not authorized - this app must be authorized for Bluetooth")

    let alertVC = UIAlertController(
      title: "BTAuthTitle".localized, message: "BTAuthMessage".localized,
      preferredStyle: UIAlertController.Style.alert)
    let action = UIAlertAction(
      title: "ok", style: UIAlertAction.Style.default,
      handler: { (action: UIAlertAction) -> Void in
        self.dismiss(animated: true, completion: nil)
      })
    alertVC.addAction(action)
    self.present(alertVC, animated: true, completion: nil)
  }

  func poweredOff() {
    print("Bluetooth is not powered on - Bluetooth must be powered on to use this app")

    let alertVC = UIAlertController(
      title: "BTEnableTitle".localized, message: "BTEnableMessage".localized,
      preferredStyle: UIAlertController.Style.alert)
    let action = UIAlertAction(
      title: "ok", style: UIAlertAction.Style.default,
      handler: { (action: UIAlertAction) -> Void in
        self.dismiss(animated: true, completion: nil)
      })
    alertVC.addAction(action)
    self.present(alertVC, animated: true, completion: nil)
  }

  /*
     Invoked when the central manager’s state is updated.
     This is where we kick off the scan if Bluetooth is turned on.
     */
  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    switch central.state {
    case .unauthorized:
      print("This app is not authorized to use Bluetooth low energy")
      unauthorized()
    case .poweredOff:
      print("Bluetooth is currently powered off.")
      poweredOff()
    case .poweredOn:
      print("Bluetooth Enabled")
      startScan()
    default: break
    }
  }
}
