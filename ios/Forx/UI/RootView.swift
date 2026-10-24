import SwiftUI

struct RootView: View {
    let store: JeepStore

    var body: some View {
        PanelWebView(store: store)
            .ignoresSafeArea()
            .background(Color.black.ignoresSafeArea())
    }
}
