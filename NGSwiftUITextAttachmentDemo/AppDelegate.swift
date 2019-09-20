//
//  AppDelegate.swift
//  NGSwiftUITextAttachmentDemo
//
//  Created by Noah Gilmore on 9/15/19.
//  Copyright © 2019 Noah Gilmore. All rights reserved.
//

import Cocoa
import SwiftUI

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    var window: NSWindow!


    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Insert code here to initialize your application
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 300),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.center()
        window.setFrameAutosaveName("Main Window")

        window.title = "Fluency"
        let contentView: NSView = window.contentView!
        let customTextView = CustomTextView()
        contentView.addSubview(customTextView)
        customTextView.translatesAutoresizingMaskIntoConstraints = false
        customTextView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor).isActive = true
        customTextView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor).isActive = true
        customTextView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 40).isActive = true
        customTextView.widthAnchor.constraint(equalToConstant: 800).isActive = true
        customTextView.heightAnchor.constraint(equalToConstant: 800).isActive = true
        let bottomConstraint = customTextView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        bottomConstraint.priority = .required
        bottomConstraint.isActive = true
        window.setContentSize(customTextView.frame.size)

        window.makeKeyAndOrderFront(nil)
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }


}

