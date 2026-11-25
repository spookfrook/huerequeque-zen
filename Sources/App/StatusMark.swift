import AppKit

enum MenuBarPose {
    case idle
    case locked
    case guarding
    case allowtimeOpen
}

/// Monochrome Huerequeque template glyph for the macOS menu bar.
/// Clean silhouette standing on one leg, with a subtle lock or window badge depending on state.
enum StatusMark {
    static func image(pose: MenuBarPose) -> NSImage {
        let size = NSSize(width: 22, height: 18)
        let image = NSImage(size: size, flipped: true) { _ in
            NSColor.black.set()

            // Standing zen leg
            let leg = NSBezierPath()
            leg.move(to: .init(x: 7.4, y: 12.2))
            leg.line(to: .init(x: 7.4, y: 15.8))
            leg.move(to: .init(x: 5.5, y: 15.8))
            leg.line(to: .init(x: 9.6, y: 15.8))
            // Tucked leg
            leg.move(to: .init(x: 9.0, y: 12.5))
            leg.line(to: .init(x: 10.4, y: 14.0))
            leg.line(to: .init(x: 8.8, y: 14.7))
            leg.lineWidth = 1.35
            leg.lineCapStyle = .round
            leg.lineJoinStyle = .round
            leg.stroke()

            // Bird silhouette
            let body = NSBezierPath()
            body.move(to: .init(x: 5.8, y: 5.2))
            body.curve(to: .init(x: 11.4, y: 2.3), controlPoint1: .init(x: 5.8, y: 2.8), controlPoint2: .init(x: 8.5, y: 1.8))
            body.curve(to: .init(x: 13.5, y: 4.6), controlPoint1: .init(x: 12.7, y: 2.6), controlPoint2: .init(x: 13.3, y: 3.5))
            body.line(to: .init(x: 16.5, y: 5.4))
            body.line(to: .init(x: 13.4, y: 6.8))
            body.curve(to: .init(x: 11.8, y: 11.8), controlPoint1: .init(x: 12.3, y: 8.3), controlPoint2: .init(x: 13.0, y: 10.3))
            body.curve(to: .init(x: 6.4, y: 13.1), controlPoint1: .init(x: 10.6, y: 13.1), controlPoint2: .init(x: 8.3, y: 13.4))
            body.line(to: .init(x: 2.8, y: 14.8))
            body.line(to: .init(x: 4.5, y: 11.8))
            body.curve(to: .init(x: 5.8, y: 5.2), controlPoint1: .init(x: 3.1, y: 9.8), controlPoint2: .init(x: 4.6, y: 7.2))
            body.close()
            body.fill()

            // Clear eye cutout
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.compositingOperation = .clear
            if pose == .allowtimeOpen {
                // Open alert eye while Allowtime window is open
                NSBezierPath(ovalIn: .init(x: 9.2, y: 4.1, width: 2.1, height: 2.1)).fill()
            } else {
                // Peaceful closed zen eye arc
                let eye = NSBezierPath()
                eye.move(to: .init(x: 8.8, y: 4.9))
                eye.curve(to: .init(x: 11.6, y: 4.8), controlPoint1: .init(x: 9.7, y: 6.1), controlPoint2: .init(x: 10.8, y: 6.1))
                eye.lineWidth = 1.25
                eye.lineCapStyle = .round
                eye.stroke()
            }
            NSGraphicsContext.restoreGraphicsState()

            NSColor.black.set()

            switch pose {
            case .idle:
                break

            case .locked:
                // Small padlock badge at lower-right
                let shackle = NSBezierPath()
                shackle.move(to: .init(x: 15.2, y: 11.1))
                shackle.line(to: .init(x: 15.2, y: 9.8))
                shackle.curve(to: .init(x: 18.6, y: 9.8), controlPoint1: .init(x: 15.2, y: 8.1), controlPoint2: .init(x: 18.6, y: 8.1))
                shackle.line(to: .init(x: 18.6, y: 11.1))
                shackle.lineWidth = 1.25
                shackle.lineCapStyle = .round
                shackle.stroke()
                NSBezierPath(roundedRect: .init(x: 14.0, y: 11.0, width: 5.8, height: 4.9), xRadius: 1.4, yRadius: 1.4).fill()

            case .guarding:
                // Calm zen ring dot indicating Allowtime guard is armed
                let ring = NSBezierPath(ovalIn: .init(x: 14.8, y: 10.6, width: 4.8, height: 4.8))
                ring.lineWidth = 1.4
                ring.stroke()

            case .allowtimeOpen:
                // Solid timer dot indicating Allowtime window is ticking
                NSBezierPath(ovalIn: .init(x: 15.1, y: 11.0, width: 4.4, height: 4.4)).fill()
            }

            return true
        }
        image.isTemplate = true
        switch pose {
        case .idle: image.accessibilityDescription = "Huerequeque Zen, en calma"
        case .locked: image.accessibilityDescription = "Huerequeque Zen, bloqueo irrompible activo"
        case .guarding: image.accessibilityDescription = "Huerequeque Zen, guardia Allowtime activa"
        case .allowtimeOpen: image.accessibilityDescription = "Huerequeque Zen, ventana Allowtime abierta"
        }
        return image
    }
}
