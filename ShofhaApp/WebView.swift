import SwiftUI
import WebKit

// MARK: - Theme

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        if s.count == 6 {
            self.init(red: Double((v >> 16) & 0xFF) / 255,
                      green: Double((v >> 8) & 0xFF) / 255,
                      blue: Double(v & 0xFF) / 255)
        } else {
            self.init(red: 0.043, green: 0.043, blue: 0.078)
        }
    }

    static let brandBg = Color(red: 0.043, green: 0.043, blue: 0.078)
    static let brandCard = Color(red: 0.09, green: 0.09, blue: 0.14)
    static let brandPurple = Color(red: 0.486, green: 0.361, blue: 1.0)
    static let brandCyan = Color(red: 0.0, green: 0.761, blue: 1.0)
    static var brandGradient: LinearGradient {
        LinearGradient(colors: [brandPurple, brandCyan],
                       startPoint: .leading, endPoint: .trailing)
    }
}

// Pulls every #rrggbb colour out of a CSS string such as
// "linear-gradient(150deg,#f7c948,#d99a06)".
func hexColors(from css: String) -> [Color] {
    var out: [Color] = []
    var cur = ""
    var inHex = false
    for ch in css {
        if ch == "#" { inHex = true; cur = ""; continue }
        if inHex {
            if ch.isHexDigit && cur.count < 6 {
                cur.append(ch)
                if cur.count == 6 { out.append(Color(hex: cur)); inHex = false }
            } else { inHex = false }
        }
    }
    return out
}

// Poster URLs sometimes contain Arabic characters or spaces — encode them
// without touching structural characters or existing % escapes.
func safeURL(_ s: String) -> URL? {
    if let u = URL(string: s), s.allSatisfy({ $0.isASCII }) { return u }
    let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~:/?#[]@!$&'()*+,;=%")
    if let enc = s.addingPercentEncoding(withAllowedCharacters: allowed), let u = URL(string: enc) {
        return u
    }
    return URL(string: s)
}

func cleanURL(_ s: String) -> String {
    s.replacingOccurrences(of: "&amp;", with: "&")
}

// Same folding the site search uses: Arabic letter variants and Turkish
// characters collapse so "اسطورة" finds "أسطورة".
func normText(_ s: String) -> String {
    var t = s.lowercased()
    let map: [(String, String)] = [
        ("إ", "ا"), ("أ", "ا"), ("آ", "ا"), ("ٱ", "ا"),
        ("ة", "ه"), ("ى", "ي"), ("ؤ", "و"), ("ئ", "ي"),
        ("ş", "s"), ("ğ", "g"), ("ü", "u"), ("ö", "o"),
        ("ç", "c"), ("ı", "i"), ("î", "i"), ("â", "a"), ("û", "u")
    ]
    for (a, b) in map { t = t.replacingOccurrences(of: a, with: b) }
    return t
}


struct ContentView: View {
    var body: some View {
        Text("Shofha bisect")
            .foregroundColor(.white)
            .background(Color.brandBg)
    }
}
