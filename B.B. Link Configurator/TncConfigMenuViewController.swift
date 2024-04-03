//
//  TncConfigMenuViewControllerTableViewController.swift
//  Mobilinkd TNC Config
//
//  Created by Rob Riggs on 12/29/18.
//  Copyright © 2018 Mobilinkd LLC. All rights reserved.
//
//  Adapted for B.B. Link adapter 01/18/24
//

import CoreBluetooth
import Eureka
import JGProgressHUD
import UIKit

struct BTDevice {
  var connected: Bool?
  var address: ESPBDAddress?
  var name: String
}
extension BTDevice: Hashable, Equatable {}

extension Notification.Name {
  static let tncApiVersionReceived = Notification.Name(
    "tncApiVersionReceived")
}

class TncConfigMenuViewController: FormViewController {

  var peripheral: CBPeripheral?
  // SlipProtocolDecoder maintains state to handle packets that are split
  // across multiple MTU blocks.
  var slipDecoder = SlipProtocolDecoder()

  // TNC Information
  var firmwareVersion: String?
  var capabilities: Capabilities?
  var apiVersion: UInt16?

  // Last known api version.
  let knownApiVersion = 0x0100

  // Bluetooth Classic devices found
  var devicesFound: [ESPBDAddress: BTDevice] = [:]
  var pairedDevice: BTDevice?

  var firmwareFlashingProgress: Progress = Progress()
  var hud: JGProgressHUD = JGProgressHUD()
  var progressObservation: NSKeyValueObservation?

  required init?(coder aDecoder: NSCoder) {
    super.init(coder: aDecoder)
  }

  override func viewDidLoad() {
    print("TncConfigMenuViewController.viewDidLoad")
    super.viewDidLoad()

    var optionsTimer: Timer?
    
    form
      +++ Section(
        footer:
          "Before pairing, make your radio discoverable by selecting Menu > Configuration > Bluetooth > Pairing Mode (934). To pair with a different radio, reset the adapter to start over."
      )
      <<< PushRow<BTDevice> { row in
        row.tag = "pairedRadioTag"
        row.title = self.pairedDevice == nil ? "Pair Radio" : "Paired Radio"
        row.selectorTitle = "Discovering Nearby Radios..."
        row.options = []
        row.disabled = Condition.function(
          ["pairedRadioTag"],
          { [weak self] form in
              return self?.pairedDevice != nil || row.value != nil
          })
        row.optionsProvider = .lazy({ [weak self] (form, completion) in
          let activityView = UIActivityIndicatorView(style: .medium)
          form.tableView.backgroundView = activityView
          activityView.startAnimating()

          optionsTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.devicesFound.isEmpty {
              return
            }
              optionsTimer?.invalidate()

              NotificationCenter.default.post(
                name: .bleDataSendRequest,
                object: KissPacketEncoder.StopScan())
              print("sent StopScan to TNC")
              
              DispatchQueue.main.async {
              form.tableView.backgroundView = nil
              let options = Array(self.devicesFound.values)
              completion(options)
            }
          }
        })
      }.onChange { [weak self] row in
        print("onChange paired value \(row.value?.name ?? "None")")
        row.title = self?.pairedDevice == nil ? "Pair Radio" : "Paired Radio"

        if row.value != nil && self?.pairedDevice != row.value {
          print("Pairing with radio: \(row.value!.name)")
          if let address = row.value?.address {
            print("Address:", address.stringRepresentation)
              
            row.title = "Paired Radio"

            NotificationCenter.default.post(
              name: .bleDataSendRequest,
              object: KissPacketEncoder.PairWithDevice(address: address))
            print("sent PairWithDevice to TNC")
              
              let alert = UIAlertController(
              title: "Confirm Pairing",
              message: "On the radio, press OK to confirm pairing.",
              preferredStyle: .alert)
              alert.addAction(
              UIAlertAction(
                title: "Done", style: .default,
                handler: nil))
              
              DispatchQueue.main.async {
                self?.present(alert, animated: true)
              }

          }
        }
      }.onPresent { [weak self] from, to in
        self?.devicesFound.removeAll()
        NotificationCenter.default.post(
          name: .bleDataSendRequest,
          object: KissPacketEncoder.ClearPairedDevice())


        let alert = UIAlertController(
        title: "Bluetooth Pairing Mode",
        message: "Make your radio discoverable by selecting Menu > Configuration > Bluetooth > Pairing Mode (934)",
        preferredStyle: .alert)
        alert.addAction(
        UIAlertAction(
          title: "OK", style: .default,
          handler: { action in
              NotificationCenter.default.post(
                name: .bleDataSendRequest,
                object: KissPacketEncoder.StartScan())
              print("sent StartScan to TNC")

          }))
        
        DispatchQueue.main.async {
          self?.present(alert, animated: true)
        }
          
        to.selectableRowCellUpdate = { (cell, row) in
          cell.textLabel?.text = row.selectableValue?.name
        }
          
        to.onDismissCallback = { vc in
          NotificationCenter.default.post(
            name: .bleDataSendRequest,
            object: KissPacketEncoder.StopScan())
          print("sent StopScan to TNC")
          _ = vc.navigationController?.popViewController(animated: true)
        }
      }.cellUpdate { cell, row in
        cell.detailTextLabel?.text = row.value?.name
      }

