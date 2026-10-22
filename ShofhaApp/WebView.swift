import SwiftUI
import WebKit
import ImageIO

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

    static let brandBg = Color(red: 0.039, green: 0.039, blue: 0.075)
    static let brandBg2 = Color(red: 0.07, green: 0.06, blue: 0.13)
    static let brandCard = Color(red: 0.085, green: 0.085, blue: 0.135)
    static let brandPurple = Color(red: 0.545, green: 0.361, blue: 0.965)
    static let brandViolet = Color(red: 0.486, green: 0.227, blue: 0.929)
    static let brandCyan = Color(red: 0.133, green: 0.827, blue: 0.933)
    static let brandGold = Color(red: 0.98, green: 0.75, blue: 0.14)
    static var brandGradient: LinearGradient {
        LinearGradient(colors: [brandPurple, brandCyan],
                       startPoint: .leading, endPoint: .trailing)
    }
    static var brandGradientV: LinearGradient {
        LinearGradient(colors: [brandViolet, brandPurple, brandCyan],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
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

// MARK: - Data store

@MainActor
final class AppStore: ObservableObject {
    static let base = "https://shofha.vercel.app"

    @Published var home: HomeData?
    @Published var loadError: String?
    @Published var allCards: [Card] = []        // full catalogue, for search/browse
    @Published var indexReady = false
    @Published var turkCards: [Card] = []

    private var manifest: Manifest?
    private var detailCache: [Int: Detail] = [:]
    private var bucketCache: [Int: [String: Detail]] = [:]
    private var indexTask: Task<Void, Never>?

    func loadHome() async {
        if home != nil { return }
        do {
            async let m = fetchJSON(Manifest.self, "\(Self.base)/catalog.json")
            async let h = fetchJSON(HomeData.self, "\(Self.base)/home.json")
            manifest = try await m
            home = try await h
            loadError = nil
            startIndexLoad()
            Task { await loadTurk() }
        } catch {
            loadError = "تأكد من الإنترنت وحاول مرة ثانية"
        }
    }

    private func loadTurk() async {
        if let cards = try? await fetchJSON([Card].self, "\(Self.base)/turk.json") {
            turkCards = cards
        }
    }

    private func startIndexLoad() {
        guard indexTask == nil, let parts = manifest?.indexParts else { return }
        indexTask = Task { [weak self] in
            guard let self = self else { return }
            var collected: [Card] = []
            collected.reserveCapacity(28000)
            // Fetch the shards a few at a time; the grid/search fill in
            // progressively instead of waiting for the whole catalogue.
            let groupSize = 6
            var idx = 0
            while idx < parts.count {
                let slice = Array(parts[idx..<min(idx + groupSize, parts.count)])
                var batch: [Card] = []
                for name in slice {
                    if let cards = try? await self.fetchJSON([Card].self, "\(Self.base)/\(name)") {
                        batch.append(contentsOf: cards)
                    }
                }
                collected.append(contentsOf: batch)
                let snapshot = collected
                await MainActor.run { self.allCards = snapshot }
                idx += groupSize
            }
            await MainActor.run { self.indexReady = true }
        }
    }

    func cards(ofKind kind: String) -> [Card] {
        var src = homeCards(ofKind: kind)
        if indexReady || !allCards.isEmpty { src = allCards }
        return src.filter { $0.k == kind }.sorted { ($0.d ?? "") > ($1.d ?? "") }
    }

    func cards(ofGenre genre: String) -> [Card] {
        allCards.filter { $0.g.contains(genre) }.sorted { ($0.d ?? "") > ($1.d ?? "") }
    }

    private func homeCards(ofKind kind: String) -> [Card] {
        guard let h = home else { return [] }
        switch kind {
        case "film": return h.films
        case "anime": return h.anime
        default: return h.series
        }
    }

    func search(_ query: String) -> [Card] {
        let q = normText(query).trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { return [] }
        let words = q.split(separator: " ").map(String.init)
        var pool = allCards
        if pool.isEmpty, let h = home {
            pool = h.hero
            pool.append(contentsOf: h.trend)
            pool.append(contentsOf: h.films)
            pool.append(contentsOf: h.series)
            pool.append(contentsOf: h.anime)
            pool.append(contentsOf: h.turk)
        }
        var seen = Set<Int>()
        var out: [Card] = []
        for card in pool {
            if seen.contains(card.i) { continue }
            let hay = normText(card.t) + " " + normText(card.l)
            if words.allSatisfy({ hay.contains($0) }) {
                seen.insert(card.i)
                out.append(card)
            }
        }
        return Array(out.prefix(120))
    }

    func detail(for card: Card) async -> Detail? {
        if let cached = detailCache[card.i] { return cached }
        let bucket = card.i / 400
        if bucketCache[bucket] == nil {
            if let map = try? await fetchJSON([String: Detail].self, "\(Self.base)/details-\(bucket).json") {
                bucketCache[bucket] = map
            }
        }
        let det = bucketCache[bucket]?[String(card.i)]
        if let det = det { detailCache[card.i] = det }
        return det
    }

    func collectionCards(_ id: String) async -> [Card] {
        (try? await fetchJSON([Card].self, "\(Self.base)/collection-\(id).json")) ?? []
    }

    private func fetchJSON<T: Decodable>(_ type: T.Type, _ urlString: String) async throws -> T {
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        let (data, _) = try await URLSession.shared.data(for: URLRequest(url: url))
        return try JSONDecoder().decode(T.self, from: data)
    }
}

// MARK: - Image pipeline
//
// The source hosts refuse or stall plain URLSession image loads (that's why
// posters stayed blank), so posters are fetched with a real browser
// identity, a same-host referer, one retry, an in-memory cache on top of the
// app-wide 300 MB URLCache, and downsampling to keep scrolling smooth.

enum ImageLoader {
    static let memory = NSCache<NSString, UIImage>()

    private static var session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.urlCache = URLCache.shared
        cfg.timeoutIntervalForRequest = 45
        cfg.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            "Accept": "image/avif,image/webp,image/*,*/*;q=0.8"
        ]
        return URLSession(configuration: cfg)
    }()

    static func load(_ urlString: String) async -> UIImage? {
        guard let url = safeURL(urlString) else { return nil }
        let key = url.absoluteString as NSString
        if let hit = memory.object(forKey: key) { return hit }
        for attempt in 0..<3 {
            if attempt == 1 {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
            } else if attempt == 2 {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
            }
            var req = URLRequest(url: url)
            if let host = url.host {
                req.setValue("https://\(host)/", forHTTPHeaderField: "Referer")
            }
            do {
                let (data, resp) = try await session.data(for: req)
                if let http = resp as? HTTPURLResponse, http.statusCode != 200 { continue }
                if let img = downsampled(data) {
                    memory.setObject(img, forKey: key)
                    return img
                }
            } catch {
                continue
            }
        }
        return nil
    }

    static func cached(_ urlString: String) -> UIImage? {
        guard let url = safeURL(urlString) else { return nil }
        return memory.object(forKey: url.absoluteString as NSString)
    }

    private static func downsampled(_ data: Data) -> UIImage? {
        let opts: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let src = CGImageSourceCreateWithData(data as CFData, opts as CFDictionary) else {
            return UIImage(data: data)
        }
        let thumbOpts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 540
        ]
        if let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, thumbOpts as CFDictionary) {
            return UIImage(cgImage: cg)
        }
        return UIImage(data: data)
    }
}

