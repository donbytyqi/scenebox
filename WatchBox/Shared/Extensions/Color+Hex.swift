//
//  Color+Hex.swift
//  SceneBox
//
//  Created by SpontaneousArray on 30.07.26.
//

import SwiftUI
import UIKit

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# ")).uppercased()
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }

    var hexString: String {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        if let srgbSpace = CGColorSpace(name: CGColorSpace.sRGB),
           let srgb = ui.cgColor.converted(to: srgbSpace, intent: .defaultIntent, options: nil),
           let comps = srgb.components, comps.count >= 3 {
            r = comps[0]; g = comps[1]; b = comps[2]
        } else {
            ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        }
        func channel(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "%02X%02X%02X", channel(r), channel(g), channel(b))
    }

    var contrastingForeground: Color {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        if let srgbSpace = CGColorSpace(name: CGColorSpace.sRGB),
           let srgb = ui.cgColor.converted(to: srgbSpace, intent: .defaultIntent, options: nil),
           let comps = srgb.components, comps.count >= 3 {
            r = comps[0]; g = comps[1]; b = comps[2]
        } else {
            ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        }
        let luma = 0.299 * r + 0.587 * g + 0.114 * b
        return luma > 0.6 ? .black : .white
    }
}
