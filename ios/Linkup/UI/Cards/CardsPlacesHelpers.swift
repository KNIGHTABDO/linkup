import SwiftUI
import MapKit
import CoreLocation
import Foundation

// MARK: - Date Helpers

enum PlacesDateParser {
    static func parse(_ raw: String?) -> Date? {
        CardDates.parse(raw)
    }

    static func monthAbbreviation(from date: Date) -> String {
        CardDates.monthAbbreviation(from: date)
    }

    static func dayNumber(from date: Date) -> String {
        date.formatted(.dateTime.day())
    }

    static func formatTimeRange(start: Date?, end: Date?) -> String {
        let timeStyle = Date.FormatStyle(date: .omitted, time: .shortened)
        let fullStyle = Date.FormatStyle(date: .abbreviated, time: .shortened)

        guard let start else {
            return end.map { String(localized: "Until") + " " + $0.formatted(timeStyle) } ?? String(localized: "Date TBD")
        }
        guard let end else {
            return start.formatted(fullStyle)
        }
        if Calendar.current.isDate(start, inSameDayAs: end) {
            return "\(start.formatted(timeStyle)) – \(end.formatted(timeStyle))"
        }
        return "\(start.formatted(fullStyle)) – \(end.formatted(fullStyle))"
    }
}

// MARK: - ICS File Generator

enum PlacesICSGenerator {
    static func createEventICS(
        title: String,
        start: Date?,
        end: Date?,
        location: String?,
        description: String?,
        url: URL?
    ) -> URL? {
        let now = Date()
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        df.timeZone = TimeZone(secondsFromGMT: 0)

        let dtStamp = df.string(from: now)
        let dtStart = start.map { df.string(from: $0) } ?? dtStamp
        let dtEnd = end.map { df.string(from: $0) } ?? (start.map { df.string(from: $0.addingTimeInterval(3600)) } ?? dtStamp)

        var lines = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//Linkup//Places Event Card//EN",
            "CALSCALE:GREGORIAN",
            "METHOD:PUBLISH",
            "BEGIN:VEVENT",
            "UID:\(UUID().uuidString)",
            "DTSTAMP:\(dtStamp)",
            "DTSTART:\(dtStart)",
            "DTEND:\(dtEnd)",
            "SUMMARY:\(escape(title))"
        ]

        if let location, !location.isEmpty {
            lines.append("LOCATION:\(escape(location))")
        }
        if let description, !description.isEmpty {
            lines.append("DESCRIPTION:\(escape(description))")
        }
        if let url {
            lines.append("URL:\(url.absoluteString)")
        }

        lines.append("END:VEVENT")
        lines.append("END:VCALENDAR")

        let icsData = lines.joined(separator: "\r\n").data(using: .utf8)

        let safeTitle = String(title.components(separatedBy: CharacterSet.alphanumerics.inverted).joined().prefix(48))
        let filename = safeTitle.isEmpty ? "event.ics" : "\(safeTitle).ics"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        do {
            try icsData?.write(to: tempURL, options: .atomic)
            return tempURL
        } catch {
            return nil
        }
    }

    private static func escape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\r\n", with: "\\n")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\n")
    }
}

// MARK: - Geocoding & Local Search Service

@MainActor
final class PlacesGeocodingService {
    static let shared = PlacesGeocodingService()
    private var cache: [String: CLLocationCoordinate2D] = [:]
    private var itemCache: [String: MKMapItem] = [:]

    func geocode(query: String) async -> CLLocationCoordinate2D? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let cached = cache[trimmed] {
            return cached
        }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        let search = MKLocalSearch(request: request)

        do {
            let response = try await search.start()
            if let first = response.mapItems.first {
                let coord = first.placemark.coordinate
                cache[trimmed] = coord
                itemCache[trimmed] = first
                return coord
            }
        } catch {
            // Graceful fallback to nil
        }

