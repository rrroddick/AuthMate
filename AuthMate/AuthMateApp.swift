//
//  AuthMateApp.swift
//  AuthMate
//

import SwiftUI

@main
struct AuthMateApp: App {
    @StateObject private var accountStore = AccountStore()
    
    var body: some Scene {
        MenuBarExtra("AuthMate", image: "MenuBarIcon") {
            ContentView()
                .environmentObject(accountStore)
        }
        .menuBarExtraStyle(.window)
    }
}
