//
//  ProfileAvatar.swift
//  SceneBox
//
//  Created by SpontaneousArray on 21.08.26.
//

import SwiftUI
import Kingfisher
import UIKit

struct ProfileAvatar: View {
    let profile: Profile
    var size: CGFloat = 96
    var preview: UIImage? = nil

    var body: some View {
        ZStack {
            if let preview {
                Image(uiImage: preview).resizable().scaledToFill()
            } else if let url = profile.avatarURL {
                KFImage(url)
                    .setProcessor(DownsamplingImageProcessor(size: CGSize(width: 512, height: 512)))
                    .cacheOriginalImage()
                    .placeholder { monogram }
                    .fade(duration: 0.2)
                    .resizable()
                    .scaledToFill()
            } else {
                monogram
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var monogram: some View {
        ZStack {
            profile.color
            Text(profile.initial)
                .font(.system(size: size * 0.46, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
    }
}

enum ProfileTabIcon {
    @MainActor
    static func make(for profile: Profile, pointSize: CGFloat = 26) async -> UIImage {
        if let url = profile.avatarURL,
           let result = try? await KingfisherManager.shared.retrieveImage(with: url) {
            return circle(result.image, pointSize: pointSize)
        }
        return monogram(profile, pointSize: pointSize)
    }

    private static func circle(_ image: UIImage, pointSize: CGFloat) -> UIImage {
        let size = CGSize(width: pointSize, height: pointSize)
        return UIGraphicsImageRenderer(size: size).image { _ in
            UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).addClip()
            let scale = max(pointSize / image.size.width, pointSize / image.size.height)
            let drawn = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: CGRect(x: (pointSize - drawn.width) / 2, y: (pointSize - drawn.height) / 2,
                                  width: drawn.width, height: drawn.height))
        }.withRenderingMode(.alwaysOriginal)
    }

    private static func monogram(_ profile: Profile, pointSize: CGFloat) -> UIImage {
        let size = CGSize(width: pointSize, height: pointSize)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor(profile.color).setFill()
            UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).fill()
            let font = UIFont.systemFont(ofSize: pointSize * 0.5, weight: .bold)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
            let text = NSAttributedString(string: profile.initial, attributes: attrs)
            let textSize = text.size()
            text.draw(at: CGPoint(x: (pointSize - textSize.width) / 2, y: (pointSize - textSize.height) / 2))
        }.withRenderingMode(.alwaysOriginal)
    }
}
