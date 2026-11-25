// Familia Llama Encargada. GENERADO por scripts/build.mjs desde tokens/llama.tokens.json: no editar a mano.
// Copiar a Sources/<App>/ y usar LlamaTheme.accent, LlamaTheme.titulo, .llamaSurface().
import AppKit
import SwiftUI

enum LlamaTheme {
    static let bg = adaptive(0xf2f2f7, 0x000000) // Lienzo de la ventana.
    static let surface = adaptive(0xffffff, 0x1c1c1e) // Tarjetas y listas agrupadas.
    static let sunk = adaptive(0xe5e5ea, 0x2c2c2e) // Carril de barras de progreso.
    static let fill = adaptive(0x767680, 0x767680, 0.12, 0.24) // Relleno de botones secundarios, campos, kbd.
    static let ink = adaptive(0x000000, 0xffffff) // Texto principal.
    static let ink2 = adaptive(0x3c3c43, 0xebebf5) // Texto secundario fuerte, iconos del menú.
    static let muted = adaptive(0x3c3c43, 0xebebf5, 0.66, 0.64) // Texto de apoyo, metadatos.
    static let line = adaptive(0x3c3c43, 0x545458, 0.29, 0.6) // Separadores de medio píxel.
    static let track = adaptive(0x3c3c43, 0xebebf5, 0.2, 0.22) // Carril del anillo de carga.
    static let side = adaptive(0xf2f2f7, 0x1c1c1e, 0.78, 0.75) // Barra lateral translúcida, con blur de 20px y saturación 180%.
    static let accent = adaptive(0x5856d6, 0x5e5ce6) // Índigo. Significa: actúa aquí, y el estado Ahora. Solo rellenos y bordes.
    static let accentOn = adaptive(0xffffff, 0xffffff) // Texto sobre relleno índigo.
    static let accentInk = adaptive(0x3634a3, 0x8f8dff) // Índigo legible para texto y enlaces (4,5:1 o más).
    static let accentSoft = adaptive(0x5856d6, 0x5e5ce6, 0.13, 0.26) // Selección, vista activa, anillo de foco.
    static let warn = adaptive(0xff9500, 0xff9f0a) // Naranja. Significa: pide tu atención.
    static let warnInk = adaptive(0xc93400, 0xffb340)
    static let warnSoft = adaptive(0xff9500, 0xff9f0a, 0.16, 0.2)
    static let purple = adaptive(0xaf52de, 0xbf5af2) // Púrpura. Significa: depende de otra persona.
    static let purpleInk = adaptive(0x8944ab, 0xda8fff)
    static let purpleSoft = adaptive(0xaf52de, 0xbf5af2, 0.14, 0.2)
    static let bad = adaptive(0xff3b30, 0xff453a) // Rojo. Significa: roto o sin vuelta.
    static let badInk = adaptive(0xd70015, 0xff6961)
    static let badSoft = adaptive(0xff3b30, 0xff453a, 0.13, 0.2)
    static let ok = adaptive(0x34c759, 0x30d158) // Verde. Significa: hecho.
    static let okInk = adaptive(0x248a3d, 0x30db5b)
    static let okSoft = adaptive(0x34c759, 0x30d158, 0.16, 0.2)
    static let gray = adaptive(0x8e8e93, 0x98989d) // Gris. Significa: en reposo.
    static let grayInk = adaptive(0x636366, 0xaeaeb2)
    static let graySoft = adaptive(0x8e8e93, 0x98989d, 0.16, 0.22)
    static let marcaTileTop = adaptive(0x6e6bf0, 0x6e6bf0) // Azulejo del icono, arriba. Degradado vertical.
    static let marcaTileBottom = adaptive(0x4441bd, 0x4441bd) // Azulejo del icono, abajo.
    static let marcaCrema = adaptive(0xfff8ea, 0xfff8ea) // Silueta del animal.
    static let marcaAmbar = adaptive(0xffbd45, 0xffbd45) // El único acento del icono: el gesto del oficio.
    static let marcaPapel = adaptive(0x5855d6, 0x5855d6) // Índigo de los huecos dentro de la silueta (ojo, boca).

    static let titulo = Font.system(size: 34, weight: .bold, design: .rounded)
    static let seccion = Font.system(size: 17, weight: .bold, design: .rounded)
    static func cifra(_ size: CGFloat = 26) -> Font { .system(size: size, weight: .bold, design: .rounded).monospacedDigit() }
    static let cuerpo = Font.system(size: 15)
    static let meta = Font.system(size: 13)

    static let radioControl: CGFloat = 9
    static let radioLista: CGFloat = 12
    static let radioTarjeta: CGFloat = 14

    private static func adaptive(_ light: Int, _ dark: Int, _ alpha: CGFloat = 1, _ darkAlpha: CGFloat = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let rgb = isDark ? dark : light
            return NSColor(srgbRed: CGFloat((rgb >> 16) & 255) / 255, green: CGFloat((rgb >> 8) & 255) / 255,
                           blue: CGFloat(rgb & 255) / 255, alpha: isDark ? darkAlpha : alpha)
        })
    }
}

extension View {
    /// Superficie agrupada: radio 12 continuo y borde de medio punto.
    func llamaSurface() -> some View {
        let shape = RoundedRectangle(cornerRadius: LlamaTheme.radioLista, style: .continuous)
        return background(LlamaTheme.surface, in: shape)
            .overlay(shape.strokeBorder(LlamaTheme.line.opacity(0.45), lineWidth: 0.5).allowsHitTesting(false))
    }
}
