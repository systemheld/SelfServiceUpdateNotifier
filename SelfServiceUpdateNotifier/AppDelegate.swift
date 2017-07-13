//
//  AppDelegate.swift
//  SelfServiceUpdateNotifier
//
//  Created by Kett, Oliver on 10.04.17.
//  Copyright © 2017 Kett, Oliver. All rights reserved.
//
// App must be "Developer ID signed" - development signed is not sufficient
// https://stackoverflow.com/questions/16029755/nsusernotificationalertstyle-plist-key-not-working#16712518
// to hide any menu and dock item:
// https://nsrover.wordpress.com/2014/10/10/creating-a-os-x-menubar-only-app/

import Cocoa

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, NSUserNotificationCenterDelegate, XMLParserDelegate {
    
    class Policy {
        var policy_id = 0
        var policy_name = String()
    }
    var policies = [Policy]()
    
    // temporary items for XMLParserDelegates
    var foundCharacters = String()
    var policy = Policy()
    var isCategoryUpdates = false
    
    func quit() {
        NSApplication.shared().terminate(self)
    }
    
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // run everything in background
        if CommandLine.arguments.count >= 2 && CommandLine.arguments[1] == "notify" {
            // App is run from LaunchAgent to notify user on completed updates
            let notification = NSUserNotification()
            notification.title = config.appName
            notification.subtitle = NSLocalizedString("App Updates installiert", comment: "all updates were installed")
            notification.informativeText = NSLocalizedString("Updates wurden erfolgreich installiert", comment: "all updates were successfully installed")
            notification.hasActionButton = false
            notification.soundName = NSUserNotificationDefaultSoundName
            NSUserNotificationCenter.default.deliver(notification)
            self.quit()
        } else {
            DispatchQueue.global().async {
                self.searchAndShowUpdates()
            }
        }
    }
    
    func searchAndShowUpdates() {
        let UUID = IORegistryEntryCreateCFProperty(
            IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching("IOPlatformExpertDevice")),
            kIOPlatformUUIDKey as CFString,
            kCFAllocatorDefault,
            0
            ).takeRetainedValue()
        let selfServiceURL = URL(string: "https://\(config.jssHost)/selfservice2/index.hml?uuid=\(UUID)")!
        let xmlURL = URL(string: "https://\(config.jssHost)/selfservice2/ssresource/policy")!
        
        let semaphore = DispatchSemaphore(value: 0)
        // get Session ID for UUID
        var task = URLSession.shared.dataTask(with: selfServiceURL, completionHandler: { data, response, error in
            semaphore.signal()
        })
        task.resume()
        semaphore.wait()
        
        // get XML with policies
        task = URLSession.shared.dataTask(with: xmlURL, completionHandler: { data, response, error in
            if (error != nil) {
                NSLog("error: \(error?.localizedDescription)")
                self.quit()
            }
            let parser = XMLParser(data: data!)
            parser.delegate = self
            parser.parse()
            semaphore.signal()
        })
        task.resume()
        semaphore.wait()
        
        // filter out policy names, that we do not want the user to remind - e.g. macOS Major Release Updates
        // we just need the ids
        var policyIDs = [Int]()
        for policy in policies {
            if !config.ignoreStringsToMatch.contains(policy.policy_name) {
                policyIDs.append(policy.policy_id)
            }
        }
        
        if policyIDs.count == 0 {
            NSLog("no updates available")
            DispatchQueue.main.async {
                self.quit()
            }
        } else {
            let notification = NSUserNotification()
            notification.title = config.appName
            notification.subtitle = NSLocalizedString("App Updates verfügbar", comment: "there are App Updates available")
            notification.informativeText = String(format: NSLocalizedString("Es stehen %d Updates für dich bereit", comment: "there are %d updates available"), policyIDs.count)
            notification.hasActionButton = true
            notification.actionButtonTitle = NSLocalizedString("installieren", comment: "install now")
            notification.otherButtonTitle = NSLocalizedString("später", comment: "install later")
            notification.soundName = NSUserNotificationDefaultSoundName
            // this is undocumented!
            notification.setValue(true, forKey: "_alwaysShowAlternateActionMenu")
            notification.additionalActions = [
                NSUserNotificationAction(identifier: "installAll", title: NSLocalizedString("alle installieren", comment: "install all")),
                NSUserNotificationAction(identifier: "openSelfService", title: NSLocalizedString("FAUmac Self Service öffnen", comment: "open the Self Service Application")),
            ]
            
            let center = NSUserNotificationCenter.default
            center.delegate = self
            center.deliver(notification)
        }
    }
    
    // MARK: NSUserNotificationCenterDelegate methods
    func userNotificationCenter(_ center: NSUserNotificationCenter, shouldPresent notification: NSUserNotification) -> Bool {
        return true
    }
    
    // undocumentented and private API - called when user clicks "später" which is the "otherButton"
    func userNotificationCenter(_ center: NSUserNotificationCenter, didDismissAlert notification: NSUserNotification) {
        NSLog("user clicked later")
        self.quit()
    }
    
    func userNotificationCenter(_ center: NSUserNotificationCenter, didActivate notification: NSUserNotification) {
        switch notification.activationType {
        case .additionalActionClicked:
            switch notification.additionalActivationAction!.identifier! {
            case "installAll":
                let touch = Process.launchedProcess(launchPath: "/usr/bin/touch", arguments: [config.triggerFile])
                touch.waitUntilExit()
                if touch.terminationStatus != 0 {
                    NSLog("error touching file \(config.triggerFile). Maybe i have no permission to write there?")
                }
            // TODO: jamf does always exit(0) so we need another way to determine if installing an update worked
            case "openSelfService":
                NSWorkspace.shared().launchApplication(config.selfServicePath)
                NSLog("launched Self Service")
            default:
                self.quit()
            }
        default:
            self.quit()
        }
        self.quit()
    }
    
    // MARK: XMLParserDelegate methods
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        if elementName == "policy" {
            // every time, a new policy tag is found, we clear the last temporarily saved policy
            self.policy = Policy()
        }
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        self.foundCharacters += string
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName {
        case "policy":
            // only policies in category Updates will be added
            if self.isCategoryUpdates == true {
                policies.append(policy)
            }
        case "policy_id":
            self.policy.policy_id = Int(self.foundCharacters) ?? 0
        case "policy_name":
            self.policy.policy_name = self.foundCharacters
        case "category_name":
            // only get Policies in category Updates
            if self.foundCharacters == config.updatesCategory {
                self.isCategoryUpdates = true
            }
        case "category":
            // if we previously set self.isCategoryUpdates to true, this category is now ended, so set it to false
            self.isCategoryUpdates = false
        default:
            () // do nothing
        }
        self.foundCharacters = String()
    }
}