        return nil
    }

    func searchItem(query: String) async -> MKMapItem? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let cached = itemCache[trimmed] {
            return cached
        }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        let search = MKLocalSearch(request: request)

        do {
            let response = try await search.start()
            if let first = response.mapItems.first {
                cache[trimmed] = first.placemark.coordinate
                itemCache[trimmed] = first
                return first
            }
        } catch {
            // Graceful fallback
        }

        return nil
    }
}

// MARK: - Open Maps Helper

enum PlacesOpenMapsHelper {
    static func open(coordinate: CLLocationCoordinate2D, name: String?, isDirections: Bool = false) {
        let placemark = MKPlacemark(coordinate: coordinate)
        let item = MKMapItem(placemark: placemark)
        item.name = name

        if isDirections {
            item.openInMaps(launchOptions: [
                MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault
            ])
        } else {
            item.openInMaps()
        }
    }

    static func openRoute(
        from: CLLocationCoordinate2D?,
        fromName: String?,
        to: CLLocationCoordinate2D,
        toName: String?,
        mode: String?
    ) {
        let destPlacemark = MKPlacemark(coordinate: to)
        let destItem = MKMapItem(placemark: destPlacemark)
        destItem.name = toName

        var launchOptions: [String: Any] = [:]
        switch mode?.lowercased() {
        case "walking":
            launchOptions[MKLaunchOptionsDirectionsModeKey] = MKLaunchOptionsDirectionsModeWalking
        case "transit":
            launchOptions[MKLaunchOptionsDirectionsModeKey] = MKLaunchOptionsDirectionsModeTransit
        case "driving", "cycling":
            launchOptions[MKLaunchOptionsDirectionsModeKey] = MKLaunchOptionsDirectionsModeDriving
        default:
            launchOptions[MKLaunchOptionsDirectionsModeKey] = MKLaunchOptionsDirectionsModeDefault
        }

        if let from {
            let srcPlacemark = MKPlacemark(coordinate: from)
            let srcItem = MKMapItem(placemark: srcPlacemark)
            srcItem.name = fromName
            MKMapItem.openMaps(with: [srcItem, destItem], launchOptions: launchOptions)
        } else {
            destItem.openInMaps(launchOptions: launchOptions)
        }
    }
}

// MARK: - Map Snapshot Service

@MainActor
final class PlacesMapSnapshotterService {
    static let shared = PlacesMapSnapshotterService()
    private var cache: [String: UIImage] = [:]

    func snapshot(for coordinate: CLLocationCoordinate2D, size: CGSize = CGSize(width: 360, height: 202)) async -> UIImage? {
        let key = String(format: "%.4f,%.4f_%.0fx%.0f", coordinate.latitude, coordinate.longitude, size.width, size.height)
        if let cached = cache[key] {
            return cached
        }

        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(center: coordinate, latitudinalMeters: 600, longitudinalMeters: 600)
        options.size = size
        options.traitCollection = UITraitCollection(userInterfaceStyle: .dark)

        let snapshotter = MKMapSnapshotter(options: options)

        let image = await withCheckedContinuation { continuation in
            snapshotter.start { snapshot, _ in
                continuation.resume(returning: snapshot?.image)
            }
        }

        if let image {
            cache[key] = image
        }
        return image
    }
}

// MARK: - Open-Meteo Weather Service & Models

struct PlacesWeatherResponse: Codable, Sendable {
    let current: PlacesWeatherCurrent?
    let hourly: PlacesWeatherHourly?
    let daily: PlacesWeatherDaily?
}

struct PlacesWeatherCurrent: Codable, Sendable {
    let temperature_2m: Double?
    let weather_code: Int?
    let wind_speed_10m: Double?
    let relative_humidity_2m: Double?
    let is_day: Int?
    let time: String?
}

struct PlacesWeatherHourly: Codable, Sendable {
    let time: [String]?
    let temperature_2m: [Double]?
    let weather_code: [Int]?
    let is_day: [Int]?
}

