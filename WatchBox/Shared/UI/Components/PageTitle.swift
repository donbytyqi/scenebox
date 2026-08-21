//
//  PageTitle.swift
//  SceneBox
//
//  Created by SpontaneousArray on 16.08.26.
//

import SwiftUI

extension View {
    func pageTitle(_ title: String) -> some View {
        #if os(tvOS)
        toolbar(.hidden, for: .navigationBar)
        #else
        navigationTitle(title)
        #endif
    }
}

struct PageTitleRow: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        #if os(tvOS)
        Text(title)
            .font(.largeTitle.weight(.bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            .accessibilityAddTraits(.isHeader)
        #else
        EmptyView()
        #endif
    }
}