struct PosterImage: View {
    let url: String
    @State private var image: UIImage?
    @State private var failed = false
    @State private var loading = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.brandCard, Color.brandBg2],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            } else if failed {
                Image(systemName: "film")
                    .font(.system(size: 20))
                    .foregroundColor(.white.opacity(0.25))
            } else {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white.opacity(0.6)))
                    .scaleEffect(0.8)
            }
        }
        .clipped()
        .task(id: url) { await load() }
        .onAppear { Task { await load() } }
    }

    private func load() async {
        if image != nil || loading { return }
        if let hit = ImageLoader.cached(url) {
            image = hit
            return
        }
        loading = true
        failed = false
        let img = await ImageLoader.load(url)
        loading = false
        if let img = img {
            withAnimation(.easeIn(duration: 0.25)) { image = img }
        } else {
            failed = true
        }
    }
}

// MARK: - Shared views

struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct RatingBadge: View {
    let rating: Double
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "star.fill").font(.system(size: 9)).foregroundColor(Color.brandGold)
            Text(String(format: "%.1f", rating)).font(.system(size: 10.5, weight: .heavy)).foregroundColor(.white)
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(Color.black.opacity(0.55))
        .background(.ultraThinMaterial)
        .cornerRadius(7)
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.14), lineWidth: 0.5))
    }
}

struct DubBadge: View {
    var body: some View {
        Text("مدبلج")
            .font(.system(size: 9, weight: .heavy)).foregroundColor(.white)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(Color.brandGradient)
            .cornerRadius(7)
            .shadow(color: Color.brandPurple.opacity(0.45), radius: 5, y: 2)
    }
}

struct CardCell: View {
    let card: Card
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                PosterImage(url: card.p)
                    .aspectRatio(2/3, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .cornerRadius(13)
                    .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.white.opacity(0.09), lineWidth: 1))
                    .shadow(color: .black.opacity(0.35), radius: 7, y: 4)
                if let r = card.r { RatingBadge(rating: r).padding(6) }
                if card.dub {
                    DubBadge()
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .topTrailing)
                }
                if !card.q.isEmpty {
                    Text(card.q)
                        .font(.system(size: 9, weight: .bold)).foregroundColor(.white)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Color.black.opacity(0.55)).cornerRadius(6)
                        .padding(6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }
            }
            Text(card.t.isEmpty ? card.l : card.t)
                .font(.system(size: 12.5, weight: .semibold)).foregroundColor(.white)
                .lineLimit(1)
            HStack(spacing: 4) {
                if let y = card.y { Text(String(y)) }
                if card.isSeriesLike, let e = card.e { Text("• \(e) حلقة") }
                Text("• \(card.kindName)")
            }
            .font(.system(size: 10)).foregroundColor(.gray)
            .lineLimit(1)
        }
    }
}