struct PlacesWeatherDaily: Codable, Sendable {
    let time: [String]?
    let weather_code: [Int]?
    let temperature_2m_max: [Double]?
    let temperature_2m_min: [Double]?
}

struct PlacesGeocodingResponse: Codable, Sendable {
    let results: [PlacesGeocodingResult]?
}

struct PlacesGeocodingResult: Codable, Sendable {
    let name: String
    let latitude: Double
    let longitude: Double
    let country: String?
}

enum PlacesWeatherCondition {
    case clearSky(isDay: Bool)
    case partlyCloudy(isDay: Bool)
    case overcast
    case fog
    case drizzle
    case rain
    case snow
    case thunderstorm

    static func from(code: Int, isDay: Bool = true) -> PlacesWeatherCondition {
        switch code {
        case 0: return .clearSky(isDay: isDay)
        case 1, 2: return .partlyCloudy(isDay: isDay)
        case 3: return .overcast
        case 45, 48: return .fog
        case 51, 53, 55, 56, 57: return .drizzle
        case 61, 63, 65, 66, 67, 80, 81, 82: return .rain
        case 71, 73, 75, 77, 85, 86: return .snow
        case 95, 96, 99: return .thunderstorm
        default: return .partlyCloudy(isDay: isDay)
        }
    }

    var symbol: String {
        switch self {
        case .clearSky(let isDay): return isDay ? "sun.max.fill" : "moon.stars.fill"
        case .partlyCloudy(let isDay): return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case .overcast: return "cloud.fill"
        case .fog: return "cloud.fog.fill"
        case .drizzle: return "cloud.drizzle.fill"
        case .rain: return "cloud.rain.fill"
        case .snow: return "cloud.snow.fill"
        case .thunderstorm: return "cloud.bolt.rain.fill"
        }
    }

    var description: String {
        switch self {
        case .clearSky: return "Clear"
        case .partlyCloudy: return "Partly Cloudy"
        case .overcast: return "Overcast"
        case .fog: return "Fog"
        case .drizzle: return "Drizzle"
        case .rain: return "Rain"
        case .snow: return "Snow"
        case .thunderstorm: return "Thunderstorm"
        }
    }

    /// Single tint per condition; the gradient is derived from Theme.surface / Theme.elevated.
    var tint: Color {
        switch self {
        case .clearSky(let isDay): return isDay ? Color.blue : Color.indigo
        case .partlyCloudy(let isDay): return isDay ? Color.blue.opacity(0.8) : Color.indigo.opacity(0.8)
        case .overcast, .fog: return Color.gray
        case .drizzle, .rain: return Color.teal
        case .snow: return Color.cyan
        case .thunderstorm: return Color.purple
        }
    }

    var gradientColors: [Color] {
        [tint.mix(with: Theme.surface, by: 0.55), tint.mix(with: Theme.elevated, by: 0.8)]
    }
}

@MainActor
final class PlacesWeatherService {
    static let shared = PlacesWeatherService()
    private static let ttl: TimeInterval = 15 * 60
    private var forecastCache: [String: (date: Date, value: PlacesWeatherResponse)] = [:]
    private var geocodeCache: [String: (lat: Double, lon: Double, name: String)] = [:]

