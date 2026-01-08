//
//  ClashWidgetBundle.swift
//  ClashWidget
//
//  Created by Zachary Buschmann on 1/7/26.
//

import WidgetKit
import SwiftUI

@main
struct ClashWidgetBundle: WidgetBundle {
    var body: some Widget {
        ClashWidget()
        ClashWidgetControl()
    }
}
