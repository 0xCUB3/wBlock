//
//  SearchableToolbarModifier.swift
//  wBlock
//
//  Created by Alexander Skula on 1/27/26.
//

import SwiftUI

struct SearchableToolbarModifier: ViewModifier {
    @Binding var text: String
    @Binding var isPresented: Bool
    let prompt: LocalizedStringKey

    func body(content: Content) -> some View {
        #if os(iOS)
            if #available(iOS 17.0, *) {
                content
                    .searchable(text: $text, isPresented: $isPresented, placement: .toolbar, prompt: prompt)
                    .searchToolbarBehavior(.minimize)
            } else {
                content
                    .searchable(text: $text, placement: .toolbar, prompt: prompt)
            }
        #else
            if #available(macOS 14.0, *) {
                content
                    .searchable(text: $text, isPresented: $isPresented, placement: .toolbar, prompt: prompt)
            } else {
                content
                    .searchable(text: $text, placement: .toolbar, prompt: prompt)
            }
        #endif
    }
}
