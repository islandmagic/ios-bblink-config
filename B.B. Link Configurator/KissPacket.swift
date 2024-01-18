//
//  KissProtocolDecoder.swift
//  Mobilinkd TNC Config
//
//  Created by Rob Riggs on 12/30/18.
//  Copyright © 2018 Mobilinkd LLC. All rights reserved.
//

import Foundation

enum KissPacketError : Error {
    case invalidPacketData
    case invalidPacketLength
}

struct Capabilities : OptionSet {
    let rawValue : UInt16
    
    static let CAP_RIG_CTRL = Capabilities(rawValue: 0x0010)
    static let CAP_FIRMWARE_VERSION = Capabilities(rawValue: 0x0800)
}

class KissPacketDecoder
{
    enum PacketType : UInt8 {
        case Data = 0
        case TxDelay = 1
        case Persistance = 2
        case SlotTime = 3
        case TxTail = 4
        case Duplex = 5
        case Hardware = 6
        case Escape = 15    // 0x0F
    }
    
    enum HardwareType : UInt8 {
        case FIRMWARE_VERSION = 40
        case API_VERSION = 123        // API 2.0
        case CAPABILITIES = 126

        case FOUND_DEVICE = 0xEE
        case GET_PAIRED_DEVICE = 0xF1
    }
    
    var port : UInt8
    var packetType : PacketType
    var hardwareType : HardwareType?
    var data : Data
    var count : Int
    
    init(incoming : Data) throws {
        if incoming.count < 1 {
            throw KissPacketError.invalidPacketLength
        }

        let typeByte = incoming[0]
        port = (typeByte & 0xF0) >> 4
        let pType = PacketType(rawValue: (typeByte & 0x0F))!
        if incoming.count > 2 && pType == .Hardware {
            hardwareType = HardwareType(rawValue: incoming[1])
            data = Data(incoming[2...])
        } else {
            data = Data(incoming[1...])
        }
        
        packetType = pType
        count = data.count
    }

    func asUInt8() -> UInt8? {
        return data[0]
    }
    
    func asUInt16() -> UInt16? {
        // Big endian...
        if data.count > 1 {
            return UInt16(UInt16(data[0]) * 256) + UInt16(data[1])
        }
        return nil
    }
    
    func asString() -> String? {
        return String(data: data, encoding: String.Encoding.utf8)
    }
    
    func isHardwareType() -> Bool {
        return hardwareType != nil
    }
    
    func getHardwareType() -> HardwareType?
    {
        return hardwareType
    }
    
    func isCapabilities() -> Bool {
        return hardwareType == .CAPABILITIES
    }
    
    func getCapabilities() -> Capabilities? {
        if hardwareType == .CAPABILITIES {
            if let cap = self.asUInt16() {
                return Capabilities(rawValue: cap)
            }
        }
        return nil
    }
}

class KissPacketEncoder {
    
    enum PacketType : UInt8 {
        case Data = 0
        case TxDelay = 1
        case Persistence = 2
        case SlotTime = 3
        case TxTail = 4
        case Duplex = 5
        case Hardware = 6
    }
    
    enum HardwareType : UInt8 {
        case FIRMWARE_VERSION = 40
        case API_VERSION = 123        // API 2.0
        case CAPABILITIES = 126

        case START_SCAN = 0xEC
        case STOP_SCAN = 0xED
        case PAIR_WITH_DEVICE = 0xEF
        case CLEAR_PAIRED_DEVICE = 0xF0
        case GET_PAIRED_DEVICE = 0xF1
        case SET_RIG_CTRL = 0xF2
        case FACTORY_RESET = 0xF3

    }
    
    let packetType : PacketType
    let hardwareType : HardwareType?
    let data : Data
    
    init(packetType: PacketType, data: UInt8) {
        self.packetType = packetType
        self.hardwareType = nil
        self.data = Data([data])
    }
    
    init(hardwareType: HardwareType?) {
        self.packetType = .Hardware
        self.hardwareType = hardwareType
        self.data = Data()
    }
    
    init(hardwareType: HardwareType?, data: Data) {
        self.packetType = .Hardware
        self.hardwareType = hardwareType
        self.data = data
    }
    
    init(hardwareType: HardwareType?, data: UInt8) {
        self.packetType = .Hardware
        self.hardwareType = hardwareType
        self.data = Data([data])
    }
    
    init(hardwareType: HardwareType?, data: UInt16) {
        self.packetType = .Hardware
        self.hardwareType = hardwareType
        self.data = Data([UInt8(data >> 8),UInt8(data & 0xFF)])
    }
    
    init(hardwareType: HardwareType?, data: Bool) {
        self.packetType = .Hardware
        self.hardwareType = hardwareType
        self.data = Data([data ? 0x01 : 0x00])
    }
    
    func encode() -> Data {
        var result = Data()
        result.append(packetType.rawValue)
        if packetType == .Hardware {
            result.append(hardwareType!.rawValue)
        }
        result += data
        return result
    }

    static func GetFirmwareVersion() -> Data {
        return SlipProtocolEncoder.encode(
            value: KissPacketEncoder(hardwareType: .FIRMWARE_VERSION).encode())
    }

    static func GetAPIVersion() -> Data {
        return SlipProtocolEncoder.encode(
            value: KissPacketEncoder(hardwareType: .API_VERSION).encode())
    }

    static func StartScan() -> Data {
        return SlipProtocolEncoder.encode(
            value: KissPacketEncoder(hardwareType: .START_SCAN).encode())
    }

    static func StopScan() -> Data {
        return SlipProtocolEncoder.encode(
            value: KissPacketEncoder(hardwareType: .STOP_SCAN).encode())
    }

    static func PairWithDevice(address: ESPBDAddress) -> Data {
        return SlipProtocolEncoder.encode(
            value: KissPacketEncoder(hardwareType: .PAIR_WITH_DEVICE, data: address.binaryRepresentation).encode())
    }
    
    static func GetPairedDevice() -> Data {
        return SlipProtocolEncoder.encode(
            value: KissPacketEncoder(hardwareType: .GET_PAIRED_DEVICE).encode())
    }
    
    static func SetRigCtrl(value: Bool) -> Data {
        return SlipProtocolEncoder.encode(
            value: KissPacketEncoder(hardwareType: .SET_RIG_CTRL, data: value).encode())
    }
    
    static func GetCapabilities() -> Data {
        return SlipProtocolEncoder.encode(
            value: KissPacketEncoder(hardwareType: .CAPABILITIES).encode())
    }

    static func ClearPairedDevice() -> Data {
        return SlipProtocolEncoder.encode(
            value: KissPacketEncoder(hardwareType: .CLEAR_PAIRED_DEVICE).encode())
    }

    static func FactoryReset() -> Data {
        return SlipProtocolEncoder.encode(
            value: KissPacketEncoder(hardwareType: .FACTORY_RESET).encode())
    }
}
