import SwiftUI
import ImageIO

/// A cover in its own 112-unit coordinate system. Wordless instances are decorative.
struct GeneratedCoverView: View {
    let recipe: GeneratedCoverRecipe
    let width: CGFloat
    var epubURL: URL?
    var height: CGFloat?
    var showsWords = true
    var showsArt = true
    @State private var loadedURL: URL?
    @State private var embeddedImage: Image?

    init(recipe: GeneratedCoverRecipe, width: CGFloat, epubURL: URL? = nil, height: CGFloat? = nil,
         showsWords: Bool = true, showsArt: Bool = true) {
        self.recipe = recipe
        self.width = width
        self.epubURL = epubURL
        self.height = height
        self.showsWords = showsWords
        self.showsArt = showsArt
    }

    private var coverHeight: CGFloat { height ?? width * 1.42 }

    var body: some View {
        ZStack {
            if showsArt, let epubURL, loadedURL == epubURL, let embeddedImage {
                embeddedImage.resizable().scaledToFill()
                    .frame(width: width, height: coverHeight).clipped()
            } else {
                Canvas(opaque: true) { context, size in
                    let unit = size.width / 112
                    context.scaleBy(x: unit, y: unit)
                    let h = size.height / unit
                    drawGround(in: &context, height: h)
                    if showsArt { drawMotif(in: &context, height: h, sparse: width < 64) }
                }
                if showsWords { words }
            }
        }
        .frame(width: width, height: coverHeight)
        .clipShape(RoundedRectangle(cornerRadius: width * 0.125, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([recipe.title, recipe.author, recipe.fandom]
            .filter { !$0.isEmpty }.joined(separator: ", "))
        .accessibilityHidden(!showsWords)
        .task(id: epubURL) {
            loadedURL = nil
            embeddedImage = nil
            guard showsArt, let epubURL else { return }
            let data = await Task.detached(priority: .utility) {
                EmbeddedWorkCoverImage.data(at: epubURL)
            }.value
            guard !Task.isCancelled, let data,
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return }
            embeddedImage = Image(decorative: image, scale: 1)
            loadedURL = epubURL
        }
    }

    private func drawGround(in context: inout GraphicsContext, height: CGFloat) {
        let l = recipe.lightness
        let hue = Double(recipe.hues[0])
        let main = Self.oklch(l, 0.085, hue)
        let light = Self.oklch(l + 0.07, 0.09, hue + 14)
        let dark = Self.oklch(l - 0.05, 0.08, hue - 10)
        let bounds = CGRect(x: 0, y: 0, width: 112, height: height)
        switch recipe.ground {
        case .gradient:
            context.fill(Path(bounds), with: .linearGradient(
                Gradient(colors: [main, light]),
                startPoint: CGPoint(x: 19, y: 0), endPoint: CGPoint(x: 93, y: height)
            ))
        case .split:
            context.fill(Path(bounds), with: .color(main))
            context.fill(Path(CGRect(x: 0, y: height * 0.58, width: 112, height: height * 0.42)), with: .color(light))
        case .band:
            context.fill(Path(bounds), with: .color(main))
            context.fill(Path(CGRect(x: 0, y: height * 0.62, width: 112, height: height * 0.12)), with: .color(dark))
        case .solid:
            context.fill(Path(bounds), with: .color(main))
        case .crossover:
            let count = recipe.hues.count
            for index in 0..<count {
                let start = count == 2 ? (index == 0 ? 0.0 : 0.6) : Double(index) / Double(count)
                let end = count == 2 ? (index == 0 ? 0.6 : 1.0) : Double(index + 1) / Double(count)
                // Projection onto the 135° gradient axis gives hard diagonal bands.
                func point(_ t: Double, _ offset: Double) -> CGPoint {
                    CGPoint(x: 112 * t + offset, y: height * t - offset * height / 112)
                }
                var band = Path()
                band.move(to: point(start, -height))
                band.addLine(to: point(start, 112))
                band.addLine(to: point(end, 112))
                band.addLine(to: point(end, -height))
                band.closeSubpath()
                context.fill(band, with: .color(Self.oklch(l, 0.085, Double(recipe.hues[index]))))
            }
        }
    }

    private func drawMotif(in context: inout GraphicsContext, height: CGFloat, sparse: Bool) {
        let centre = CGPoint(x: recipe.placement == 2 ? 32 : 80,
                             y: height * (recipe.placement == 0 ? 0.314 : recipe.placement == 1 ? 0.742 : 0.73))
        let density = [0.7, 0.95, 1.2, 1.5][sparse ? 0 : recipe.tier]
        var rng = GeneratedCoverRecipe.Random(seed: recipe.shapeSeed)
        let path = Self.motif(recipe.motif, centre: centre, radius: 46, density: density, random: &rng)
        var art = context
        art.translateBy(x: centre.x, y: centre.y)
        art.rotate(by: .degrees(recipe.rotation))
        art.scaleBy(x: CGFloat(recipe.scale), y: CGFloat(recipe.scale))
        art.translateBy(x: -centre.x, y: -centre.y)
        let white = Color.white.opacity(recipe.opacity)
        if recipe.motif == "petals" || recipe.motif == "halftone" {
            art.fill(path, with: .color(Color.white.opacity(recipe.opacity * 0.8)))
        } else {
            art.stroke(path, with: .color(white), style: StrokeStyle(
                lineWidth: CGFloat(max(recipe.lineWidth, sparse ? 0.9 * 112 / Double(width) : 0) / recipe.scale),
                lineCap: .round, lineJoin: .round
            ))
        }
        guard recipe.hasRing else { return }
        let radius = CGFloat(46 * 1.16 * recipe.scale)
        var ring = Path()
        if recipe.closedRing {
            ring.addEllipse(in: CGRect(x: centre.x - radius, y: centre.y - radius,
                                       width: 2 * radius, height: 2 * radius))
        } else {
            let middle = atan2(Double(height / 2 - centre.y), Double(56 - centre.x))
            ring.addArc(center: centre, radius: radius,
                        startAngle: .radians(middle + 0.6),
                        endAngle: .radians(middle - 0.6), clockwise: false)
        }
        context.stroke(ring, with: .color(white), style: StrokeStyle(
            lineWidth: CGFloat(max(1.2, sparse ? 0.9 * 112 / Double(width) : 0)), lineCap: .round
        ))
    }

    private var words: some View {
        let size: CGFloat = {
            let count = recipe.title.count
            let base: CGFloat = count <= 12 && !recipe.title.contains(" ") ? 22 : count <= 32 ? 15 : count <= 64 ? 13 : 12
            return width / 112 * (recipe.titleStyle == 2 ? base * 0.8 : base)
        }()
        let align: HorizontalAlignment = recipe.placement == 2 ? .trailing : .leading
        return VStack(alignment: align, spacing: width * 0.035) {
            if recipe.placement != 1 { fandomLabel }
            if recipe.placement == 0 { Spacer(minLength: 0) }
            if recipe.placement == 2 { Spacer().frame(height: width * 0.08) }
            Text(recipe.title)
                .font(recipe.titleStyle == 2 ? .system(size: size, weight: .bold) :
                        recipe.titleStyle == 1 ? .system(size: size, weight: .semibold, design: .serif).italic() :
                        .system(size: size, weight: .semibold, design: .serif))
                .textCase(recipe.titleStyle == 2 ? .uppercase : nil)
                .tracking(recipe.titleStyle == 2 ? width / 112 * 0.6 : 0)
                .lineLimit(3)
                .multilineTextAlignment(recipe.placement == 2 ? .trailing : .leading)
            if !recipe.subtitle.isEmpty {
                Text(recipe.subtitle).lineLimit(2).font(.system(size: width * 0.09).italic())
            }
            Text(recipe.author).lineLimit(1).font(.system(size: width * 0.09).italic())
            if recipe.placement == 1 { Spacer(minLength: 0); fandomLabel }
            if recipe.placement == 2 { Spacer(minLength: 0) }
        }
        .foregroundStyle(.white)
        .padding(width * 0.1)
    }

    private var fandomLabel: some View {
        HStack(spacing: 3) {
            Text(recipe.fandom.uppercased()).lineLimit(1)
                .foregroundStyle(Color.white.opacity(0.88))
            if recipe.part > 0 {
                Text("PART \(recipe.part <= 5 ? ["", "I", "II", "III", "IV", "V"][recipe.part] : String(recipe.part))")
            }
        }
        .font(.system(size: width * 0.076, weight: .semibold))
    }

    // OKLCH to clipped sRGB; canvas and contrast tests use the same conversion.
    static func rgb(_ lightness: Double, _ chroma: Double, _ hue: Double) -> (Double, Double, Double) {
        let angle = hue * .pi / 180
        let a = chroma * cos(angle), b = chroma * sin(angle)
        let l = pow(lightness + 0.3963377774 * a + 0.2158037573 * b, 3)
        let m = pow(lightness - 0.1055613458 * a - 0.0638541728 * b, 3)
        let s = pow(lightness - 0.0894841775 * a - 1.2914855480 * b, 3)
        func encode(_ value: Double) -> Double {
            let x = min(max(value, 0), 1)
            return x <= 0.0031308 ? 12.92 * x : 1.055 * pow(x, 1 / 2.4) - 0.055
        }
        return (encode(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
                encode(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
                encode(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s))
    }

    static func oklch(_ lightness: Double, _ chroma: Double, _ hue: Double) -> Color {
        let (r, g, b) = rgb(lightness, chroma, hue)
        return Color(red: r, green: g, blue: b)
    }

    private static func motif(_ kind: String, centre: CGPoint, radius r: Double,
                              density: Double, random rng: inout GeneratedCoverRecipe.Random) -> Path {
        let cx = Double(centre.x), cy = Double(centre.y)
        func point(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: CGFloat(x), y: CGFloat(y)) }
        func ellipse(_ path: inout Path, _ x: Double, _ y: Double, _ rx: Double, _ ry: Double) {
            path.addEllipse(in: CGRect(x: CGFloat(x - rx), y: CGFloat(y - ry),
                                       width: CGFloat(rx * 2), height: CGFloat(ry * 2)))
        }
        func count(_ low: Int, _ high: Int, min minimum: Int = 3, random: inout GeneratedCoverRecipe.Random) -> Int {
            max(minimum, Int((Double(random.integer(low, high)) * density).rounded()))
        }
        var path = Path()
        switch kind {
        case "sprig":
            let base = point(cx - r * 0.12, cy + r * 0.95)
            let end = point(cx + r * 0.10, cy - r * 0.85)
            let c1 = point(cx - r * 0.28, cy + r * 0.25), c2 = point(cx + r * 0.24, cy - r * 0.25)
            path.move(to: base); path.addCurve(to: end, control1: c1, control2: c2)
            let n = max(3, Int((Double(rng.integer(5, 7)) * density * 0.8).rounded()))
            for i in 0..<n {
                let t = Double(i + 1) / Double(n + 1), u = 1 - t
                let x = pow(u, 3) * Double(base.x) + 3 * u * u * t * Double(c1.x) + 3 * u * t * t * Double(c2.x) + pow(t, 3) * Double(end.x)
                let y = pow(u, 3) * Double(base.y) + 3 * u * u * t * Double(c1.y) + 3 * u * t * t * Double(c2.y) + pow(t, 3) * Double(end.y)
                let side = i.isMultiple(of: 2) ? 1.0 : -1.0, len = r * rng.between(0.32, 0.48)
                path.move(to: point(x, y))
                path.addQuadCurve(to: point(x + side * len, y - len * 0.55),
                                  control: point(x + side * len * 0.25, y - len * 0.75))
                path.addQuadCurve(to: point(x, y), control: point(x + side * len * 0.75, y - len * 0.1))
            }
        case "orbit":
            let n = max(3, Int((Double(rng.integer(6, 8)) * density * 0.8).rounded())) * 2
            for i in 0..<(n / 2) {
                let a = Double(i) * 2 * .pi / Double(n)
                path.move(to: point(cx + cos(a) * r, cy + sin(a) * r))
                path.addLine(to: point(cx - cos(a) * r, cy - sin(a) * r))
            }
            ellipse(&path, cx, cy, r * 0.62, r * 0.62)
        case "rings":
            let base = rng.between(0, 2 * .pi)
            let n = max(2, Int((5 * density * 0.8).rounded()))
            for i in 0..<n {
                let rr = r * Double(i + 1) / Double(n), shift = (r - rr) * 0.45
                ellipse(&path, cx + cos(base + Double(i) * 0.35) * shift,
                        cy + sin(base + Double(i) * 0.35) * shift, rr, rr)
            }
        case "moire":
            let offset = r * rng.between(0.18, 0.32), angle = rng.next() * 2 * .pi
            let n = max(2, Int((3.5 * density).rounded()))
            for group in 0..<2 {
                for i in 1...n {
                    let rr = r * Double(i) / Double(n) * 1.1
                    ellipse(&path, cx + Double(group) * cos(angle) * offset,
                            cy + Double(group) * sin(angle) * offset, rr, rr)
                }
            }
        case "sigil":
            for i in 0...8 {
                let angle = Double((i * 3) % 8) * .pi / 4 - .pi / 2
                let p = point(cx + cos(angle) * r * 0.78, cy + sin(angle) * r * 0.78)
                if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            ellipse(&path, cx, cy, r * 0.22, r * 0.22)
        case "contours":
            let phase = rng.between(0, 2 * .pi)
            for level in 1...max(2, Int((5 * density * 0.8).rounded())) {
                let base = r * 0.85 * Double(level) / Double(max(2, Int((5 * density * 0.8).rounded())))
                for step in 0...48 {
                    let a = Double(step) / 48 * 2 * .pi
                    let rr = base * (1 + 0.14 * sin(3 * a + phase) + 0.08 * cos(5 * a - phase))
                    let p = point(cx + cos(a) * rr, cy + sin(a) * rr * 0.78)
                    if step == 0 { path.move(to: p) } else { path.addLine(to: p) }
                }
            }
        case "guilloche":
            let fa = rng.integer(3, 5), phase = rng.between(0.2, 1.4)
            for step in 0...180 {
                let t = Double(step) / 180 * 2 * .pi
                let p = point(cx + sin(Double(fa) * t + phase) * r * 0.65,
                              cy + sin(Double(fa + 1) * t) * r * 0.65)
                if step == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
        case "waves":
            let n = count(3, 5, random: &rng), amp = r * rng.between(0.08, 0.16), freq = rng.between(1.5, 3)
            for i in 0..<n {
                let y = cy - r + Double(i) * 2 * r / Double(n - 1)
                for step in 0...40 {
                    let t = Double(step) / 40
                    let p = point(cx - r * 1.3 + t * 2.6 * r, y + sin(t * 2 * .pi * freq + Double(i) * 0.6) * amp)
                    if step == 0 { path.move(to: p) } else { path.addLine(to: p) }
                }
            }
        case "halftone":
            let step = r * rng.between(0.2, 0.28) / density, limit = r * 1.25
            for y in stride(from: -limit, through: limit, by: step) {
                for x in stride(from: -limit, through: limit, by: step) {
                    let size = step * 0.45 * (1 - hypot(x, y) / limit)
                    if size > 0.6 { ellipse(&path, cx + x, cy + y, size, size) }
                }
            }
        case "truchet":
            let n = max(2, Int((4 * density).rounded())), side = r * 2.5 / Double(n), half = side / 2
            for y in 0..<n { for x in 0..<n {
                let px = cx - r * 1.25 + Double(x) * side, py = cy - r * 1.25 + Double(y) * side
                let flip = rng.next() < 0.5
                path.move(to: point(px + half, py))
                path.addArc(center: point(flip ? px : px + side, py), radius: CGFloat(half),
                            startAngle: .degrees(flip ? 0 : 180), endAngle: .degrees(90), clockwise: !flip)
                path.move(to: point(flip ? px + side : px, py + half))
                path.addArc(center: point(flip ? px + side : px, py + side), radius: CGFloat(half),
                            startAngle: .degrees(-90), endAngle: .degrees(flip ? -180 : 0), clockwise: flip)
            } }
        case "rosette":
            let petals = rng.integer(3, 7), outer = r * 0.8, inner = outer / Double(petals)
            let distance = inner * rng.between(0.8, 1.6)
            for step in 0...360 {
                let t = Double(step) / 360 * 2 * .pi
                let p = point(cx + (outer - inner) * cos(t) + distance * cos(Double(petals - 1) * t),
                              cy + (outer - inner) * sin(t) - distance * sin(Double(petals - 1) * t))
                if step == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
        case "sunburst":
            let n = count(7, 10, min: 5, random: &rng)
            for i in 0..<n {
                let a = Double(i) / Double(n) * 2 * .pi
                path.move(to: point(cx + cos(a) * r * 0.25, cy + sin(a) * r * 0.25))
                path.addLine(to: point(cx + cos(a) * r * 1.4, cy + sin(a) * r * 1.4))
            }
        case "constellation":
            let n = count(5, 7, min: 4, random: &rng)
            var stars: [(Double, Double, Double)] = []
            for _ in 0..<n {
                let a = rng.next() * 2 * .pi, rad = r * (0.25 + rng.next() * 0.9)
                stars.append((a, cx + cos(a) * rad, cy + sin(a) * rad))
            }
            stars.sort { $0.0 < $1.0 }
            for (index, star) in stars.enumerated() {
                if index == 0 { path.move(to: point(star.1, star.2)) }
                else { path.addLine(to: point(star.1, star.2)) }
            }
            for star in stars { ellipse(&path, star.1, star.2, 1.8, 1.8) }
        case "chevrons":
            let n = count(3, 5, random: &rng)
            for i in 0..<n {
                let y = cy - r * 0.9 + Double(i) * r * 0.32
                path.move(to: point(cx - r, y + r * 0.3))
                path.addLine(to: point(cx, y - r * 0.05))
                path.addLine(to: point(cx + r, y + r * 0.3))
            }
        case "squares":
            let step = rng.between(6, 12) * .pi / 180, n = max(2, Int((4 * density).rounded()))
            for i in 0..<n {
                let side = r * (1.1 - Double(i) * 0.15), angle = Double(i) * step
                for corner in 0..<4 {
                    let a = angle + .pi / 4 + Double(corner) * .pi / 2
                    let p = point(cx + cos(a) * side, cy + sin(a) * side)
                    if corner == 0 { path.move(to: p) } else { path.addLine(to: p) }
                }
                path.closeSubpath()
            }
        case "petals":
            let n = count(4, 6, random: &rng)
            for i in 0..<n {
                let a = Double(i) / Double(n) * 2 * .pi
                path.move(to: centre)
                path.addQuadCurve(to: point(cx + cos(a) * r, cy + sin(a) * r),
                                  control: point(cx + cos(a - 0.32) * r * 0.72, cy + sin(a - 0.32) * r * 0.72))
                path.addQuadCurve(to: centre,
                                  control: point(cx + cos(a + 0.32) * r * 0.72, cy + sin(a + 0.32) * r * 0.72))
            }
        default: break
        }
        return path
    }
}
