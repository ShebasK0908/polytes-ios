import SwiftUI
import UIKit

/// Puente entre SwiftUI y la vista UIKit del escritorio.
struct DesktopViewRepresentable: UIViewRepresentable {
    let simulation: Simulation

    func makeUIView(context: Context) -> DesktopView {
        let view = DesktopView()
        view.simulation = simulation
        return view
    }

    func updateUIView(_ uiView: DesktopView, context: Context) {
        uiView.simulation = simulation
    }
}

/// Pantalla principal: el escritorio a pantalla completa y una barra
/// superior fina con el acceso al creador de stickmen.
struct ContentView: View {
    @StateObject private var simulation = Simulation()
    @State private var showingCreator = false

    var body: some View {
        ZStack(alignment: .top) {
            DesktopViewRepresentable(simulation: simulation)
                .ignoresSafeArea()

            HStack {
                Text("Polytes")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Text("\(simulation.stickmen.count) en escena")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.75))
                Button {
                    showingCreator = true
                } label: {
                    Label("Crear stickman", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.35))
        }
        .sheet(isPresented: $showingCreator) {
            CreatorView(simulation: simulation)
        }
    }
}
