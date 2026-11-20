import SwiftUI
import UIKit

/// Puente entre SwiftUI y la vista UIKit del escritorio.
struct DesktopViewRepresentable: UIViewRepresentable {
    let simulation: Simulation
    /// Con el creador abierto, el escritorio se pausa (v5): no simula
    /// ni se repinta tras la hoja.
    var isPaused: Bool = false

    func makeUIView(context: Context) -> DesktopView {
        let view = DesktopView()
        view.simulation = simulation
        return view
    }

    func updateUIView(_ uiView: DesktopView, context: Context) {
        uiView.simulation = simulation
        uiView.setPaused(isPaused)
    }
}

/// Pantalla principal: el escritorio ocupa TODA la pantalla, borde a
/// borde, como un juego (v4) — sin cabecera fija y sin barra de estado.
/// El mundo jugable es la pantalla completa: la simulación recibe los
/// límites enteros de la vista, incluidas las zonas seguras.
///
/// Lo único que flota sobre el escritorio es el botón de crear, una
/// píldora semitransparente en la esquina superior derecha. No es una
/// superficie: ningún stickman puede subirse a él ni quedarse pegado;
/// como mucho, pasa por detrás un instante, como en los juegos.
struct ContentView: View {
    @StateObject private var simulation = Simulation()
    @State private var showingCreator = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            DesktopViewRepresentable(simulation: simulation, isPaused: showingCreator)
                .ignoresSafeArea()

            Button {
                showingCreator = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                    Text("Crear stickman")
                    Text("· \(simulation.stickmen.count)")
                        .foregroundColor(.white.opacity(0.7))
                }
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.38), in: Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1))
            }
            .padding(.top, 10)
            .padding(.trailing, 12)
        }
        .statusBarHidden(true)
        .sheet(isPresented: $showingCreator) {
            CreatorView(simulation: simulation)
        }
    }
}
