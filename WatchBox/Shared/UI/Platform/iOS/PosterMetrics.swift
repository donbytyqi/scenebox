//
//  PosterMetrics.swift
//  SceneBox
//
//  Created by SpontaneousArray on 19.08.26.
//

#if os(iOS)
import SwiftUI

enum PosterMetrics {
    static func shelfWidth(_ sizeClass: UserInterfaceSizeClass?) -> CGFloat {
        if Platform.isMac { return 180 }          // big window, big posters
        return sizeClass == .regular ? 168 : 116
    }

    static func gridColumns(_ sizeClass: UserInterfaceSizeClass?) -> [GridItem] {
        let regular = sizeClass == .regular
        if Platform.isMac {
            return [GridItem(.adaptive(minimum: 160, maximum: 210), spacing: 20)]
        }
        return [GridItem(.adaptive(minimum: regular ? 150 : 108,
                                   maximum: regular ? 200 : 132),
                         spacing: regular ? 18 : 12)]
    }
}
#endif