struct SectionHeader: View {
    let title: String
    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.brandGradient)
                .frame(width: 4, height: 19)
            Text(title)
                .font(.system(size: 17.5, weight: .black)).foregroundColor(.white)
            Spacer()
        }
        .padding(.horizontal, 16)
    }
}

struct CardRowView: View {
    let title: String
    let cards: [Card]
    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            SectionHeader(title: title)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(cards) { card in
                        NavigationLink(destination: DetailView(card: card)) {
                            CardCell(card: card).frame(width: 110)
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
        LazyVGrid(columns: cols, spacing: 17) {
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
            RadialGradient(colors: [Color.brandPurple.opacity(0.35), .clear],
                           center: .top, startRadius: 40, endRadius: 420)
                .ignoresSafeArea()
            VStack(spacing: 18) {
                Text("شوفها")
                    .font(.system(size: 52, weight: .black))
                    .foregroundStyle(Color.brandGradient)
                    .shadow(color: Color.brandPurple.opacity(0.5), radius: 24, y: 6)
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.3)
            }
        }
    }
}

struct AmbienceBackground: View {
    var body: some View {
        ZStack {
            Color.brandBg
            RadialGradient(colors: [Color.brandViolet.opacity(0.22), .clear],
                           center: .topTrailing, startRadius: 30, endRadius: 460)
            RadialGradient(colors: [Color.brandCyan.opacity(0.08), .clear],
                           center: .topLeading, startRadius: 30, endRadius: 380)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Root

struct ContentView: View {
    @StateObject private var store = AppStore()

    var body: some View {
        Group {
            if let err = store.loadError, store.home == nil {
                ZStack {
                    AmbienceBackground()
                    VStack(spacing: 14) {
                        Text("📡").font(.system(size: 44))
                        Text("ماكو اتصال").font(.headline).foregroundColor(.white)
                        Text(err).font(.footnote).foregroundColor(.gray)
                        Button("حاول مرة ثانية") {
                            store.loadError = nil
                            Task { await store.loadHome() }
                        }
                        .buttonStyle(PressScaleStyle())
                        .padding(.horizontal, 26).padding(.vertical, 12)
                        .background(Color.brandGradient).foregroundColor(.white).cornerRadius(14)
                        .shadow(color: Color.brandPurple.opacity(0.45), radius: 12, y: 5)
                    }
                }
            } else if store.home == nil {
                SplashView()
            } else {
                TabView {
                    NavigationView { HomeView() }
                        .navigationViewStyle(.stack)
                        .tabItem { Label("الرئيسية", systemImage: "house.fill") }
                    NavigationView { BrowseView(kind: "film", title: "الأفلام") }
                        .navigationViewStyle(.stack)
                        .tabItem { Label("الأفلام", systemImage: "film.fill") }
                    NavigationView { BrowseView(kind: "series", title: "المسلسلات") }
                        .navigationViewStyle(.stack)
                        .tabItem { Label("المسلسلات", systemImage: "tv.fill") }
                    NavigationView { BrowseView(kind: "anime", title: "الأنمي") }
                        .navigationViewStyle(.stack)
                        .tabItem { Label("الأنمي", systemImage: "sparkles") }
                    NavigationView { SearchView() }
                        .navigationViewStyle(.stack)
                        .tabItem { Label("بحث", systemImage: "magnifyingglass") }
                }
                .accentColor(Color.brandCyan)
            }
        }
        .environmentObject(store)
        .environment(\.layoutDirection, .rightToLeft)
        .preferredColorScheme(.dark)
        .task { await store.loadHome() }
    }
}

// MARK: - Home

struct HomeView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        ScrollView {
            if let home = store.home {
                VStack(alignment: .leading, spacing: 30) {
                    HeroPager(cards: home.hero)
                    CardRowView(title: "🔥 ترند شوفها اليوم", cards: home.trend)

                    if !home.cols.isEmpty {
                        VStack(alignment: .leading, spacing: 11) {
                            SectionHeader(title: "مجموعات مختارة")
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(home.cols) { col in
                                        NavigationLink(destination: CollectionView(info: col)) {
                                            CollectionCard(info: col)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }
                    }

                    if !home.genres.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(home.genres, id: \.self) { genre in
                                    NavigationLink(destination: GenreView(genre: genre)) {
                                        Text(genre)
                                            .font(.system(size: 13, weight: .bold)).foregroundColor(.white)
                                            .padding(.horizontal, 15).padding(.vertical, 9)
                                            .background(Color.white.opacity(0.06))
                                            .cornerRadius(17)
                                            .overlay(RoundedRectangle(cornerRadius: 17).stroke(Color.white.opacity(0.1), lineWidth: 1))
                                    }
                                    .buttonStyle(PressScaleStyle())
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }

                    CardRowView(title: "🎬 أحدث الأفلام", cards: home.films)
                    CardRowView(title: "📺 أحدث المسلسلات", cards: home.series)
                    CardRowView(title: "🌸 أحدث الأنمي", cards: home.anime)

                    if !home.turk.isEmpty {
                        VStack(alignment: .leading, spacing: 11) {
                            HStack {
                                SectionHeader(title: "🇹🇷 مسلسلات تركية")
                                NavigationLink(destination: TurkView()) {
                                    HStack(spacing: 3) {
                                        Text("الكل").font(.system(size: 13, weight: .bold))
                                        Image(systemName: "chevron.left").font(.system(size: 10, weight: .bold))
                                    }
                                    .foregroundColor(Color.brandCyan)
                                }
                                .padding(.leading, 16)
                            }
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(alignment: .top, spacing: 12) {
                                    ForEach(home.turk) { card in
                                        NavigationLink(destination: DetailView(card: card)) {
                                            CardCell(card: card).frame(width: 110)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }
                    }

                    Link(destination: URL(string: "https://t.me/shofha10")!) {
                        HStack(spacing: 9) {
                            Image(systemName: "paperplane.fill")
                            Text("تابعنا على تيليجرام").font(.system(size: 14.5, weight: .black))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.brandGradientV).cornerRadius(15)
                        .shadow(color: Color.brandPurple.opacity(0.4), radius: 12, y: 5)
                    }
                    .buttonStyle(PressScaleStyle())
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
                .padding(.top, 2)
            }
        }
        .background(AmbienceBackground())
        .navigationTitle("شوفها")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct HeroPager: View {
    let cards: [Card]
    @State private var page = 0

    var body: some View {
        let top = Array(cards.prefix(8))
        ZStack(alignment: .bottom) {
            TabView(selection: $page) {
                ForEach(top.indices, id: \.self) { idx in
                    NavigationLink(destination: DetailView(card: top[idx])) {
                        HeroSlide(card: top[idx])
                    }
                    .buttonStyle(.plain)
                    .tag(idx)
                }
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            .frame(height: 470)

            HStack(spacing: 5) {
                ForEach(top.indices, id: \.self) { idx in
                    Capsule()
                        .fill(idx == page ? Color.white : Color.white.opacity(0.3))
                        .frame(width: idx == page ? 20 : 6, height: 6)
                        .animation(.easeInOut(duration: 0.25), value: page)
                }
            }
            .padding(.bottom, 10)
        }
        .onReceive(Timer.publish(every: 5.5, on: .main, in: .common).autoconnect()) { _ in
            guard !top.isEmpty else { return }
            withAnimation(.easeInOut(duration: 0.55)) {
                page = (page + 1) % top.count
            }
        }
    }
}

struct HeroSlide: View {
    let card: Card
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            PosterImage(url: card.p)
            LinearGradient(colors: [.clear, Color.brandBg.opacity(0.55), Color.brandBg],
                           startPoint: .top, endPoint: .bottom)
            LinearGradient(colors: [Color.brandBg.opacity(0.35), .clear],
                           startPoint: .bottom, endPoint: .top)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    if let r = card.r { RatingBadge(rating: r) }
                    if let y = card.y {
                        Text(String(y))
                            .font(.system(size: 10.5, weight: .bold)).foregroundColor(.white)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Color.black.opacity(0.5)).cornerRadius(7)
                    }
                    Text(card.kindName)
                        .font(.system(size: 10.5, weight: .bold)).foregroundColor(.white)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Color.brandPurple.opacity(0.75)).cornerRadius(7)
                }
                Text(card.t.isEmpty ? card.l : card.t)
                    .font(.system(size: 25, weight: .black)).foregroundColor(.white)
                    .lineLimit(2).multilineTextAlignment(.leading)
                    .shadow(color: .black.opacity(0.6), radius: 10, y: 3)
                if !card.g.isEmpty {
                    Text(card.g.prefix(3).joined(separator: " • "))
                        .font(.system(size: 12)).foregroundColor(.white.opacity(0.85))
                        .lineLimit(1)
                }
                HStack(spacing: 7) {
                    ZStack {
                        Circle().fill(Color.white)
                        Image(systemName: "play.fill")
                            .font(.system(size: 11, weight: .black))
                            .foregroundColor(Color.brandViolet)
                    }
                    .frame(width: 27, height: 27)
                    Text("شاهد الآن").font(.system(size: 14.5, weight: .black))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 18).padding(.vertical, 10)
                .background(Color.brandGradient).cornerRadius(24)
                .shadow(color: Color.brandPurple.opacity(0.55), radius: 13, y: 5)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 30)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct CollectionCard: View {
    let info: CollectionInfo
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if info.colors.count >= 2 {
                LinearGradient(colors: info.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            } else if let first = info.colors.first {
                first
            } else {
                Color.brandCard
            }
            if let posters = info.posters, posters.count >= 3 {
                HStack(spacing: 4) {
                    ForEach(posters.prefix(3), id: \.self) { p in
                        PosterImage(url: p).frame(width: 52, height: 76).cornerRadius(7)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(info.brand ?? info.name)
                    .font(.system(size: 15.5, weight: .black)).foregroundColor(info.titleColor)
                    .lineLimit(1)
                    .shadow(color: .black.opacity(0.35), radius: 5, y: 2)
                if let count = info.count {
                    Text("\(count) عنوان").font(.system(size: 11, weight: .semibold)).foregroundColor(info.titleColor.opacity(0.85))
                }
            }
            .padding(11)
        }
        .frame(width: 192, height: 152)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.13), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 9, y: 5)
    }
}

struct CollectionView: View {
    let info: CollectionInfo
    @EnvironmentObject var store: AppStore
    @State private var cards: [Card] = []
    var body: some View {
        ScrollView {
            if cards.isEmpty {
                ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white)).padding(.top, 60)
            } else {
                GridView(cards: cards)
            }
        }
        .background(AmbienceBackground())
        .navigationTitle(info.name)
        .task { cards = await store.collectionCards(info.id) }
    }
}

struct TurkView: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        ScrollView {
            GridView(cards: store.turkCards.isEmpty ? (store.home?.turk ?? []) : store.turkCards)
        }
        .background(AmbienceBackground())
        .navigationTitle("مسلسلات تركية")
    }
}

struct GenreView: View {
    let genre: String
    @EnvironmentObject var store: AppStore
    var body: some View {
        ScrollView {
            if store.indexReady {
                GridView(cards: store.cards(ofGenre: genre))
            } else {
                VStack(spacing: 12) {
                    ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white))
                    Text("جاري تحميل الكتالوج...").font(.footnote).foregroundColor(.gray)
                }
                .padding(.top, 60)
            }
        }
        .background(AmbienceBackground())
        .navigationTitle(genre)
    }
}

