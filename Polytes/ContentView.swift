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

/// Pantalla principal: una cabecera fija arriba y el escritorio debajo.
/// La cabecera NO forma parte del mundo: la vista del escritorio ocupa
/// solo el espacio bajo ella, así que ningún stickman puede subirse,
/// pegarse ni quedar oculto tras la barra superior.
struct ContentView: View {
    @StateObject private var simulation = Simulation()
    @State private var showingCreator = false

    var body: some View {
        VStack(spacing: 0) {
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
            .background(Color(red: 0.05, green: 0.07, blue: 0.12))

            DesktopViewRepresentable(simulation: simulation)
        }
        .ignoresSafeArea()
        .sheet(isPresented: $showingCreator) {
            CreatorView(simulation: simulation)
        }
    }
}
