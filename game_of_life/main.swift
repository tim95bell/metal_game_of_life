//
//  main.swift
//  game_of_life
//
//  Created by Tim Bell on 7/7/2024.
//

import Cocoa

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