// MARK: - Browse & Search

struct BrowseView: View {
    let kind: String
    let title: String
    @EnvironmentObject var store: AppStore
    @State private var genre: String? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                if let home = store.home, !home.genres.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            chip("الكل", active: genre == nil) { genre = nil }
                            ForEach(home.genres, id: \.self) { g in
                                chip(g, active: genre == g) { genre = g }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                GridView(cards: filtered)
            }
            .padding(.top, 10)
        }
        .background(AmbienceBackground())
        .navigationTitle(title)
    }

    private var filtered: [Card] {
        let base = store.cards(ofKind: kind)
        guard let g = genre else { return base }
        return base.filter { $0.g.contains(g) }
    }

    private func chip(_ text: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 15).padding(.vertical, 9)
                .background(active ? AnyShapeStyle(Color.brandGradient) : AnyShapeStyle(Color.white.opacity(0.06)))
                .cornerRadius(17)
                .overlay(RoundedRectangle(cornerRadius: 17).stroke(Color.white.opacity(active ? 0 : 0.1), lineWidth: 1))
                .shadow(color: active ? Color.brandPurple.opacity(0.4) : .clear, radius: 8, y: 3)
        }
        .buttonStyle(PressScaleStyle())
    }
}

struct SearchView: View {
    @EnvironmentObject var store: AppStore
    @State private var query = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass").foregroundColor(Color.brandCyan)
                    TextField("ابحث عن فيلم أو مسلسل...", text: $query)
                        .foregroundColor(.white)
                        .submitLabel(.search)
                    if !query.isEmpty {
                        Button(action: { query = "" }) {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.gray)
                        }
                    }
                }
                .padding(13)
                .background(Color.white.opacity(0.06)).cornerRadius(14)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.1), lineWidth: 1))
                .padding(.horizontal, 16)

                if query.trimmingCharacters(in: .whitespaces).count < 2 {
                    VStack(spacing: 10) {
                        Text("🔍").font(.system(size: 34))
                        Text("ابحث بالعربي أو بالإنجليزي")
                            .font(.system(size: 14.5, weight: .semibold)).foregroundColor(.white.opacity(0.85))
                        if !store.indexReady {
                            Text("جاري تحميل الكتالوج كامل للبحث...")
                                .font(.footnote).foregroundColor(.gray)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 46)
                } else {
                    let results = store.search(query)
                    if results.isEmpty {
                        Text("لا توجد نتائج لـ «\(query)»")
                            .font(.system(size: 14)).foregroundColor(.gray)
                            .frame(maxWidth: .infinity).padding(.top, 40)
                    } else {
                        GridView(cards: results)
                    }
                }
            }
            .padding(.top, 10)
        }
        .background(AmbienceBackground())
        .navigationTitle("بحث")
    }
}

