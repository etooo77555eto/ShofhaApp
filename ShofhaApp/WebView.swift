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
    var seasonNumbers: [Int] { seasons.keys.compactMap { Int($0) }.sorted() }
}

extension Detail: Decodable {
    enum CodingKeys: String, CodingKey { case story, servers, dur, country, seasons; case defaultURL = "default" }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        story = try c.decodeIfPresent(String.self, forKey: .story) ?? ""
        servers = try c.decodeIfPresent([Server].self, forKey: .servers) ?? []
        defaultURL = try c.decodeIfPresent(String.self, forKey: .defaultURL)
        var parsedDur: Int? = nil
        if let dv = try? c.decodeIfPresent(Int.self, forKey: .dur), let v = dv {
            parsedDur = v
        } else if let ds = try? c.decodeIfPresent(String.self, forKey: .dur), let sv = ds {
            parsedDur = Int(sv)
        }
        dur = parsedDur
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
        let src = indexReady || !allCards.isEmpty ? allCards : (homeCards(ofKind: kind))
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
        let pool = allCards.isEmpty ? (home?.hero ?? []) + (home?.trend ?? []) + (home?.films ?? []) + (home?.series ?? []) + (home?.anime ?? []) + (home?.turk ?? []) : allCards
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

// MARK: - Root

struct ContentView: View {
    @StateObject private var store = AppStore()

