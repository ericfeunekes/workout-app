// DSExerciseIconView.swift
//
// Small, token-aligned exercise and workout block glyphs. These are SwiftUI
// mirrors of the editable SVG masters in `docs/design/icons/exercise-icons.svg`.

import SwiftUI

public enum DSExerciseIcon: String, CaseIterable, Sendable {
    case strength
    case conditioning
    case run
    case warmUp
    case rest
    case timer
    case bodyweight
    case dumbbell
    case barbell
    case kettlebell
    case row
    case bike
    case mobility
    case benchPress
    case inclineBenchPress

    var accessibilityLabel: String {
        switch self {
        case .strength: "Strength"
        case .conditioning: "Conditioning"
        case .run: "Run"
        case .warmUp: "Warm-up"
        case .rest: "Rest"
        case .timer: "Timer"
        case .bodyweight: "Bodyweight"
        case .dumbbell: "Dumbbell"
        case .barbell: "Barbell"
        case .kettlebell: "Kettlebell"
        case .row: "Row"
        case .bike: "Bike"
        case .mobility: "Mobility"
        case .benchPress: "Bench press"
        case .inclineBenchPress: "Incline bench press"
        }
    }
}

public struct DSExerciseIconView: View {
    private let icon: DSExerciseIcon
    private let size: CGFloat
    private let showsTile: Bool

    public init(
        icon: DSExerciseIcon,
        size: CGFloat = 32,
        showsTile: Bool = false
    ) {
        self.icon = icon
        self.size = size
        self.showsTile = showsTile
    }

    public var body: some View {
        let strokeWidth = max(1.4, size / 13.5)
        let iconSize = showsTile ? size * 0.58 : size

        ZStack {
            if showsTile {
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .fill(DSColors.surface)
                    .overlay {
                        RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                            .stroke(DSColors.border, lineWidth: 1)
                    }
            }

            ZStack {
                DSExerciseIconGlyph(icon: icon, layer: .primary)
                    .stroke(
                        DSColors.foreground,
                        style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round, lineJoin: .round)
                    )
                DSExerciseIconGlyph(icon: icon, layer: .accent)
                    .stroke(
                        DSColors.accent,
                        style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round, lineJoin: .round)
                    )
            }
            .frame(width: iconSize, height: iconSize)
        }
        .frame(width: size, height: size)
        .accessibilityLabel(Text(icon.accessibilityLabel))
    }
}

private enum DSExerciseIconLayer {
    case primary
    case accent
}

private struct DSExerciseIconGlyph: Shape {
    let icon: DSExerciseIcon
    let layer: DSExerciseIconLayer

    func path(in rect: CGRect) -> Path {
        scaled(basePath(), in: rect)
    }

