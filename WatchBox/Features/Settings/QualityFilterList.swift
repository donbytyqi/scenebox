//
//  QualityFilterList.swift
//  SceneBox
//
//  Created by SpontaneousArray on 31.07.26.
//

import SwiftUI

struct QualityFilterList: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        List {
            PageTitleRow("Hide qualities")
            Section {
                ForEach(QualityFilter.offered) { quality in
                    Button {
                        toggle(quality)
                    } label: {
                        HStack {
                            Text(quality.title)
                                .foregroundStyle(.white)
                            Spacer()
                            if settings.excludedQualities.contains(quality) {
                                Image(systemName: "checkmark")
                                    #if os(tvOS)
                                    .foregroundStyle(.white)
                                    #else
                                    .foregroundStyle(Theme.accent)
                                    #endif
                            }
                        }
                    }
                }
            } footer: {
                Text("Checked qualities are hidden from release lists.")
            }
        }
        .hideScrollBackground()
        .background(Theme.background)
        .pageTitle("Hide qualities")
        .inlineNavigationBar()
    }

    private func toggle(_ quality: QualityFilter) {
        if settings.excludedQualities.contains(quality) {
            settings.excludedQualities.remove(quality)
        } else {
            settings.excludedQualities.insert(quality)
        }
    }
}
