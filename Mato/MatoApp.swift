//
//  MatoApp.swift
//  Mato
//
//  Created by  on 5/22/25.
//

import SwiftUI

@main
struct MatoApp: App {
    init() {
        // Configure TipKit on app launch
        MatoTips.configure()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }

        Settings {
            SettingsView()
        }
    }
}