// MARK: - Detail

struct DetailView: View {
    let card: Card
    @EnvironmentObject var store: AppStore
    @State private var detail: Detail?
    @State private var season: Int = 0
    @State private var episode: Episode? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if let det = detail {
                    if !det.story.isEmpty {
                        VStack(alignment: .leading, spacing: 7) {
                            SectionHeader(title: "القصة")
                            Text(det.story).font(.system(size: 14)).foregroundColor(.white.opacity(0.75))
                                .lineSpacing(5).frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                        }
                    }
                    watchSection(det)
                } else {
                    ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .frame(maxWidth: .infinity).padding(.top, 30)
                }
            }
            .padding(.bottom, 26)
        }
        .background(AmbienceBackground())
        .navigationBarTitleDisplayMode(.inline)
        .task {
            detail = await store.detail(for: card)
            if let det = detail, let first = seasonNumbers(of: det).first { season = first }
        }
    }

    private var header: some View {
        ZStack(alignment: .bottomLeading) {
            PosterImage(url: card.p)
                .frame(height: 350)
                .blur(radius: 26)
                .opacity(0.5)
            LinearGradient(colors: [.clear, Color.brandBg], startPoint: .top, endPoint: .bottom)
            HStack(alignment: .bottom, spacing: 15) {
                PosterImage(url: card.p)
                    .frame(width: 112, height: 168)
                    .cornerRadius(13)
                    .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.white.opacity(0.16), lineWidth: 1))
                    .shadow(color: .black.opacity(0.55), radius: 16, y: 8)
                VStack(alignment: .leading, spacing: 7) {
                    Text(card.t.isEmpty ? card.l : card.t)
                        .font(.system(size: 21, weight: .black)).foregroundColor(.white)
                        .lineLimit(3)
                        .shadow(color: .black.opacity(0.6), radius: 8, y: 2)
                    if !card.l.isEmpty && card.l != card.t {
                        Text(card.l).font(.system(size: 12)).foregroundColor(.white.opacity(0.65)).lineLimit(1)
                    }
                    HStack(spacing: 6) {
                        metaChip(card.kindName)
                        if let y = card.y { metaChip(String(y)) }
                        if let r = card.r { metaChip("⭐ \(String(format: "%.1f", r))") }
                        if card.dub { metaChip("مدبلج") }
                        if !card.q.isEmpty { metaChip(card.q) }
                    }
                    if card.isSeriesLike {
                        HStack(spacing: 6) {
                            if let sc = card.sc { metaChip("\(sc) موسم") }
                            if let e = card.e { metaChip("\(e) حلقة") }
                        }
                    }
                    if let det = detail {
                        HStack(spacing: 6) {
                            if !det.country.isEmpty { metaChip(det.country) }
                            if let dur = det.dur { metaChip("\(dur) دقيقة") }
                        }
                    }
                    if !card.g.isEmpty {
                        Text(card.g.joined(separator: " • "))
                            .font(.system(size: 11.5, weight: .semibold)).foregroundColor(Color.brandCyan).lineLimit(2)
                    }
                }
            }
            .padding(16)
        }
        .frame(height: 350)
    }

    private func metaChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold)).foregroundColor(.white)
            .padding(.horizontal, 9).padding(.vertical, 4.5)
            .background(Color.black.opacity(0.45))
            .background(.ultraThinMaterial)
            .cornerRadius(9)
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.white.opacity(0.13), lineWidth: 0.5))
    }

    @ViewBuilder
    private func watchSection(_ det: Detail) -> some View {
        if !seasonNumbers(of: det).isEmpty {
            VStack(alignment: .leading, spacing: 15) {
                SectionHeader(title: "الحلقات")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(seasonNumbers(of: det), id: \.self) { s in
                            Button(action: { season = s; episode = nil }) {
                                Text("الموسم \(s)")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 17).padding(.vertical, 10)
                                    .background(season == s ? AnyShapeStyle(Color.brandGradient) : AnyShapeStyle(Color.white.opacity(0.06)))
                                    .cornerRadius(19)
                                    .overlay(RoundedRectangle(cornerRadius: 19).stroke(Color.white.opacity(season == s ? 0 : 0.1), lineWidth: 1))
                                    .shadow(color: season == s ? Color.brandPurple.opacity(0.4) : .clear, radius: 8, y: 3)
                            }
                            .buttonStyle(PressScaleStyle())
                        }
                    }
                    .padding(.horizontal, 16)
                }

                let eps = det.seasons[String(season)] ?? []
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10),
                                    GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(eps) { ep in
                        Button(action: { episode = ep }) {
                            Text("\(ep.n)")
                                .font(.system(size: 15.5, weight: .black))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity).padding(.vertical, 13)
                                .background(episode?.n == ep.n ? AnyShapeStyle(Color.brandGradient) : AnyShapeStyle(Color.white.opacity(0.06)))
                                .cornerRadius(12)
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(episode?.n == ep.n ? 0 : 0.09), lineWidth: 1))
                                .shadow(color: episode?.n == ep.n ? Color.brandPurple.opacity(0.4) : .clear, radius: 8, y: 3)
                        }
                        .buttonStyle(PressScaleStyle())
                    }
                }
                .padding(.horizontal, 16)

                if let ep = episode {
                    serverButtons(servers: ep.servers, defaultURL: ep.defaultURL,
                                  title: "\(card.t.isEmpty ? card.l : card.t) — الموسم \(season) حلقة \(ep.n)")
                } else {
                    Text("اختر حلقة لعرض سيرفراتها")
                        .font(.system(size: 13)).foregroundColor(.gray)
                        .padding(.horizontal, 16)
                }
            }
        } else if !det.servers.isEmpty {
            serverButtons(servers: det.servers, defaultURL: det.defaultURL,
                          title: card.t.isEmpty ? card.l : card.t)
        } else {
            Text("لا توجد سيرفرات متاحة لهذا العنوان حالياً")
                .font(.system(size: 13)).foregroundColor(.gray)
                .padding(.horizontal, 16)
        }
    }

    @ViewBuilder
    private func serverButtons(servers: [Server], defaultURL: String?, title: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let first = servers.first {
                NavigationLink(destination: PlayerView(title: title, servers: servers,
                                                       initialURL: defaultURL ?? first.url)) {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle().fill(Color.white)
                            Image(systemName: "play.fill")
                                .font(.system(size: 12, weight: .black))
                                .foregroundColor(Color.brandViolet)
                        }
                        .frame(width: 30, height: 30)
                        Text("شاهد الآن").font(.system(size: 16.5, weight: .black))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(Color.brandGradient).cornerRadius(15)
                    .shadow(color: Color.brandPurple.opacity(0.5), radius: 14, y: 6)
                }
                .buttonStyle(PressScaleStyle())
                .padding(.horizontal, 16)
            }
        }
    }
}

