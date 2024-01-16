//
//  DynamicSelectorRow.swift
//  B.B. Link Configurator
//
//  Created by Georges Auberger on 1/15/24.
//  Copyright © 2024 Island Magic Co. All rights reserved.
//

import Foundation
import Eureka

class DynamicSelectorViewController: SelectorViewController<SelectorRow<PushSelectorCell<String>>> {
    
    func updateOptions(_ newOptions: [String]) {
        print("Dynamically updating options in the controller")
        optionsProviderRow.cachedOptionsData = newOptions
        optionsProviderRow.options = newOptions
        form.removeAll()
        setupForm()
        tableView.reloadData()
    }
}
