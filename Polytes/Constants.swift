import CoreGraphics

/// Valores de ajuste del mundo y del cuerpo. Son los mismos valores de
/// comportamiento del diseño original: tamaños en puntos, tiempos en
/// segundos y un paso fijo de simulación.
enum C {
    /// Paso fijo de la simulación (el bucle original avanzaba cada 32 ms).
    static let frameDuration: Double = 0.032

    /// Gravedad del modo con animación (px/s²).
    static let gravityAcceleration: Double = 1098
    /// Empuje vertical que recibe cada punto Verlet en cada paso.
    static let ragdollAcceleration: Double = 40
    static let ragdollDamping: Double = 0.995
    static let ragdollCenterDampingX: Double = 0.90
    static let ragdollCenterDampingY: Double = 0.90
    static let ragdollSpinFactor: Double = 0.04
    static let ragdollSolverIterations: Int = 20
    static let ragdollStiffness: Double = 0.85
    static let ragdollBounceFactor: Double = 0.7

    static let stickmanWidth: Double = 100
    static let stickmanHeight: Double = 145
    static let groundSnapTolerance: Double = 10
    static let decideCooldownDefault: Double = 3

    static let stroke: Double = 9
    static let ragPointRadius: Double = 10
    static let hollowHeadDiameter: Double = 38
    static let filledHeadDiameter: Double = 30

    static let torsoLength: Double = 37
    /// Distancia desde la parte superior de la caja hasta la cadera.
    static let hipHeightFromTop: Double = stroke + hollowHeadDiameter + torsoLength
    static let upperArmLength: Double = 24
    static let forearmLength: Double = 23
    static let upperLegLength: Double = 28
    static let lowerLegLength: Double = 27

    static let defaultCycleDuration: Double = 0.5
    static let distancePerWalkCycle: Double = 67
    static let defaultWalkSpeed: Double = 170

    static let scoreMargin: Double = 0.3
    static let landingRecoveryTime: Double = 3

    /// Altura de la barra inferior del escritorio (el suelo base es su borde superior).
    static let taskbarHeight: Double = 48
    /// Radio de búsqueda táctil al agarrar una articulación. En el original,
    /// pensado para ratón, el radio era mínimo; en una pantalla táctil se
    /// amplía y se elige siempre la articulación más cercana al dedo.
    static let grabSearchRadius: Double = 34
    /// Altura de la barra de título de las ventanas del escritorio.
    static let windowTitleBarHeight: Double = 30
}

func clampValue(_ value: Double, _ low: Double, _ high: Double) -> Double {
    return max(low, min(high, value))
}