    var body: some View {
        Group {
            if let err = store.loadError, store.home == nil {
                ZStack {
                    Color.brandBg.ignoresSafeArea()
                    VStack(spacing: 14) {
                        Text("📡").font(.system(size: 44))
                        Text("ماكو اتصال").font(.headline).foregroundColor(.white)
                        Text(err).font(.footnote).foregroundColor(.gray)
                        Button("حاول مرة ثانية") {
                            store.loadError = nil
                            Task { await store.loadHome() }
                        }
                        .padding(.horizontal, 22).padding(.vertical, 10)
                        .background(Color.brandGradient).foregroundColor(.white).cornerRadius(12)
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
                VStack(alignment: .leading, spacing: 26) {
                    HeroPager(cards: home.hero)
                    CardRowView(title: "🔥 ترند شوفها اليوم", cards: home.trend)

                    if !home.cols.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("مجموعات مختارة")
                                .font(.system(size: 17, weight: .bold)).foregroundColor(.white)
                                .padding(.horizontal, 16)
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
                                            .font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
                                            .padding(.horizontal, 14).padding(.vertical, 8)
                                            .background(Color.brandCard).cornerRadius(16)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }

                    CardRowView(title: "🎬 أحدث الأفلام", cards: home.films)
                    CardRowView(title: "📺 أحدث المسلسلات", cards: home.series)
                    CardRowView(title: "🌸 أحدث الأنمي", cards: home.anime)

                    if !home.turk.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("🇹🇷 مسلسلات تركية")
                                    .font(.system(size: 17, weight: .bold)).foregroundColor(.white)
                                Spacer()
                                NavigationLink(destination: TurkView()) {
                                    Text("الكل").font(.system(size: 13)).foregroundColor(Color.brandCyan)
                                }
                            }
                            .padding(.horizontal, 16)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(alignment: .top, spacing: 12) {
                                    ForEach(home.turk) { card in
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

                    Link(destination: URL(string: "https://t.me/shofha10")!) {
                        HStack {
                            Image(systemName: "paperplane.fill")
                            Text("تابعنا على تيليجرام").font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.brandGradient).cornerRadius(12)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
                }
                .padding(.top, 4)
            }
        }
        .background(Color.brandBg.ignoresSafeArea())
        .navigationTitle("شوفها")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct HeroPager: View {
    let cards: [Card]
    @State private var page = 0
    var body: some View {
        TabView(selection: $page) {
            ForEach(cards.prefix(8).indices, id: \.self) { idx in
                NavigationLink(destination: DetailView(card: cards[idx])) {
                    ZStack(alignment: .bottomLeading) {
                        PosterView(url: cards[idx].p)
                        LinearGradient(colors: [.clear, Color.brandBg],
                                       startPoint: .center, endPoint: .bottom)
                        VStack(alignment: .leading, spacing: 6) {
                            if let r = cards[idx].r {
                                HStack(spacing: 3) {
                                    Image(systemName: "star.fill").foregroundColor(.yellow).font(.system(size: 11))
                                    Text(String(format: "%.1f", r)).font(.system(size: 12, weight: .bold)).foregroundColor(.white)
                                    if let y = cards[idx].y { Text("• \(String(y))").font(.system(size: 12)).foregroundColor(.gray) }
                                }
                            }
                            Text(cards[idx].t.isEmpty ? cards[idx].l : cards[idx].t)
                                .font(.system(size: 22, weight: .black)).foregroundColor(.white)
                                .lineLimit(2).multilineTextAlignment(.leading)
                            HStack(spacing: 6) {
                                Image(systemName: "play.fill").font(.system(size: 12))
                                Text("شاهد الآن").font(.system(size: 13, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .background(Color.brandGradient).cornerRadius(20)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .buttonStyle(.plain)
                .tag(idx)
            }
        }
        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .automatic))
        .frame(height: 460)
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
                        PosterView(url: p).frame(width: 52, height: 76).cornerRadius(6)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(info.brand ?? info.name)
                    .font(.system(size: 15, weight: .black)).foregroundColor(info.titleColor)
                    .lineLimit(1)
                if let count = info.count {
                    Text("\(count) عنوان").font(.system(size: 11)).foregroundColor(info.titleColor.opacity(0.8))
                }
            }
            .padding(10)
        }
        .frame(width: 190, height: 150)
        .cornerRadius(14)
    }
}

struct CollectionView: View {
    let info: CollectionInfo
    @EnvironmentObject var store: AppStore
    @State private var cards: [Card] = []
    var body: some View {
        ScrollView {
            if cards.isEmpty {
                ProgressView().tint(.white).padding(.top, 60)
            } else {
                GridView(cards: cards)
            }
        }
        .background(Color.brandBg.ignoresSafeArea())
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
        .background(Color.brandBg.ignoresSafeArea())
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
                    ProgressView().tint(.white)
                    Text("جاري تحميل الكتالوج...").font(.footnote).foregroundColor(.gray)
                }
                .padding(.top, 60)
            }
        }
        .background(Color.brandBg.ignoresSafeArea())
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
            VStack(alignment: .leading, spacing: 14) {
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
        .background(Color.brandBg.ignoresSafeArea())
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
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(active ? .white : .gray)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(active ? Color.brandPurple : Color.brandCard)
                .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }
}

struct SearchView: View {
    @EnvironmentObject var store: AppStore
    @State private var query = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundColor(.gray)
                    TextField("ابحث عن فيلم أو مسلسل...", text: $query)
                        .foregroundColor(.white)
                        .submitLabel(.search)
                    if !query.isEmpty {
                        Button(action: { query = "" }) {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.gray)
                        }
                    }
                }
                .padding(12)
                .background(Color.brandCard).cornerRadius(12)
                .padding(.horizontal, 16)

                if query.trimmingCharacters(in: .whitespaces).count < 2 {
                    VStack(spacing: 10) {
                        Text("ابحث بالعربي أو بالإنجليزي")
                            .font(.system(size: 14)).foregroundColor(.gray)
                        if !store.indexReady {
                            Text("جاري تحميل الكتالوج كامل للبحث...")
                                .font(.footnote).foregroundColor(.gray)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
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
        .background(Color.brandBg.ignoresSafeArea())
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
            VStack(alignment: .leading, spacing: 18) {
                header
                if let det = detail {
                    if !det.story.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("القصة").font(.system(size: 16, weight: .bold)).foregroundColor(.white)
                            Text(det.story).font(.system(size: 14)).foregroundColor(.gray)
                                .lineSpacing(4).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 16)
                    }
                    watchSection(det)
                } else {
                    ProgressView().tint(.white)
                        .frame(maxWidth: .infinity).padding(.top, 30)
                }
            }
            .padding(.bottom, 24)
        }
        .background(Color.brandBg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .task {
            detail = await store.detail(for: card)
            if let first = detail?.seasonNumbers.first { season = first }
        }
    }

    private var header: some View {
        ZStack(alignment: .bottomLeading) {
            PosterView(url: card.p)
                .frame(height: 340)
                .blur(radius: 24)
                .opacity(0.55)
            LinearGradient(colors: [.clear, Color.brandBg], startPoint: .top, endPoint: .bottom)
            HStack(alignment: .bottom, spacing: 14) {
                PosterView(url: card.p)
                    .frame(width: 110, height: 165)
                    .cornerRadius(10)
                VStack(alignment: .leading, spacing: 6) {
                    Text(card.t.isEmpty ? card.l : card.t)
                        .font(.system(size: 20, weight: .black)).foregroundColor(.white)
                        .lineLimit(3)
                    if !card.l.isEmpty && card.l != card.t {
                        Text(card.l).font(.system(size: 12)).foregroundColor(.gray).lineLimit(1)
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
                            .font(.system(size: 11)).foregroundColor(Color.brandCyan).lineLimit(2)
                    }
                }
            }
            .padding(16)
        }
        .frame(height: 340)
    }

    private func metaChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold)).foregroundColor(.white)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color.white.opacity(0.14)).cornerRadius(8)
    }

