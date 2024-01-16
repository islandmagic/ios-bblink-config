//
//  ESPBDAddress.swift
//  B.B. Link Configurator
//
//  Created by Georges Auberger on 1/14/24.
//  Copyright © 2024 Island Magic Co. All rights reserved.
//

import Foundation

struct ESPBDAddress: Hashable {
    private let address: Data
    
    init?(address: Data) {
        guard address.count == 6 else { return nil }
        self.address = address
    }
    
    init?(addressString: String) {
        let components = addressString.split(separator: ":").compactMap { UInt8($0, radix: 16) }
        guard components.count == 6 else { return nil }
        self.address = Data(components)
    }
    
    var binaryRepresentation: Data {
        return self.address
    }
    
    var stringRepresentation: String {
        return self.address.map { String(format: "%02x", $0) }.joined(separator: ":")
    }
    
    // Conformance to Hashable is automatically provided because Data already conforms to Hashable.
}