      +++ Section(
        header: "Advanced",
        footer:
          "Allow apps to control the radio frequency and mode, or turn off for manual operation.")
      <<< SwitchRow { row in
        row.tag = "useRigCtrlTag"
        row.title = "Allow Radio Control"
        row.value = true
      }.onChange { row in
        print("useRigCtrl \(row.value)")
        NotificationCenter.default.post(
          name: .bleDataSendRequest,
          object: KissPacketEncoder.SetRigCtrl(value: row.value ?? true))
      }
      +++ Section()
      <<< LabelRow { row in
        row.title = "Adapter Name"
        row.value = peripheral?.name!
      }
      <<< LabelRow { row in
        row.tag = "firmwareVersionRowTag"
        row.title = "Firmware Version"
        row.value = firmwareVersion
      }
      <<< ButtonRow { row in
        row.tag = "updateFirmwareTag"
        row.title = "Update Firmware"
        row.disabled = Condition(booleanLiteral: !FirmwareUpdater.shared.newVersionAvailable)
      }.onCellSelection { [weak self] (cell, row) in
        if !row.isDisabled {
          let newVersion = FirmwareUpdater.shared.newVersion ?? "N/A"
          let alert = UIAlertController(
            title: "Update Firmware to \(newVersion)",
            message:
              "Please make sure your phone and the adapter stay connected and turned on for the duration of the update. The update should take roughly 3 minutes, after which the adapter will restart on its own.\n\nProceed with update now?",
            preferredStyle: .alert)
          alert.addAction(
            UIAlertAction(
              title: "OK".localized, style: .default,
              handler: { action in
                print("Updating adapter")
                self?.performFlashUpdate()
              }))
          alert.addAction(UIAlertAction(title: "Cancel".localized, style: .default, handler: nil))
          self?.present(alert, animated: true, completion: nil)
        }
      }
      +++ Section()
      <<< ButtonRow { row in
        row.tag = "factoryResetTag"
        row.title = "Reset Adapter"
      }.onCellSelection { [weak self] (cell, row) in
        let alert = UIAlertController(
          title: "Reset Adapter",
          message: "Resetting the adapter will restore its default settings and reboot it.",
          preferredStyle: .alert)
        alert.addAction(
          UIAlertAction(
            title: "OK".localized, style: .default,
            handler: { action in
              print("Resetting adapter")
              NotificationCenter.default.post(
                name: .bleDataSendRequest,
                object: KissPacketEncoder.FactoryReset())
            }))
        alert.addAction(UIAlertAction(title: "Cancel".localized, style: .default, handler: nil))
        self?.present(alert, animated: true, completion: nil)
      }

