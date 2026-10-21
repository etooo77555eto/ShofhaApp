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

// MARK: - Models

struct Card: Identifiable, Hashable {
    let i: Int
    var t: String
    var l: String
    var p: String
    var y: Int?
    var g: [String]
    var r: Double?
    var k: String          // film | series | anime
    var e: Int?
    var sc: Int?
    var d: String?
    var dub: Bool
    var q: String

    var id: Int { i }
    var isSeriesLike: Bool { k == "series" || k == "anime" }
    var kindName: String {
        switch k {
        case "film": return "فيلم"
        case "anime": return "أنمي"
        default: return "مسلسل"
        }
    }
}

extension Card: Decodable {
    enum CodingKeys: String, CodingKey { case i, t, l, p, y, g, r, k, e, sc, d, dub, q }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        i = try c.decodeIfPresent(Int.self, forKey: .i) ?? 0
        t = try c.decodeIfPresent(String.self, forKey: .t) ?? ""
        l = try c.decodeIfPresent(String.self, forKey: .l) ?? ""
        p = try c.decodeIfPresent(String.self, forKey: .p) ?? ""
        y = try c.decodeIfPresent(Int.self, forKey: .y)
        g = try c.decodeIfPresent([String].self, forKey: .g) ?? []
        r = try c.decodeIfPresent(Double.self, forKey: .r)
        k = try c.decodeIfPresent(String.self, forKey: .k) ?? "film"
        e = try c.decodeIfPresent(Int.self, forKey: .e)
        sc = try c.decodeIfPresent(Int.self, forKey: .sc)
        d = try c.decodeIfPresent(String.self, forKey: .d)
        dub = try c.decodeIfPresent(Bool.self, forKey: .dub) ?? false
        q = try c.decodeIfPresent(String.self, forKey: .q) ?? ""
    }
}

struct Server: Decodable, Hashable {
    var label: String
    var url: String
}

struct Episode: Decodable, Identifiable {
    var n: Int
    var servers: [Server]
    var defaultURL: String?
    var date: String?
    var id: Int { n }
    enum CodingKeys: String, CodingKey { case n, servers, date; case defaultURL = "default" }
}

struct Detail {
    var story: String
    var servers: [Server]
    var defaultURL: String?
    var dur: Int?
    var country: String
    var seasons: [String: [Episode]]
}

// Duration arrives as a number on some titles and as a string on others.
private struct FlexInt: Decodable {
    var value: Int?
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let i = try? c.decode(Int.self) {
            value = i
        } else if let str = try? c.decode(String.self) {
            value = Int(str)
        } else {
            value = nil
        }
    }
}

extension Detail: Decodable {
    enum CodingKeys: String, CodingKey { case story, servers, dur, country, seasons; case defaultURL = "default" }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        story = try c.decodeIfPresent(String.self, forKey: .story) ?? ""
        servers = try c.decodeIfPresent([Server].self, forKey: .servers) ?? []
        defaultURL = try c.decodeIfPresent(String.self, forKey: .defaultURL)
        dur = try c.decodeIfPresent(FlexInt.self, forKey: .dur)?.value
        country = try c.decodeIfPresent(String.self, forKey: .country) ?? ""
        seasons = try c.decodeIfPresent([String: [Episode]].self, forKey: .seasons) ?? [:]
    }
}

struct CollectionInfo: Decodable, Identifiable {
    var id: String
    var name: String
    var brand: String?
    var sub: String?
    var bg: String?
    var fg: String?
    var count: Int?
    var posters: [String]?
    var colors: [Color] { hexColors(from: bg ?? "") }
    var titleColor: Color { fg.map { Color(hex: $0) } ?? .white }
}

struct HomeData: Decodable {
    var hero: [Card]
    var trend: [Card]
    var films: [Card]
    var series: [Card]
    var anime: [Card]
    var genres: [String]
    var cols: [CollectionInfo]
    var turk: [Card]
}

struct Manifest: Decodable {
    var indexParts: [String]
    var buckets: Int
    var total: Int
}


// Season numbers of a detail, ascending. (Kept out of the Detail type:
// the one-liner computed property version broke the compiler.)
func seasonNumbers(of det: Detail) -> [Int] {
    var nums: [Int] = []
    for key in det.seasons.keys {
        if let n = Int(key) { nums.append(n) }
    }
    return nums.sorted()
}

// MARK: - Shared views

struct PosterView: View {
    let url: String
    var body: some View {
        ZStack {
            Color.brandCard
            if let u = safeURL(url) {
                AsyncImage(url: u, transaction: Transaction(animation: .easeIn(duration: 0.2))) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    case .failure:
                        Image(systemName: "film").foregroundColor(.gray)
                    default:
                        Color.brandCard
                    }
                }
            }
        }
        .clipped()
    }
}

struct RatingBadge: View {
    let rating: Double
    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "star.fill").font(.system(size: 8)).foregroundColor(.yellow)
            Text(String(format: "%.1f", rating)).font(.system(size: 10, weight: .bold)).foregroundColor(.white)
        }
        .padding(.horizontal, 5).padding(.vertical, 2)
        .background(Color.black.opacity(0.65)).cornerRadius(6)
    }
}

struct CardCell: View {
    let card: Card
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ZStack(alignment: .topLeading) {
                PosterView(url: card.p)
                    .aspectRatio(2/3, contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .cornerRadius(10)
                if let r = card.r { RatingBadge(rating: r).padding(5) }
                if card.dub {
                    Text("مدبلج").font(.system(size: 9, weight: .bold)).foregroundColor(.white)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Color.brandPurple).cornerRadius(6)
                        .padding(5)
                        .frame(maxWidth: .infinity, alignment: .topTrailing)
                }
            }
            Text(card.t.isEmpty ? card.l : card.t)
                .font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
                .lineLimit(1)
            HStack(spacing: 4) {
                if let y = card.y { Text(String(y)) }
                if card.isSeriesLike, let e = card.e { Text("• \(e) حلقة") }
                if !card.q.isEmpty { Text("• \(card.q)") }
            }
            .font(.system(size: 10)).foregroundColor(.gray)
            .lineLimit(1)
        }
    }
}

struct CardRowView: View {
    let title: String
    let cards: [Card]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 17, weight: .bold)).foregroundColor(.white)
                .padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(cards) { card in
                        NavigationLink(destination: DetailView(card: card)) {
                            CardCell(card: card).frame(width: 108)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

struct GridView: View {
    let cards: [Card]
    @State private var shown = 90
    private let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    var body: some View {
        let page = Array(cards.prefix(shown))
        LazyVGrid(columns: cols, spacing: 16) {
            ForEach(page.indices, id: \.self) { idx in
                NavigationLink(destination: DetailView(card: page[idx])) {
                    CardCell(card: page[idx])
                }
                .buttonStyle(.plain)
                .onAppear {
                    if idx >= shown - 12 && shown < cards.count { shown += 90 }
                }
            }
        }
        .padding(.horizontal, 16)
        .onChange(of: cards.count) { _ in shown = 90 }
    }
}

struct SplashView: View {
    var body: some View {
        ZStack {
            Color.brandBg.ignoresSafeArea()
            VStack(spacing: 16) {
                Text("شوفها")
                    .font(.system(size: 44, weight: .black))
                    .foregroundStyle(Color.brandGradient)
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.3)
            }
        }
    }
}

// MARK: - Root (bisect stub)

struct ContentView: View {
    var body: some View {
        Text("Shofha bisect")
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.brandBg)
    }
}

// MARK: - Detail (bisect stub)

struct DetailView: View {
    let card: Card
    var body: some View {
        Text(card.t)
    }
}
