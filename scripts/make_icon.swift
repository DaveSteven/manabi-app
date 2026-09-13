// Restore the app icon from the checked-in, user-provided 1024×1024 logo.
// Run from the manabi_app directory: swift scripts/make_icon.swift
import Foundation

let source = URL(fileURLWithPath: "Manabi/Resources/Assets.xcassets/ManabiLogo.imageset/ManabiLogo.png")
let destination = URL(fileURLWithPath: "Manabi/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
try Data(contentsOf: source).write(to: destination, options: .atomic)
print("App icon updated from ManabiLogo.")