    NotificationCenter.default.addObserver(
      self, selector: #selector(firmwareUpdateAvailabilityChanged),
      name: .firmwareUpdateAvailabilityChanged, object: nil)

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(self.didLoseConnection),
      name: .bleDisconnected,
      object: nil)

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(self.willResignActive),
      name: UIApplication.willResignActiveNotification,
      object: nil)

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(self.didBecomeActive),
      name: UIApplication.didBecomeActiveNotification,
      object: nil)

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(self.bleReceive),
      name: .bleDataReceived,
      object: nil)

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(self.checkApiVersion),
      name: .tncApiVersionReceived,
      object: nil)

    NotificationCenter.default.post(
      name: .bleDataSendRequest,
      object: KissPacketEncoder.GetAPIVersion())

    NotificationCenter.default.post(
      name: .bleDataSendRequest,
      object: KissPacketEncoder.GetCapabilities())

    NotificationCenter.default.post(
      name: .bleDataSendRequest,
      object: KissPacketEncoder.GetFirmwareVersion())

    NotificationCenter.default.post(
      name: .bleDataSendRequest,
      object: KissPacketEncoder.GetPairedDevice())

  }

  @objc func firmwareUpdateAvailabilityChanged() {
    DispatchQueue.main.async { [weak self] in
      // Assuming you have a reference to the ButtonRow
      let updateButtonRow: ButtonRow? = self?.form.rowBy(tag: "updateFirmwareTag")
      updateButtonRow?.disabled = Condition(
        booleanLiteral: !FirmwareUpdater.shared.newVersionAvailable)
      updateButtonRow?.evaluateDisabled()
      updateButtonRow?.reload()
    }
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)

    NotificationCenter.default.post(
      name: .bleDataSendRequest,
      object: KissPacketEncoder.StopScan())
    print("sent StopScan to TNC")
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
  }

  @objc func willResignActive(notification: NSNotification) {
    print("TncConfigMenuViewController.willResignActive")
    print("Disconnecting from BLE")
    NotificationCenter.default.post(
      name: .bleDisconnectRequest,
      object: nil)
  }

  @objc func didBecomeActive(notification: NSNotification) {
    if blePeripheral == nil {
      self.navigationController?.popToRootViewController(animated: false)
    }
  }

  @objc func didLoseConnection(notification: NSNotification) {
    let alert = UIAlertController(
      title: "LostBLETitle".localized,
      message: "LostBLEMessage".localized,
      preferredStyle: .alert)
    alert.addAction(
      UIAlertAction(
        title: "OK", style: .default,
        handler: { action in
          self.navigationController?.popToRootViewController(animated: false)
        }))
    self.present(alert, animated: true)
  }

  deinit {
    print("TncConfigMenuViewController.deinit")
    NotificationCenter.default.removeObserver(self)
  }

  func performFlashUpdate() {
    if let peripheral = blePeripheral, let characteristic = otaFlashCharacteristic {
      showFlashingHUD()

      progressObservation = self.firmwareFlashingProgress.observe(
        \.fractionCompleted, options: [.initial, .new]
      ) { progress, change in
        if progress.isCancelled {
          DispatchQueue.main.async { [weak self] in
            self?.showFlashingErrorHUD()
          }
        } else {
          DispatchQueue.main.async { [weak self] in
            self?.incrementHUD(progress: Float(progress.fractionCompleted))
          }
        }
      }

      DispatchQueue.main.async { [weak self] in
        let updateButtonRow: ButtonRow? = self?.form.rowBy(tag: "updateFirmwareTag")
        updateButtonRow?.disabled = true
        updateButtonRow?.evaluateDisabled()
        updateButtonRow?.reload()
      }

      FirmwareUpdater.shared.performUpdate(
        peripheral: peripheral, characteristic: characteristic,
        progress: self.firmwareFlashingProgress)
    } else {
      showFlashingErrorHUD()
    }
  }

  func showFlashingHUD() {
    hud.indicatorView = JGProgressHUDRingIndicatorView()
    hud.interactionType = .blockAllTouches
    hud.square = true
    hud.detailTextLabel.text = "0%"
    hud.textLabel.text = "Flashing Firmware"
    hud.show(in: self.view)
  }

  func incrementHUD(progress: Float) {
    hud.progress = progress
    hud.detailTextLabel.text = "\(Int(progress*100.0))%"

    if progress >= 1.0 {
      DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(500)) { [weak self] in
        UIView.animate(
          withDuration: 0.1,
          animations: {
            self?.hud.textLabel.text = "Done"
            self?.hud.detailTextLabel.text = nil
            self?.hud.indicatorView = JGProgressHUDSuccessIndicatorView()
          })
        self?.hud.dismiss(afterDelay: 1.0)
      }
    }
  }

  func showFlashingErrorHUD() {
    hud.dismiss()
    hud = JGProgressHUD()
    hud.indicatorView = JGProgressHUDErrorIndicatorView()
    hud.square = true
    hud.textLabel.text = "Error"
    hud.detailTextLabel.text = "Failed to flash"
    hud.show(in: self.view)
    hud.dismiss(afterDelay: 3.0)
  }

  func hasRigCtrl() -> Bool {
    return capabilities?.contains(.CAP_RIG_CTRL) ?? true
  }

  func postPacket(packet: KissPacketDecoder) {
    if let hardware = packet.getHardwareType() {
      switch hardware {
      case .FIRMWARE_VERSION:
        print("Received get firmware version: \(packet.asString())")
        let firmwareVersionRow: LabelRow? = form.rowBy(tag: "firmwareVersionRowTag")
        firmwareVersionRow?.value = packet.asString()
        tableView.reloadData()
        break
      case .API_VERSION:
        print("Received api version: \(packet.asUInt16())")
        apiVersion = packet.asUInt16()
        NotificationCenter.default.post(
          name: .tncApiVersionReceived,
          object: packet)
        break
      case .CAPABILITIES:
        capabilities = packet.getCapabilities()
        let useRigCtrlRow: SwitchRow? = form.rowBy(tag: "useRigCtrlTag")
        useRigCtrlRow?.value = hasRigCtrl()
        useRigCtrlRow?.reload()
        break
      case .FOUND_DEVICE:
        print("Found device")
        if let parsed = parseBluetoothPacket(packet: packet.data) {
          let address = parsed.address
          let name = parsed.name
          print("Address:", address.stringRepresentation)
          print("Name:", name)
          let device = BTDevice(address: address, name: name)
          devicesFound.updateValue(device, forKey: address)
        } else {
          print("Invalid device info")
        }
        break
      case .GET_PAIRED_DEVICE:
        print("Get paired device")
        if let parsed = parseBluetoothPacket(packet: packet.data) {
          let connected = parsed.connected
          let address = parsed.address
          let name = parsed.name
          print("Connected:", connected)
          print("Address:", address.stringRepresentation)
          print("Name:", name)
          pairedDevice = BTDevice(connected: connected, address: address, name: name)
          devicesFound.updateValue(pairedDevice!, forKey: address)
          let pairedRadioRow: PushRow<BTDevice>? = form.rowBy(tag: "pairedRadioTag")
          pairedRadioRow?.value = pairedDevice
        } else {
          print("No previously paired device found")
          devicesFound.removeAll()
          pairedDevice = nil
          let pairedRadioRow: PushRow<BTDevice>? = form.rowBy(tag: "pairedRadioTag")
          pairedRadioRow?.value = nil
        }
        tableView.reloadData()
        break

      }
    } else {
      print("packet type: \((packet.packetType))")
    }
  }

  @objc func bleReceive(notification: NSNotification) {
    print("bleReceive")
    // unpack data
    let data = notification.object as! Data
    let packets = slipDecoder.decode(incoming: data)
    for packet in packets {
      let kiss: KissPacketDecoder
      do {
        try kiss = KissPacketDecoder(incoming: packet)
        postPacket(packet: kiss)
      } catch {
        print("invalid KISS packet received: \((data.hexEncodedString() as String))")
        continue
      }
    }
  }

  @objc func checkApiVersion(notification: NSNotification) {
    print("Got apiversion")
    if apiVersion != nil && apiVersion! > knownApiVersion {
      let alert = UIAlertController(
        title: "New Version Detected",
        message:
          "The adapter reported a more recent version than anticipated by the configurator app. For optimal compatibility, please update the configurator app.",
        preferredStyle: .alert)
      alert.addAction(UIAlertAction(title: "OK".localized, style: .default, handler: { action in }))
      self.present(alert, animated: true, completion: nil)
    }
  }

  func parseBluetoothPacket(packet: Data) -> (connected: Bool, address: ESPBDAddress, name: String)?
  {
    // Ensure the packet has at least 6 bytes for the address
    guard packet.count > 7 else {
      print("Packet is too short to contain a valid address and name.")
      return nil
    }

    // Extract the first byte as connection status
    let connected = packet[0] == 0x01

    // Extract the next 6 bytes as the address
    let addressData = packet.subdata(in: 1..<7)
    guard let address = ESPBDAddress(address: addressData) else {
      print("The address part of the packet is not valid.")
      return nil
    }

    // Extract the remaining bytes as the name
    let nameData = packet.subdata(in: 7..<packet.count)
    guard let name = String(data: nameData, encoding: .utf8) else {
      print("Name data could not be decoded as a UTF-8 string.")
      return nil
    }

    // Return the parsed address and name
    return (connected, address, name)
  }

}
