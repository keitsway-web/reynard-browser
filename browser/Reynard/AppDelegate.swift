//
//  AppDelegate.swift
//  Reynard
//
//  Created by Minh Ton on 1/2/26.
//

import AVFoundation
import UIKit

class AppDelegate: UIResponder, UIApplicationDelegate {
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        JITController.shared.startBackgroundAudioIfNeeded()
        requestMicrophonePermission()
        return true
    }
    
    private func requestMicrophonePermission() {
        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission { _ in }
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission { _ in }
        }
    }
    
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
    
    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {}
}
