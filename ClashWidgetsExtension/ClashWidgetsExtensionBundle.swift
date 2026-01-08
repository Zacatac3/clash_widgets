//
//  ClashWidgetsExtensionBundle.swift
//  ClashWidgetsExtension
//
//  Created by Zachary Buschmann on 1/7/26.
//

import WidgetKit
import SwiftUI

@main
struct ClashWidgetsExtensionBundle: WidgetBundle {
    var body: some Widget {
        ClashWidgetsExtension()
        ClashWidgetsExtensionControl()
        ClashWidgetsExtensionLiveActivity()
    }
}
