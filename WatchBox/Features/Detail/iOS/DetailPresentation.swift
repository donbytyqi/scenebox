//
//  DetailPresentation.swift
//  SceneBox
//
//  Created by SpontaneousArray on 01.08.26.
//

#if os(iOS)
import SwiftUI

extension EnvironmentValues {
    @Entry var openMediaDetail: ((MediaResult) -> Void)? = nil
}

struct PosterLink<Label: View>: View {
    let item: MediaResult
    @ViewBuilder var label: Label

    @Environment(\.openMediaDetail) private var openMediaDetail

    var body: some View {
        if let openMediaDetail {
            Button { openMediaDetail(item) } label: { label }
                .buttonStyle(.plain)
        } else {
            NavigationLink(value: item) { label }
                .buttonStyle(.plain)
        }
    }
}
#endif
