//
//  UUIDKey.swift
//  Mobilinkd TNC Config
//
//  Created by Trevor Beaton on 12/3/16.
//  Copyright © 2016 Vanguard Logic LLC. All rights reserved.
//

import CoreBluetooth

let kBLEService_UUID = "00000001-ba2a-46c9-ae49-01b0961f68bb"
let kBLE_Characteristic_uuid_Tx = "00000002-ba2a-46c9-ae49-01b0961f68bb"
let kBLE_Characteristic_uuid_Rx = "00000003-ba2a-46c9-ae49-01b0961f68bb"

let BLEService_UUID = CBUUID(string: kBLEService_UUID)
let BLE_Characteristic_uuid_Tx = CBUUID(string: kBLE_Characteristic_uuid_Tx)//(Property = Write without response)
let BLE_Characteristic_uuid_Rx = CBUUID(string: kBLE_Characteristic_uuid_Rx)// (Property = Read/Notify)

let kBLEServiceOTAUUID = "1A68D2B0-C2E4-453F-A2BB-B659D66CF442"
let kBLECharacteristicOTAFlashUUID  = "1A68D2B1-C2E4-453F-A2BB-B659D66CF442"
let kBLECharacterisitcOTAIdentityUUID =   "1A68D2B2-C2E4-453F-A2BB-B659D66CF442"

let BLEServiceOTAUUID = CBUUID(string: kBLEServiceOTAUUID)
let BLECharacteristicOTAFlashUUID = CBUUID(string: kBLECharacteristicOTAFlashUUID) // Write
let BLECharacterisitcOTAIdentityUUID = CBUUID(string: kBLECharacterisitcOTAIdentityUUID) // Read