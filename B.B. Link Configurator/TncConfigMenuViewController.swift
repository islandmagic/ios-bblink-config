//
//  TncConfigMenuViewControllerTableViewController.swift
//  Mobilinkd TNC Config
//
//  Created by Rob Riggs on 12/29/18.
//  Copyright © 2018 Mobilinkd LLC. All rights reserved.
//

import UIKit
import CoreBluetooth
import Eureka

struct BTDevice {
    var address : ESPBDAddress?
    var name : String
}
extension BTDevice: Hashable, Equatable {}

class TncConfigMenuViewController : FormViewController {
    
    static let tncFirmwareVersionNotification = NSNotification.Name(rawValue: "tncFirmwareVersion")
    static let tncApiVersionNotification = NSNotification.Name(rawValue: "tncApiVersion")
    static let tncCapabilitiesNotification = NSNotification.Name(rawValue: "tncCapabilities")
    
    var mainViewController : BLECentralViewController?
    var peripheralManager: CBPeripheralManager?
    var peripheral: CBPeripheral?
    // SlipProtocolDecoder maintains state to handle packets that are split
    // across multiple MTU blocks.
    var slipDecoder = SlipProtocolDecoder()
    
    // TNC Information
    var firmwareVersion : String?
    var capabilities : Capabilities?
    