    @ViewBuilder
    private func watchSection(_ det: Detail) -> some View {
        if !det.seasonNumbers.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(det.seasonNumbers, id: \.self) { s in
                            Button(action: { season = s; episode = nil }) {
                                Text("الموسم \(s)")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(season == s ? .white : .gray)
                                    .padding(.horizontal, 16).padding(.vertical, 9)
                                    .background(season == s ? Color.brandPurple : Color.brandCard)
                                    .cornerRadius(18)
                            }
                            .buttonStyle(.plain)
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
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(episode?.n == ep.n ? .white : .gray)
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                                .background(episode?.n == ep.n ? Color.brandPurple : Color.brandCard)
                                .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
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
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                        Text("شاهد الآن").font(.system(size: 16, weight: .black))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(Color.brandGradient).cornerRadius(14)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
            }
            Text("السيرفرات")
                .font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                .padding(.horizontal, 16)
            ForEach(servers.indices, id: \.self) { si in
                let srv = servers[si]
                NavigationLink(destination: PlayerView(title: title, servers: servers, initialURL: srv.url)) {
                    HStack {
                        Image(systemName: "play.rectangle.fill").foregroundColor(Color.brandCyan)
                        Text(srv.label).font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                        Spacer()
                        if srv.url == defaultURL {
                            Text("افتراضي").font(.system(size: 10)).foregroundColor(.gray)
                        }
                        Image(systemName: "chevron.left").font(.system(size: 11)).foregroundColor(.gray)
                    }
                    .padding(14)
                    .background(Color.brandCard).cornerRadius(12)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
            }
        }
    }
}

// MARK: - Player

struct PlayerView: View {
    let title: String
    let servers: [Server]
    @State private var currentURL: String

    init(title: String, servers: [Server], initialURL: String) {
        self.title = title
        self.servers = servers
        _currentURL = State(initialValue: cleanURL(initialURL))
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color.black
                PlayerWebView(url: currentURL)
            }
            .aspectRatio(16/9, contentMode: .fit)

            if servers.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(servers.indices, id: \.self) { si in
                            let srv = servers[si]
                            Button(action: { currentURL = cleanURL(srv.url) }) {
                                Text(srv.label)
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(cleanURL(srv.url) == currentURL ? .white : .gray)
                                    .padding(.horizontal, 14).padding(.vertical, 8)
                                    .background(cleanURL(srv.url) == currentURL ? Color.brandPurple : Color.brandCard)
                                    .cornerRadius(16)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.vertical, 12)
            }

            Text("إذا توقف السيرفر، بدّل لسيرفر ثاني من الأزرار فوق. صغّر الفيديو لصورة داخل صورة (PiP) من زر ملء الشاشة داخل المشغّل.")
                .font(.system(size: 12)).foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
        }
        .background(Color.brandBg.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PlayerWebView: UIViewRepresentable {
    let url: String

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
        if let store = WKContentRuleListStore.default() {
            store.compileContentRuleList(forIdentifier: "shofha-adblock",
                                         encodedContentRuleList: AdBlocker.ruleListJSON()) { list, _ in
                DispatchQueue.main.async {
                    if let list = list { config.userContentController.add(list) }
                    if let u = URL(string: url) { webView.load(URLRequest(url: u)) }
                }
            }
        } else if let u = URL(string: url) {
            webView.load(URLRequest(url: u))
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if context.coordinator.loadedURL != url {
            context.coordinator.loadedURL = url
            if let u = URL(string: url) { uiView.load(URLRequest(url: u)) }
        }
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var loadedURL: String = ""

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
