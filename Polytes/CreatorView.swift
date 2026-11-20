import SwiftUI
import UIKit

/// El creador de stickmen: nombre, color y tipo de cabeza, con vista
/// previa en vivo y la personalidad que esos datos generan. Debajo, la
/// lista de stickmen en escena para poder eliminarlos.
struct CreatorView: View {
    @ObservedObject var simulation: Simulation
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var color: Color = .black
    @State private var hollowHead: Bool = true

    private var effectiveName: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Polytes" : trimmed
    }

    private var personality: Personality {
        Personality.generate(name: effectiveName, hollowHead: hollowHead, hueDegrees: hueDegrees)
    }

    /// Tono del color elegido en grados, o nil si es acromático.
    private var hueDegrees: Double? {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        UIColor(color).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return saturation < 0.05 ? nil : Double(hue) * 360
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Nuevo stickman") {
                    TextField("Nombre", text: $name)
                        .autocorrectionDisabled()

                    ColorPicker("Color", selection: $color, supportsOpacity: false)

                    HStack(spacing: 8) {
                        ForEach(presetColors, id: \.name) { preset in
                            Button {
                                color = preset.color
                            } label: {
                                Circle()
                                    .fill(preset.color)
                                    .frame(width: 26, height: 26)
                                    .overlay(Circle().stroke(Color.secondary.opacity(0.4), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Picker("Cabeza", selection: $hollowHead) {
                        Text("Hueca").tag(true)
                        Text("Rellena").tag(false)
                    }
                    .pickerStyle(.segmented)
                }

                Section("Vista previa") {
                    HStack(spacing: 16) {
                        StickmanPreview(color: UIColor(color), hollowHead: hollowHead)
                            .frame(width: 110, height: 160)
                        VStack(alignment: .leading, spacing: 10) {
                            Text(effectiveName)
                                .font(.headline)
                            traitBar(label: "Energía", value: personality.energy, tint: .orange)
                            traitBar(label: "Curiosidad", value: personality.curiosity, tint: .blue)
                            Text("La personalidad nace del nombre: el mismo nombre siempre da los mismos rasgos.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    Button {
                        simulation.addStickman(name: effectiveName, color: UIColor(color), hollowHead: hollowHead)
                        dismiss()
                    } label: {
                        HStack {
                            Spacer()
                            Text("Crear stickman").fontWeight(.semibold)
                            Spacer()
                        }
                    }
                }

                if !simulation.stickmen.isEmpty {
                    Section("En escena") {
                        ForEach(simulation.stickmen, id: \.id) { stickman in
                            HStack {
                                Circle()
                                    .fill(Color(stickman.color))
                                    .frame(width: 16, height: 16)
                                    .overlay(Circle().stroke(Color.secondary.opacity(0.4), lineWidth: 1))
                                VStack(alignment: .leading) {
                                    Text(stickman.name)
                                    Text("Energía \(stickman.energy) · Curiosidad \(stickman.curiosity) · Cabeza \(stickman.hollowHead ? "hueca" : "rellena")")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Button(role: .destructive) {
                                    simulation.removeStickman(id: stickman.id)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Crear stickman")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
    }

    private func traitBar(label: String, value: Int, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label).font(.caption)
                Spacer()
                Text("\(value)").font(.caption.weight(.bold))
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(Color.secondary.opacity(0.2))
                    RoundedRectangle(cornerRadius: 3).fill(tint)
                        .frame(width: proxy.size.width * CGFloat(value) / 100)
                }
            }
            .frame(height: 6)
        }
    }

    private var presetColors: [(name: String, color: Color)] {
        [
            ("Negro", .black),
            ("Rojo", .red),
            ("Naranja", .orange),
            ("Amarillo", .yellow),
            ("Verde", .green),
            ("Azul", .blue),
            ("Morado", .purple)
        ]
    }
}

/// Miniatura de un stickman en su pose de reposo, dibujada con la misma
/// cinemática directa y el mismo trazo que usa el escritorio.
struct StickmanPreview: View {
    let color: UIColor
    let hollowHead: Bool

    var body: some View {
        Canvas { context, size in
            let headRadius = hollowHead ? C.hollowHeadDiameter / 2 : C.filledHeadDiameter / 2
            let joints = Rig.fkJoints(pose: Animations.idle.frames[0], x: 0, y: 0, headRadius: headRadius)

            let scale = min(size.width / CGFloat(C.stickmanWidth), size.height / CGFloat(C.stickmanHeight))
            let offsetX = (size.width - CGFloat(C.stickmanWidth) * scale) / 2
            let offsetY = (size.height - CGFloat(C.stickmanHeight) * scale) / 2
            func map(_ p: CGPoint) -> CGPoint {
                CGPoint(x: offsetX + p.x * scale, y: offsetY + p.y * scale)
            }

            guard let hip = joints[.hip].map(map), let neck = joints[.neck].map(map), let head = joints[.head].map(map) else { return }
            let stroke = StrokeStyle(lineWidth: CGFloat(C.stroke) * scale, lineCap: .round, lineJoin: .round)
            let uiColor = Color(color)

            var torso = Path()
            torso.move(to: neck)
            torso.addLine(to: hip)
            context.stroke(torso, with: .color(uiColor), style: stroke)

            drawLimb(&context, from: neck, mid: joints[.elbowR].map(map), to: joints[.handR].map(map), color: uiColor, style: stroke)
            drawLimb(&context, from: neck, mid: joints[.elbowL].map(map), to: joints[.handL].map(map), color: uiColor, style: stroke)
            drawLimb(&context, from: hip, mid: joints[.kneeR].map(map), to: joints[.footR].map(map), color: uiColor, style: stroke)
            drawLimb(&context, from: hip, mid: joints[.kneeL].map(map), to: joints[.footL].map(map), color: uiColor, style: stroke)

            let radius = CGFloat(headRadius) * scale
            let headRect = CGRect(x: head.x - radius, y: head.y - radius, width: radius * 2, height: radius * 2)
            let headPath = Path(ellipseIn: headRect)
            if hollowHead {
                context.stroke(headPath, with: .color(uiColor), style: stroke)
            } else {
                context.fill(headPath, with: .color(uiColor))
            }
        }
    }

    private func drawLimb(_ context: inout GraphicsContext, from origin: CGPoint?, mid: CGPoint?, to end: CGPoint?, color: Color, style: StrokeStyle) {
        guard let origin, let mid, let end else { return }
        let straightMid = CGPoint(x: origin.x + (end.x - origin.x) / 2, y: origin.y + (end.y - origin.y) / 2)
        let control = CGPoint(x: mid.x + (straightMid.x - mid.x) * 0.5, y: mid.y + (straightMid.y - mid.y) * 0.5)
        var path = Path()
        path.move(to: origin)
        path.addQuadCurve(to: end, control: control)
        context.stroke(path, with: .color(color), style: style)
    }
}