    // Bluetooth Classic devices found
    var devicesFound : [ESPBDAddress:BTDevice] = [:]
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        form +++ Section()
            <<< LabelRow() { row in
                row.title = "Adapter Name"
                row.value = peripheral?.name!
            }
            <<< LabelRow() { row in
                row.tag = "firmwareVersionRowTag"
                row.title = "Firmware Version"
                row.value = firmwareVersion
            }
        +++ Section(footer: "Make sure your radio is discoverable. Menu > Bluetooth > Pairing Mode")
        <<< PushRow<BTDevice>() {row in
                row.tag = "pairedRadioTag"
                row.title = "Paired Radio"
                row.selectorTitle = "Discovering Nearby Devices..."
                row.options = []
                
                row.optionsProvider = .lazy({ (form, completion) in
                    let activityView = UIActivityIndicatorView(style: .medium)
                    form.tableView.backgroundView = activityView
                     activityView.startAnimating()
                     DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: {
                         form.tableView.backgroundView = nil
                         let options = Array(self.devicesFound.values)
                         completion(options)
                     })
                 })                
            }.onChange { row in
                print("pairedRadio: \(row.value?.name ?? "None")")
                if let address = row.value?.address {
                    print("Address:", address.stringRepresentation)
                    NotificationCenter.default.post(
                        name: BLECentralViewController.bleDataSendNotification,
                        object: KissPacketEncoder.PairWithDevice(address: address))
                    print("sent PairWithDevice to TNC")
                }
                }.onPresent { from, to in
                    self.devicesFound.removeAll()
                    NotificationCenter.default.post(
                        name: BLECentralViewController.bleDataSendNotification,
                        object: KissPacketEncoder.StartScan())
                    print("sent StartScan to TNC")
                    to.selectableRowCellUpdate = { (cell, row) in
                        cell.textLabel?.text = row.selectableValue?.name
                    }
                    to.onDismissCallback = { vc in
                        NotificationCenter.default.post(
                            name: BLECentralViewController.bleDataSendNotification,
                            object: KissPacketEncoder.StopScan())
                        print("sent StopScan to TNC")
                        _ = vc.navigationController?.popViewController(animated: true)
                    }
                }.cellUpdate {cell,row in
                    cell.detailTextLabel?.text = row.value?.name
                }
            
            +++ Section("Advanced")
        <<< SwitchRow() {row in
            row.tag = "useRigCtrlTag"
            row.title = "Control Frequency"
            row.value = true
        }.onChange {row in
            print("useRigCtrl \(row.value)")
            NotificationCenter.default.post(
                name: BLECentralViewController.bleDataSendNotification,
                object: KissPacketEncoder.SetRigCtrl(value: row.value ?? true))
        }
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.didLoseConnection),
            name: BLECentralViewController.bleDisconnectNotification,
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
            name: BLECentralViewController.bleDataReceiveNotification,
            object: nil)

        NotificationCenter.default.post(
            name: BLECentralViewController.bleDataSendNotification,
            object: KissPacketEncoder.GetCapabilities())

        NotificationCenter.default.post(
            name: BLECentralViewController.bleDataSendNotification,
            object: KissPacketEncoder.GetFirmwareVersion())

        NotificationCenter.default.post(
            name: BLECentralViewController.bleDataSendNotification,
            object: KissPacketEncoder.GetPairedDevice())
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        NotificationCenter.default.post(
            name: BLECentralViewController.bleDataSendNotification,
            object: KissPacketEncoder.StopScan())
        print("sent StopScan to TNC")
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
    }

    @objc func willResignActive(notification: NSNotification)
    {
        print("TncConfigMenuViewController.willResignActive")
        
        if self.isBeingPresented {
            disconnectBle()
        }
    }
    
    @objc func didBecomeActive(notification: NSNotification)
    {
        if blePeripheral == nil {
            self.navigationController?.popToRootViewController(animated: false)
        }
    }

    @objc func didLoseConnection(notification: NSNotification)
    {
        let alert = UIAlertController(
            title: "LostBLETitle".localized,
            message: "LostBLEMessage".localized,
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { action in
            self.navigationController?.popToRootViewController(animated: false)
        }))
        self.present(alert, animated: true)
    }

    deinit {
        NotificationCenter.default.removeObserver(self,
            name: BLECentralViewController.bleDataReceiveNotification,
            object: nil)
        print("bleDataReceiveNotification unsubscribed")
    }
    
    func hasRigCtrl() -> Bool {
        return capabilities?.contains(.CAP_RIG_CTRL) ?? true
    }
    
    func postPacket(packet: KissPacketDecoder)
    {
        if let hardware = packet.getHardwareType() {
            switch hardware {
            case .FIRMWARE_VERSION:
                print("Received get firmware version: ", packet.asString())
                let firmwareVersionRow: LabelRow? = form.rowBy(tag: "firmwareVersionRowTag")
                firmwareVersionRow?.value = packet.asString()
                tableView.reloadData()
                NotificationCenter.default.post(
                    name: TncConfigMenuViewController.tncFirmwareVersionNotification,
                    object: packet)
                break
            case .API_VERSION:
                NotificationCenter.default.post(
                    name: TncConfigMenuViewController.tncApiVersionNotification,
                    object: packet)
                break
            case .CAPABILITIES:
                capabilities = packet.getCapabilities()
                let useRigCtrlRow: SwitchRow? = form.rowBy(tag: "useRigCtrlTag")
                useRigCtrlRow?.value = hasRigCtrl()
                useRigCtrlRow?.reload()
                NotificationCenter.default.post(
                    name: TncConfigMenuViewController.tncCapabilitiesNotification,
                    object: packet)
                break
            case .FOUND_DEVICE:
                print("Found device")
                if let parsed = parseBluetoothPacket(packet: packet.data) {
                    let address = parsed.address
                    let name = parsed.name
                    print("Address:", address.stringRepresentation)
                    print("Name:", name)
                    devicesFound.updateValue(BTDevice(address: address, name: name), forKey: address)
                }
                else
                {
                    print("Invalid device info")
                }
                break
            case .START_SCAN:
                print("Start scan")
                break
            case .STOP_SCAN:
                print("Stop scan")
                break
            case .PAIR_WITH_DEVICE:
                print("Pair with device")
                break
            case .CLEAR_PAIRED_DEVICE:
                print("Clear paired device")
                break
            case .GET_PAIRED_DEVICE:
                print("Get paired device")
                if let parsed = parseBluetoothPacket(packet: packet.data) {
                    let address = parsed.address
                    let name = parsed.name
                    print("Address:", address.stringRepresentation)
                    print("Name:", name)
                    let device = BTDevice(address: address, name: name)
                    devicesFound.updateValue(device, forKey: address)
                    let pairedRadioRow: PushRow<BTDevice>? = form.rowBy(tag: "pairedRadioTag")
                    pairedRadioRow?.value = device
                }
                else
                {
                    print("No previously paired device found")
                    devicesFound.removeAll()
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
    
    
    @objc func bleReceive(notification: NSNotification)
    {
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
    
    func parseBluetoothPacket(packet: Data) -> (address: ESPBDAddress, name: String)? {
        // Ensure the packet has at least 6 bytes for the address
        guard packet.count > 6 else {
            print("Packet is too short to contain a valid address and name.")
            return nil
        }
        
        // Extract the first 6 bytes as the address
        let addressData = packet.subdata(in: 0..<6)
        guard let address = ESPBDAddress(address: addressData) else {
            print("The address part of the packet is not valid.")
            return nil
        }
        
        // Extract the remaining bytes as the name
        let nameData = packet.subdata(in: 6..<packet.count)
        guard let name = String(data: nameData, encoding: .utf8) else {
            print("Name data could not be decoded as a UTF-8 string.")
            return nil
        }
        
        // Return the parsed address and name
        return (address, name)
    }
}
