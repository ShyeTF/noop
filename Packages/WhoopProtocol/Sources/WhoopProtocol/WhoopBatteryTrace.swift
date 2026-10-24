import Foundation

/// Courbe « Batterie récente » continue.
///
/// Le bracelet rapporte sa charge toutes les huit minutes environ. Dès qu’un
/// relevé manque, la courbe était coupée en segments et laissait un trou. Ce
/// module comble les trous **intérieurs** par une interpolation cubique
/// monotone (Fritsch–Carlson), qui ne dépasse jamais les valeurs voisines :
/// une batterie qui descend ne remonte pas dans le creux.
///
/// Rien n’est inventé avant le premier relevé ni après le dernier : la courbe
/// commence et finit exactement sur une mesure réelle.
public enum WhoopBatteryTrace {
    /// Un relevé de la courbe. `measured` distingue une vraie mesure d’un point
    /// calculé pour relier deux mesures.
    public struct Sample: Equatable, Sendable {
        public let time: TimeInterval
        public let value: Double
        public let measured: Bool

        public init(time: TimeInterval, value: Double, measured: Bool) {
            self.time = time
            self.value = value
            self.measured = measured
        }
    }

    /// Pas de remplissage : un point calculé toutes les quatre minutes, soit
    /// deux fois la cadence du bracelet. Assez dense pour que le tracé soit
    /// lisse, assez lâche pour ne pas gonfler la série.
    public static let fillStepSeconds: TimeInterval = 4 * 60

    /// Garde-fou : jamais plus de points calculés que ça dans un seul trou.
    /// Un bracelet laissé de côté une semaine ne fabrique pas 2 500 points.
    public static let maxFillPerGap = 120

    /// Bornes d’un pourcentage de charge.
    public static let valueRange: ClosedRange<Double> = 0...100

    /// Ramène un pourcentage dans `valueRange`.
    ///
    /// Les **mesures** y passent aussi, pas seulement les points calculés : un
    /// relevé aberrant (bracelet qui annonce 150 %) ressortait tel quel et
    /// sortait de la zone de tracé, par-dessus le reste de l’écran.
    private static func clamped(_ value: Double) -> Double {
        min(max(value, valueRange.lowerBound), valueRange.upperBound)
    }

    /// Courbe continue à partir des relevés bruts.
    ///
    /// - Parameters:
    ///   - points: relevés `(instant, pourcentage)`, dans n’importe quel ordre.
    ///   - step: écart visé entre deux points calculés.
    /// - Returns: les mesures d’origine, triées, plus les points calculés qui
    ///   comblent les écarts supérieurs à `step`. Moins de deux mesures : la
    ///   liste est renvoyée telle quelle, sans rien inventer.
    public static func continuous(
        points: [(time: TimeInterval, value: Double)],
        step: TimeInterval = fillStepSeconds
    ) -> [Sample] {
        let measured = ordered(points)
        guard measured.count >= 2, step > 0 else {
            return measured.map { Sample(time: $0.time, value: $0.value, measured: true) }
        }
        let tangents = monotoneTangents(measured)

        var filled: [Sample] = []
        filled.reserveCapacity(measured.count * 2)
        for index in measured.indices {
            let start = measured[index]
            filled.append(Sample(time: start.time, value: start.value, measured: true))
            guard index + 1 < measured.count else { break }
            let end = measured[index + 1]
            let width = end.time - start.time
            let spans = width / step
            guard spans.isFinite, spans > 1 else { continue }
            // `count` points strictement entre les deux mesures : la mesure
            // suivante est ajoutée au tour d’après, jamais dupliquée ici.
            // Le plafond est appliqué avant la conversion : un horodatage
            // aberrant ne doit pas faire déborder l’entier.
            let wanted = Int(min(spans.rounded(.down), Double(maxFillPerGap) + 1)) - 1
            let count = max(wanted, 0)
            guard count > 0 else { continue }
            for position in 1...count {
                let ratio = Double(position) / Double(count + 1)
                let time = start.time + width * ratio
                let value = hermite(
                    start: start, end: end,
                    startTangent: tangents[index], endTangent: tangents[index + 1],
                    ratio: ratio)
                filled.append(Sample(time: time, value: clamped(value), measured: false))
            }
        }
        return filled
    }

    /// Relevés bornés puis triés par instant, doublons d’instant écartés
    /// (le dernier relevé fourni gagne).
    private static func ordered(
        _ points: [(time: TimeInterval, value: Double)]
    ) -> [(time: TimeInterval, value: Double)] {
        let usable = points
            .filter { $0.time.isFinite && $0.value.isFinite }
            .map { (time: $0.time, value: clamped($0.value)) }
        // Tri stable sur (instant, rang d’origine) : à instant égal, le dernier
        // relevé fourni gagne, sans dépendre de la stabilité de `sorted`.
        let sorted = usable.enumerated()
            .sorted { ($0.element.time, $0.offset) < ($1.element.time, $1.offset) }
            .map { $0.element }
        var result: [(time: TimeInterval, value: Double)] = []
        result.reserveCapacity(sorted.count)
        for point in sorted {
            if let last = result.last, last.time == point.time {
                result[result.count - 1] = point
            } else {
                result.append(point)
            }
        }
        return result
    }

    /// Pentes de Fritsch–Carlson : la courbe reste monotone sur chaque
    /// intervalle, donc elle ne dépasse jamais ses deux mesures voisines.
    private static func monotoneTangents(
        _ points: [(time: TimeInterval, value: Double)]
    ) -> [Double] {
        let count = points.count
        var secants = [Double](repeating: 0, count: max(0, count - 1))
        for index in 0..<(count - 1) {
            let width = points[index + 1].time - points[index].time
            secants[index] = width > 0 ? (points[index + 1].value - points[index].value) / width : 0
        }
        var tangents = [Double](repeating: 0, count: count)
        tangents[0] = secants[0]
        tangents[count - 1] = secants[count - 2]
        for index in 1..<(count - 1) {
            // Changement de sens ou palier : tangente nulle, pas de dépassement.
            if secants[index - 1] * secants[index] <= 0 {
                tangents[index] = 0
            } else {
                tangents[index] = (secants[index - 1] + secants[index]) / 2
            }
        }
        for index in 0..<(count - 1) {
            if secants[index] == 0 {
                tangents[index] = 0
                tangents[index + 1] = 0
                continue
            }
            let alpha = tangents[index] / secants[index]
            let beta = tangents[index + 1] / secants[index]
            let norm = alpha * alpha + beta * beta
            if norm > 9 {
                let scale = 3 / norm.squareRoot()
                tangents[index] = scale * alpha * secants[index]
                tangents[index + 1] = scale * beta * secants[index]
            }
        }
        return tangents
    }

    /// Hermite cubique sur `[start, end]`, `ratio` entre 0 et 1.
    private static func hermite(
        start: (time: TimeInterval, value: Double),
        end: (time: TimeInterval, value: Double),
        startTangent: Double,
        endTangent: Double,
        ratio: Double
    ) -> Double {
        let width = end.time - start.time
        let squared = ratio * ratio
        let cubed = squared * ratio
        let h00 = 2 * cubed - 3 * squared + 1
        let h10 = cubed - 2 * squared + ratio
        let h01 = -2 * cubed + 3 * squared
        let h11 = cubed - squared
        return h00 * start.value
            + h10 * width * startTangent
            + h01 * end.value
            + h11 * width * endTangent
    }
}
