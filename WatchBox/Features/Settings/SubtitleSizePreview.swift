//
//  SubtitleSizePreview.swift
//  SceneBox
//
//  Created by SpontaneousArray on 31.07.26.
//

import SwiftUI

struct SubtitleSizePreview: View {
    let scale: Double

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.28), Color(white: 0.12)],
                           startPoint: .top, endPoint: .bottom)
            Text("The quick brown fox")
                .font(.system(size: 15 * scale, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black, radius: 1, y: 1)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .padding(.horizontal, 8)
        }
        .frame(height: 68)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        .animation(.easeInOut(duration: 0.15), value: scale)
    }
}