// MARK: - Player

struct PlayerView: View {
    let title: String
    let servers: [Server]
    @State private var idx: Int
    @State private var phase = 0
    @State private var switched = false

    init(title: String, servers: [Server], initialURL: String) {
        self.title = title
        self.servers = servers
        var start = 0
        for i in servers.indices {
            if cleanURL(servers[i].url) == cleanURL(initialURL) {
                start = i
                break
            }
        }
        _idx = State(initialValue: start)
    }

    private var currentURL: String {
        if servers.isEmpty { return "" }
        return cleanURL(servers[idx].url)
    }

    private func advance() {
        if idx + 1 < servers.count {
            switched = true
            phase = 0
            idx += 1
        } else {
            phase = 2
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color.black
                if !servers.isEmpty && phase != 2 {
                    PlayerWebView(url: currentURL,
                                  onSuccess: { phase = 1 },
                                  onFailure: { advance() })
                        .id(currentURL)
                }
                if phase == 0 {
                    VStack(spacing: 12) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.3)
                        Text(switched ? "السيرفر ما اشتغل — أبدّل لغيره…" : "جاري تجهيز الفيديو…")
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundColor(.white.opacity(0.85))
                    }
                }
                if phase == 2 {
                    VStack(spacing: 11) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(Color.brandGold).font(.system(size: 26))
                        Text("ما اشتغل أي سيرفر لهذا العنوان")
                            .font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                        Text("تأكد من اتصالك وجرّب مرة ثانية")
                            .font(.system(size: 12.5)).foregroundColor(.gray)
                        Button(action: { idx = 0; switched = false; phase = 0 }) {
                            Text("حاول مجدداً")
                                .font(.system(size: 14, weight: .black)).foregroundColor(.white)
                                .padding(.horizontal, 22).padding(.vertical, 10)
                                .background(Color.brandGradient).cornerRadius(12)
                        }
                        .buttonStyle(PressScaleStyle())
                        .padding(.top, 4)
                    }
                    .padding(16)
                }
            }
            .aspectRatio(16/9, contentMode: .fit)
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.1), lineWidth: 1))
            .padding(.horizontal, 12)
            .padding(.top, 10)

            HStack(spacing: 8) {
                Image(systemName: "lightbulb.fill").foregroundColor(Color.brandGold).font(.system(size: 13))
                Text("التطبيق يبدّل تلقائياً بين السيرفرات إذا توقف واحد، وللصورة داخل صورة (PiP) كبّر الفيديو من زر ملء الشاشة داخل المشغّل.")
                    .font(.system(size: 12)).foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.leading)
            }
            .padding(13)
            .background(Color.white.opacity(0.04)).cornerRadius(13)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            Spacer()
        }
        .background(AmbienceBackground())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PlayerWebView: UIViewRepresentable {
    let url: String
    var onSuccess: () -> Void = {}
    var onFailure: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsPictureInPictureMediaPlayback = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.websiteDataStore = WKWebsiteDataStore.default()
        config.processPool = WKProcessPool()

        // In the player, window.open is purely the ad pop-up door — kill it
        // in every frame, main included.
        let script = WKUserScript(source: "try { window.open = function() { return null; }; } catch (e) {}",
                                  injectionTime: .atDocumentStart,
                                  forMainFrameOnly: false)
        config.userContentController.addUserScript(script)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        context.coordinator.loadedURL = url
        context.coordinator.onSuccess = onSuccess
        context.coordinator.onFailure = onFailure
        if let store = WKContentRuleListStore.default() {
            store.compileContentRuleList(forIdentifier: "shofha-adblock",
                                         encodedContentRuleList: AdBlocker.ruleListJSON()) { list, _ in
                DispatchQueue.main.async {
                    if let list = list { config.userContentController.add(list) }
                    if let u = URL(string: url) {
                        context.coordinator.beginLoad()
                        webView.load(URLRequest(url: u))
                    }
                }
            }
        } else if let u = URL(string: url) {
            context.coordinator.beginLoad()
            webView.load(URLRequest(url: u))
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.onSuccess = onSuccess
        context.coordinator.onFailure = onFailure
        if context.coordinator.loadedURL != url {
            context.coordinator.loadedURL = url
            if let u = URL(string: url) {
                context.coordinator.beginLoad()
                uiView.load(URLRequest(url: u))
            }
        }
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var loadedURL: String = ""
        var onSuccess: () -> Void = {}
        var onFailure: () -> Void = {}
        private var generation = 0
        private var resolved = false
        private var watchdog: DispatchWorkItem?
        private var probeItem: DispatchWorkItem?
        private var finishedOnce = false
        private var probeCycle = 0
        private var probeIndex = 0
        private var emptyStreak = 0

        static let probeJS = "(function() { var t = ''; try { t = (document.body ? document.body.innerText : '').toLowerCase(); } catch (e) {} var dead = ['file not found', 'video not found', 'file was deleted', 'this video has been deleted', 'video has been removed', 'no longer available', 'الفيديو غير متوفر', 'تم حذف هذا']; for (var i = 0; i < dead.length; i++) { if (t.indexOf(dead[i]) >= 0) { return 'dead'; } } if (document.querySelector('video')) { return 'video'; } if (document.querySelector('iframe')) { return 'frame'; } return 'empty'; })()"

        func beginLoad() {
            generation += 1
            resolved = false
            finishedOnce = false
            probeCycle = 0
            probeIndex = 0
            emptyStreak = 0
            watchdog?.cancel()
            probeItem?.cancel()
            let gen = generation
            let item = DispatchWorkItem { [weak self] in
                guard let self = self, self.generation == gen, !self.resolved else { return }
                if self.finishedOnce { return }
                self.fail()
            }
            watchdog = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 35, execute: item)
        }

        private func succeed() {
            if resolved { return }
            resolved = true
            watchdog?.cancel()
            probeItem?.cancel()
            onSuccess()
        }

        private func fail() {
            if resolved { return }
            resolved = true
            watchdog?.cancel()
            probeItem?.cancel()
            onFailure()
        }

        private func scheduleProbe(_ webView: WKWebView, gen: Int, cycle: Int, delay: Double) {
            probeItem?.cancel()
            let item = DispatchWorkItem { [weak self] in
                guard let self = self, self.generation == gen, self.probeCycle == cycle, !self.resolved else { return }
                webView.evaluateJavaScript(Coordinator.probeJS) { [weak self] result, _ in
                    guard let self = self, self.generation == gen, self.probeCycle == cycle, !self.resolved else { return }
                    let r = (result as? String) ?? "empty"
                    if r == "dead" {
                        self.fail()
                        return
                    }
                    if r == "video" || r == "frame" {
                        self.succeed()
                        return
                    }
                    self.emptyStreak += 1
                    self.probeIndex += 1
                    if self.emptyStreak >= 3 || self.probeIndex >= 3 {
                        self.fail()
                        return
                    }
                    let nextDelay: Double = self.probeIndex == 1 ? 3 : 2
                    self.scheduleProbe(webView, gen: gen, cycle: cycle, delay: nextDelay)
                }
            }
            probeItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if resolved { return }
            finishedOnce = true
            watchdog?.cancel()
            probeCycle += 1
            probeIndex = 0
            emptyStreak = 0
            scheduleProbe(webView, gen: generation, cycle: probeCycle, delay: 5)
        }

        private func isIgnorable(_ error: Error) -> Bool {
            let e = error as NSError
            if e.code == NSURLErrorCancelled { return true }
            if e.domain == "WebKitErrorDomain" && e.code == 102 { return true }
            let desc = e.localizedDescription.lowercased()
            if desc.contains("frame load interrupted") { return true }
            return false
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            if isIgnorable(error) { return }
            fail()
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            if isIgnorable(error) { return }
            fail()
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url,
                  let scheme = url.scheme?.lowercased() else {
                decisionHandler(.allow)
                return
            }
            guard scheme == "http" || scheme == "https" || scheme == "about" || scheme == "data" || scheme == "blob" else {
                if UIApplication.shared.canOpenURL(url) { UIApplication.shared.open(url) }
                decisionHandler(.cancel)
                return
            }
            if AdBlocker.isAdHost(url.host) {
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        // Every pop-up inside the player is an ad — none are ever loaded.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url,
               let scheme = url.scheme?.lowercased(), scheme != "http" && scheme != "https" {
                if UIApplication.shared.canOpenURL(url) { UIApplication.shared.open(url) }
            }
            return nil
        }
    }
}