    private func basePath() -> Path {
        switch (icon, layer) {
        case (.strength, .primary):
            return lines([[(5, 15), (19, 15)], [(7, 10), (17, 10)], [(8, 7), (8, 17)], [(16, 7), (16, 17)]])
        case (.strength, .accent):
            return lines([[(10, 5), (14, 5)]])

        case (.conditioning, .primary):
            var path = Path()
            path.addArc(center: CGPoint(x: 12, y: 14), radius: 7, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
            addLine(&path, from: (6, 18), to: (18, 18))
            return path
        case (.conditioning, .accent):
            return lines([[(12, 7), (12, 14), (16, 16)]])

        case (.run, .primary):
            var path = Path()
            path.addEllipse(in: CGRect(x: 12.8, y: 3.3, width: 3.4, height: 3.4))
            addPolyline(&path, [(13, 8), (10, 12), (13, 14), (15, 11)])
            return path
        case (.run, .accent):
            return lines([[(9, 12), (6, 13)], [(13, 14), (11, 19)], [(15, 11), (19, 13)]])

        case (.warmUp, .primary):
            var path = Path()
            path.move(to: CGPoint(x: 7, y: 17))
            path.addCurve(to: CGPoint(x: 12, y: 7), control1: CGPoint(x: 7, y: 13), control2: CGPoint(x: 12, y: 12))
            path.addCurve(to: CGPoint(x: 17, y: 17), control1: CGPoint(x: 15, y: 10), control2: CGPoint(x: 17, y: 13))
            path.addCurve(to: CGPoint(x: 7, y: 17), control1: CGPoint(x: 17, y: 22), control2: CGPoint(x: 7, y: 22))
            return path
        case (.warmUp, .accent):
            var path = Path()
            path.move(to: CGPoint(x: 12, y: 19))
            path.addCurve(to: CGPoint(x: 10, y: 16), control1: CGPoint(x: 10.6, y: 18.2), control2: CGPoint(x: 10, y: 17.2))
            path.addCurve(to: CGPoint(x: 12, y: 12.5), control1: CGPoint(x: 10, y: 14.6), control2: CGPoint(x: 11.1, y: 13.6))
            path.addCurve(to: CGPoint(x: 14, y: 16.4), control1: CGPoint(x: 13.1, y: 13.9), control2: CGPoint(x: 14, y: 15))
            path.addCurve(to: CGPoint(x: 12, y: 19), control1: CGPoint(x: 14, y: 17.5), control2: CGPoint(x: 13.4, y: 18.4))
            return path

        case (.rest, .primary):
            return lines([[(8, 6), (8, 18)], [(16, 6), (16, 18)]])
        case (.rest, .accent):
            return lines([[(10, 19), (16, 19)]])

        case (.timer, .primary):
            var path = Path()
            path.addEllipse(in: CGRect(x: 5, y: 6, width: 14, height: 14))
            addLine(&path, from: (10, 3), to: (14, 3))
            addLine(&path, from: (12, 6), to: (12, 8))
            return path
        case (.timer, .accent):
            return lines([[(12, 13), (16, 10)]])

        case (.bodyweight, .primary):
            var path = Path()
            path.addEllipse(in: CGRect(x: 10, y: 3, width: 4, height: 4))
            addLine(&path, from: (7, 10), to: (17, 10))
            addLine(&path, from: (12, 7), to: (12, 14))
            return path
        case (.bodyweight, .accent):
            return lines([[(8, 19), (12, 14), (16, 19)]])

        case (.dumbbell, .primary):
            return lines([[(7, 12), (17, 12)]])
        case (.dumbbell, .accent):
            return lines([[(4, 9), (4, 15)], [(7, 9), (7, 15)], [(17, 9), (17, 15)], [(20, 9), (20, 15)]])

        case (.barbell, .primary):
            return lines([[(3, 12), (21, 12)]])
        case (.barbell, .accent):
            return lines([[(5, 8), (5, 16)], [(8, 7), (8, 17)], [(16, 7), (16, 17)], [(19, 8), (19, 16)]])

        case (.kettlebell, .primary):
            var path = Path()
            path.addArc(center: CGPoint(x: 12, y: 10), radius: 4, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
            addPolyline(&path, [(7, 11), (17, 11), (18, 18), (6, 18), (7, 11)])
            return path
        case (.kettlebell, .accent):
            return lines([[(10, 11), (10, 10), (10.6, 9), (12, 8.6), (13.4, 9), (14, 10), (14, 11)]])

        case (.row, .primary):
            return lines([[(5, 17), (19, 17)], [(8, 14), (12, 8), (16, 14)]])
        case (.row, .accent):
            return lines([[(8, 10), (4, 12)], [(16, 10), (20, 12)]])

        case (.bike, .primary):
            var path = Path()
            path.addEllipse(in: CGRect(x: 3.5, y: 13, width: 6, height: 6))
            path.addEllipse(in: CGRect(x: 14.5, y: 13, width: 6, height: 6))
            return path
        case (.bike, .accent):
            return lines([[(6.5, 16), (11, 9), (14.5, 16), (6.5, 16)], [(11, 9), (15, 9)]])

        case (.mobility, .primary):
            var path = Path()
            path.move(to: CGPoint(x: 6, y: 17))
            path.addCurve(to: CGPoint(x: 18, y: 17), control1: CGPoint(x: 9, y: 11), control2: CGPoint(x: 15, y: 11))
            addLine(&path, from: (9, 6), to: (15, 6))
            return path
        case (.mobility, .accent):
            return lines([[(7, 9), (9, 11), (11, 14), (12, 17)], [(17, 9), (15, 11), (13, 14), (12, 17)]])

        case (.benchPress, .primary):
            return lines([[(5, 15), (15, 15)], [(7, 18), (17, 18)], [(8, 15), (6, 18)], [(15, 15), (17, 18)], [(9, 13), (13, 11)]])
        case (.benchPress, .accent):
            return lines([[(6, 9), (18, 9)], [(5, 7), (5, 11)], [(19, 7), (19, 11)]])

        case (.inclineBenchPress, .primary):
            return lines([[(6, 18), (18, 18)], [(8, 16), (15, 10)], [(7, 18), (8, 16)], [(16, 10), (18, 18)], [(11, 13), (14, 11)]])
        case (.inclineBenchPress, .accent):
            return lines([[(8, 8), (16, 6)], [(7, 6), (7, 10)], [(17, 4), (17, 8)]])
        }
    }

    private func scaled(_ path: Path, in rect: CGRect) -> Path {
        let size = min(rect.width, rect.height)
        let originX = rect.midX - size / 2
        let originY = rect.midY - size / 2
        return path
            .applying(CGAffineTransform(scaleX: size / 24, y: size / 24))
            .applying(CGAffineTransform(translationX: originX, y: originY))
    }

    private func lines(_ segments: [[(CGFloat, CGFloat)]]) -> Path {
        var path = Path()
        for segment in segments {
            addPolyline(&path, segment)
        }
        return path
    }

    private func addLine(_ path: inout Path, from start: (CGFloat, CGFloat), to end: (CGFloat, CGFloat)) {
        path.move(to: CGPoint(x: start.0, y: start.1))
        path.addLine(to: CGPoint(x: end.0, y: end.1))
    }

    private func addPolyline(_ path: inout Path, _ points: [(CGFloat, CGFloat)]) {
        guard let first = points.first else { return }
        path.move(to: CGPoint(x: first.0, y: first.1))
        for point in points.dropFirst() {
            path.addLine(to: CGPoint(x: point.0, y: point.1))
        }
    }
}
