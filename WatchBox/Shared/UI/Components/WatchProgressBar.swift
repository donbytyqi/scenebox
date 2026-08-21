//
//  WatchProgressBar.swift
//  SceneBox
//
//  Created by SpontaneousArray on 10.08.26.
//

import SwiftUI

struct WatchProgressBar: View {
    let fraction: Double

    var body: some View {
        Capsule()
            .opacity(0.3)
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    Capsule()
                        .frame(width: geo.size.width * min(max(fraction, 0), 1))
                }
            }
            .clipShape(Capsule())
    }
}
