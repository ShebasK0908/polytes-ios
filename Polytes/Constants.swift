import CoreGraphics

/// Valores de ajuste del mundo y del cuerpo. Son los mismos valores de
/// comportamiento del diseño original: tamaños en puntos, tiempos en
/// segundos y un paso fijo de simulación. Desde la v2 (escritorio apaisado
/// y espacioso) el cuerpo se dibuja a escala reducida: todas las medidas
/// del cuerpo y lo que depende de ellas (zancada, velocidad de paseo,
/// tolerancia de apoyo) llevan el factor `bodyScale`.
enum C {
    /// Escala del cuerpo respecto al diseño original (v2: 0,6).
    static let bodyScale: Double = 0.6

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
    /// Fricción de un punto del ragdoll apoyado en una superficie (v5):
    /// fracción de su velocidad horizontal que pierde en cada paso.
    /// Sin ella, un cuerpo caído se deslizaba y se plegaba sobre sí
    /// mismo hasta hacerse un nudo.
    static let ragdollGroundFriction: Double = 0.45
    /// Cada cuántas iteraciones del solver se reaplican los contactos
    /// por punto dentro del bucle (estabilidad del reposo sin coste).
    static let ragdollContactEvery: Int = 4
    /// Tiempo de contacto estable (varios puntos apoyados y cuerpo
    /// casi quieto) tras el que un cuerpo en vuelo se da por aterrizado.
    static let ragdollRestSettleTime: Double = 0.22

    static let stickmanWidth: Double = 100 * bodyScale
    static let stickmanHeight: Double = 145 * bodyScale
    static let groundSnapTolerance: Double = 10 * bodyScale
    static let decideCooldownDefault: Double = 3

    static let stroke: Double = 9 * bodyScale
    static let ragPointRadius: Double = 10 * bodyScale
    static let hollowHeadDiameter: Double = 38 * bodyScale
    static let filledHeadDiameter: Double = 30 * bodyScale

    static let torsoLength: Double = 37 * bodyScale
    /// Distancia desde la parte superior de la caja hasta la cadera.
    static let hipHeightFromTop: Double = stroke + hollowHeadDiameter + torsoLength
    static let upperArmLength: Double = 24 * bodyScale
    static let forearmLength: Double = 23 * bodyScale
    static let upperLegLength: Double = 28 * bodyScale
    static let lowerLegLength: Double = 27 * bodyScale

    static let defaultCycleDuration: Double = 0.5
    /// Zancada por ciclo y velocidad de paseo: escalan con el cuerpo para
    /// mantener la misma cadencia y que los pies no patinen.
    static let distancePerWalkCycle: Double = 67 * bodyScale
    static let defaultWalkSpeed: Double = 170 * bodyScale

    static let scoreMargin: Double = 0.3
    static let landingRecoveryTime: Double = 3

    /// Altura de la barra inferior del escritorio (el suelo base es su borde superior).
    static let taskbarHeight: Double = 48
    /// Radio de búsqueda táctil al agarrar una articulación. En el original,
    /// pensado para ratón, el radio era mínimo; en una pantalla táctil se
    /// amplía y se elige siempre la articulación más cercana al dedo.
    /// No escala con el cuerpo: debe seguir siendo cómodo para el dedo
    /// (~30 pt) aunque el stickman sea más pequeño.
    static let grabSearchRadius: Double = 30
    /// Altura de la barra de título de las ventanas del escritorio.
    static let windowTitleBarHeight: Double = 30

    // MARK: - Combate y poderes (v3)

    /// Irritación que suma cada agarre del dedo.
    static let irritationGrabGain: Double = 18
    /// Irritación que se enfría por segundo cuando no hay represalia activa.
    static let irritationDecayPerSecond: Double = 4.0
    /// Duración de la represalia contra el dedo.
    static let retaliationDuration: Double = 3.2
    /// Tiempo tras una represalia en el que no puede volver a explotar.
    static let retaliationCooldown: Double = 9
    /// Duración máxima de una pelea antes de darla por terminada.
    static let fightMaxDuration: Double = 14
    /// Cooldown de peleas tras cada enfrentamiento (rango aleatorio).
    /// (v4: más largo, para que el escritorio se sienta vivo pero no
    /// en guerra constante.)
    static let fightCooldownMin: Double = 30
    static let fightCooldownMax: Double = 50
    /// Velocidad de crucero del vuelo con motor (pt/s).
    static let flightSpeed: Double = 430
    /// Velocidad del dash de supervelocidad (pt/s) y su duración.
    static let dashSpeed: Double = 1500
    static let dashDuration: Double = 0.16
    /// Velocidad de las bolas de fuego (pt/s).
    static let fireballSpeed: Double = 660
    /// Tiempo de carga visible del superpuñetazo.
    static let superPunchChargeTime: Double = 0.55
    /// Tope de partículas vivas a la vez (rendimiento).
    static let maxParticles: Int = 700
}

func clampValue(_ value: Double, _ low: Double, _ high: Double) -> Double {
    return max(low, min(high, value))
}

/// Punto a partir de dos Double (los impulsos y velocidades de combate
/// se calculan en Double y CGPoint trabaja en CGFloat).
func cgPoint(_ x: Double, _ y: Double) -> CGPoint {
    CGPoint(x: CGFloat(x), y: CGFloat(y))
}