// MARK: - Ad blocking (shared)

enum AdBlocker {
    static let domains: [String] = [
        "popads.net", "popcash.net", "poponclick.com", "onclickads.net",
        "onclickperformance.com", "onadclick.com",
        "exosrv.com", "exdynsrv.com", "exoclick.com",
        "adcash.com", "propellerads.com", "hilltopads.com",
        "trafficjunky.com", "juicyads.com", "a-ads.com", "bidvertiser.com",
        "mgid.com", "adskeeper.com", "tsyndicate.com",
        "doubleclick.net", "googlesyndication.com", "googleadservices.com",
        "amazon-adsystem.com", "adsterra.com", "highperformanceformat.com",
        "profitablecpmrate.com", "effectivecpmcontent.com",
        "clickadu.com", "monetag.com", "evadav.com", "galaksion.com",
        "rollerads.com", "zeydoo.com"
    ]

    static func isAdHost(_ host: String?) -> Bool {
        guard let h = host?.lowercased() else { return false }
        return domains.contains { h == $0 || h.hasSuffix("." + $0) }
    }

    static func ruleListJSON() -> String {
        let rules: [[String: Any]] = [[
            "trigger": ["url-filter": ".*",
                        "if-domain": domains.map { "*" + $0 }],
            "action": ["type": "block"]
        ]]
        if let data = try? JSONSerialization.data(withJSONObject: rules),
           let json = String(data: data, encoding: .utf8) {
            return json
        }
        return "[]"
    }
}