    func fetchWeather(lat: Double, lon: Double) async throws -> PlacesWeatherResponse {
        let key = "\(lat.formatted(.number.precision(.fractionLength(3)).locale(Locale(identifier: "en_US_POSIX")))),\(lon.formatted(.number.precision(.fractionLength(3)).locale(Locale(identifier: "en_US_POSIX"))))"
        if let cached = forecastCache[key], Date().timeIntervalSince(cached.date) < Self.ttl {
            return cached.value
        }

        guard let url = cardMakeURL(
            host: "api.open-meteo.com",
            path: "/v1/forecast",
            queryItems: [
                URLQueryItem(name: "latitude", value: String(lat)),
                URLQueryItem(name: "longitude", value: String(lon)),
                URLQueryItem(name: "current", value: "temperature_2m,weather_code,wind_speed_10m,relative_humidity_2m,is_day"),
                URLQueryItem(name: "hourly", value: "temperature_2m,weather_code,is_day"),
                URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min"),
                URLQueryItem(name: "timezone", value: "auto"),
                URLQueryItem(name: "forecast_days", value: "7")
            ]
        ) else {
            throw URLError(.badURL)
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(PlacesWeatherResponse.self, from: data)
        forecastCache[key] = (Date(), decoded)
        return decoded
    }

    func geocode(location: String) async throws -> (lat: Double, lon: Double, name: String)? {
        let trimmed = location.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let cached = geocodeCache[trimmed] {
            return cached
        }

        guard let url = cardMakeURL(
            host: "geocoding-api.open-meteo.com",
            path: "/v1/search",
            queryItems: [
                URLQueryItem(name: "name", value: trimmed),
                URLQueryItem(name: "count", value: "1")
            ]
        ) else {
            return nil
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        let resp = try JSONDecoder().decode(PlacesGeocodingResponse.self, from: data)
        if let first = resp.results?.first {
            let res = (lat: first.latitude, lon: first.longitude, name: first.name)
            geocodeCache[trimmed] = res
            return res
        }
        return nil
    }
}

// MARK: - Currency Service

struct PlacesCurrencyResponse: Codable, Sendable {
    let result: String?
    let rates: [String: Double]?
    let time_last_update_utc: String?
}

@MainActor
final class PlacesCurrencyService {
    static let shared = PlacesCurrencyService()
    private static let ttl: TimeInterval = 60 * 60
    private var rateCache: [String: (date: Date, rates: [String: Double])] = [:]

    func fetchRate(from: String, to: String) async throws -> Double? {
        let base = from.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let target = to.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard base.count == 3, target.count == 3,
              base.allSatisfy({ $0.isLetter }), target.allSatisfy({ $0.isLetter }) else { return nil }

        if let cached = rateCache[base], Date().timeIntervalSince(cached.date) < Self.ttl, let rate = cached.rates[target] {
            return rate
        }

        guard let url = cardMakeURL(host: "open.er-api.com", path: "/v6/latest/\(base)", queryItems: []) else {
            return nil
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        let resp = try JSONDecoder().decode(PlacesCurrencyResponse.self, from: data)
        if let rates = resp.rates {
            rateCache[base] = (Date(), rates)
            return rates[target].flatMap { cardSafeDouble($0) }
        }
        return nil
    }
}

// MARK: - Reusable UI Components

/// 16:9 Hero photo carousel, falling back to MapKit snapshot if no photos
struct PlacesHeroCarousel: View {
    let photos: [String]
    let coordinate: CLLocationCoordinate2D?
    let name: String?

    var body: some View {
        if photos.contains(where: { placesWebURL($0) != nil }) {
            TabView {
                ForEach(photos.filter { placesWebURL($0) != nil }, id: \.self) { photoURL in
                    AsyncImage(url: placesWebURL(photoURL)) { phase in
                        switch phase {
                        case .empty:
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Theme.elevated)
                                .overlay(ProgressView().tint(Theme.secondaryText))
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(16/9, contentMode: .fill)
                        case .failure:
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Theme.elevated)
                                .overlay(
                                    Image(systemName: "photo")
                                        .font(.system(size: 28))
                                        .foregroundStyle(Theme.tertiaryText)
                                )
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityLabel(name ?? String(localized: "Place photo"))
                }
            }
            .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .automatic : .never))
            .aspectRatio(16/9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else {
            PlacesMapSnapshotView(coordinate: coordinate, name: name)
                .aspectRatio(16/9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

/// Static map snapshot or non-interactive map view
struct PlacesMapSnapshotView: View {
    let coordinate: CLLocationCoordinate2D?
    let name: String?

    @State private var snapshotImage: UIImage?
    @State private var snapshotFailed = false

    var body: some View {
        Group {
            if let snapshotImage {
                Image(uiImage: snapshotImage)
                    .resizable()
                    .aspectRatio(16/9, contentMode: .fill)
                    .overlay(
                        VStack {
                            Spacer()
                            HStack(spacing: 6) {
                                Image(systemName: "mappin.circle.fill")
                                    .foregroundStyle(Theme.accent)
                                if let name {
                                    Text(name)
                                        .font(Theme.sans(12, weight: .semibold))
                                        .foregroundStyle(Theme.text)
                                        .lineLimit(1)
                                        .cardTextDirection(name)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Theme.surface.opacity(0.85), in: Capsule())
                            .padding(10)
                        }
                    )
            } else if let coord = coordinate, CLLocationCoordinate2DIsValid(coord) {
                // No live Map in chat cards: placeholder with a fixed aspect until the snapshot arrives.
                Theme.elevated
                    .overlay {
                        if snapshotFailed {
                            Image(systemName: "map")
                                .font(.system(size: 28))
                                .foregroundStyle(Theme.tertiaryText)
                        } else {
                            ProgressView().tint(Theme.secondaryText)
                        }
                    }
                    .accessibilityHidden(true)
                    .id(coord.latitude)
            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.elevated)
                    .overlay(
                        VStack(spacing: 6) {
                            Image(systemName: "map.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(Theme.tertiaryText)
                            if let name {
                                Text(name)
                                    .font(Theme.sans(12))
                                    .foregroundStyle(Theme.secondaryText)
                            }
                        }
                    )
            }
        }
        .task(id: "\(coordinate?.latitude ?? 0),\(coordinate?.longitude ?? 0)") {
            guard let coord = coordinate, CLLocationCoordinate2DIsValid(coord) else { return }
            snapshotFailed = false
            snapshotImage = await PlacesMapSnapshotterService.shared.snapshot(for: coord)
            snapshotFailed = (snapshotImage == nil)
        }
    }
}

/// Small non-interactive map: a cached MKMapSnapshotter image (no live Map in chat cards).
struct PlacesMiniMapView: View {
    let coordinate: CLLocationCoordinate2D?
    let name: String?

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        if let coord = coordinate, CLLocationCoordinate2DIsValid(coord) {
            Color.clear
                .aspectRatio(16 / 7, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .overlay {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .overlay {
                                Image(systemName: "mappin.circle.fill")
                                    .font(.system(size: 26))
                                    .foregroundStyle(Theme.accent, Theme.surface)
                            }
                    } else {
                        Theme.elevated.overlay {
                            if failed {
                                Image(systemName: "map")
                                    .foregroundStyle(Theme.tertiaryText)
                            } else {
                                ProgressView().tint(Theme.secondaryText)
                            }
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.hairline))
                .overlay(alignment: .bottomTrailing) {
                    Button {
                        PlacesOpenMapsHelper.open(coordinate: coord, name: name)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.right")
                                .font(Theme.sans(11, weight: .bold))
                            Text("Open")
                                .font(Theme.sans(12, weight: .semibold))
                                .lineLimit(1)
                                .fixedSize()
                        }
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(Theme.surface.opacity(0.9), in: Capsule())
                    .overlay(Capsule().stroke(Theme.hairline))
                    .padding(4)
                    .accessibilityLabel(Text("Open in Maps"))
                }
                .accessibilityElement(children: .contain)
                .task(id: "\(coord.latitude),\(coord.longitude)") {
                    failed = false
                    let result = await PlacesMapSnapshotterService.shared.snapshot(
                        for: coord, size: CGSize(width: 360, height: 158))
                    image = result
                    failed = (result == nil)
                }
        }
    }
}

/// Action buttons row: solid surface chips with hairline (Directions, Call, Website, Share)
struct PlacesActionButtonsRow: View {
    let coordinate: CLLocationCoordinate2D?
    let name: String?
    let phone: String?
    let website: URL?

    @Environment(\.openURL) private var openURL

    var shareText: String {
        var parts: [String] = []
        if let name { parts.append(name) }
        if let website { parts.append(website.absoluteString) }
        return parts.joined(separator: " - ")
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if let coord = coordinate, CLLocationCoordinate2DIsValid(coord) {
                    Button {
                        PlacesOpenMapsHelper.open(coordinate: coord, name: name, isDirections: true)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Directions")
                                .font(Theme.sans(13, weight: .medium))
                        }
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .background(Theme.surface, in: Capsule())
                    .overlay(Capsule().stroke(Theme.hairline))
                }

                if let phone, !phone.isEmpty {
                    let cleaned = phone.filter { ($0.isASCII && $0.isNumber) || $0 == "+" }
                    if !cleaned.isEmpty, let telURL = URL(string: "tel:\(cleaned)") {
                        Button {
                            openURL(telURL)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "phone.fill")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("Call")
                                    .font(Theme.sans(13, weight: .medium))
                            }
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                            .fixedSize()
                            .padding(.horizontal, 14)
                            .frame(minHeight: 44)
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .background(Theme.surface, in: Capsule())
                        .overlay(Capsule().stroke(Theme.hairline))
                    }
                }

                if let website {
                    Button {
                        openURL(website)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "safari.fill")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Website")
                                .font(Theme.sans(13, weight: .medium))
                        }
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .background(Theme.surface, in: Capsule())
                    .overlay(Capsule().stroke(Theme.hairline))
                }

                ShareLink(item: shareText.isEmpty ? (name ?? "Place") : shareText) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Share")
                            .font(Theme.sans(13, weight: .medium))
                    }
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .background(Theme.surface, in: Capsule())
                .overlay(Capsule().stroke(Theme.hairline))
            }
            .padding(.vertical, 2)
        }
    }
}

/// Hours row with green "Open" / red "Closed" indicator
struct PlacesHoursView: View {
    let hours: String

    var body: some View {
        let trimmed = hours.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if lower.hasPrefix("open") {
                Circle()
                    .fill(Theme.success)
                    .frame(width: 8, height: 8)
                Text(trimmed)
                    .font(Theme.sans(13, weight: .medium))
                    .foregroundStyle(Theme.text)
            } else if lower.hasPrefix("closed") {
                Circle()
                    .fill(Theme.danger)
                    .frame(width: 8, height: 8)
                Text(trimmed)
                    .font(Theme.sans(13, weight: .medium))
                    .foregroundStyle(Theme.text)
            } else {
                Image(systemName: "clock")
                    .font(Theme.sans(12))
                    .foregroundStyle(Theme.secondaryText)
                Text(trimmed)
                    .font(Theme.sans(13))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
}

/// Star rating + review count display
struct PlacesRatingView: View {
    let rating: Double?
    let reviews: Int?
    var maxStars: Int = 5

    var body: some View {
        if let rating = cardSafeDouble(rating) {
            HStack(spacing: 4) {
                Image(systemName: "star.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(cardStarColor)
                    .accessibilityHidden(true)

                Text(rating.formatted(.number.precision(.fractionLength(1))))
                    .monospacedDigit()
                    .font(Theme.sans(13, weight: .semibold))
                    .foregroundStyle(Theme.text)

                if let reviews, reviews > 0 {
                    let formatted = formatReviews(reviews)
                    Text("(\(formatted))")
                        .font(Theme.sans(12))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func formatReviews(_ count: Int) -> String {
        cardFormatNumber(Double(count))
    }
}

/// Only http(s) URLs are loaded or opened from model-supplied strings.
func placesWebURL(_ raw: String?) -> URL? {
    guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
          let url = URL(string: raw), let scheme = url.scheme?.lowercased(),
          scheme == "http" || scheme == "https", url.host != nil else { return nil }
    return url
}
