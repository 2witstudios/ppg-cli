import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {
            Image(systemName: "terminal")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("PPG Mobile")
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
