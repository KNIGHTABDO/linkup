import SwiftUI
import MapKit
import CoreLocation
import Foundation

// MARK: - Date Helpers

enum PlacesDateParser {
    private static let isoWithFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoStandard: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let isoDateOnly: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f
    }()

    private static let fallbackFormatters: [DateFormatter] = {
        let patterns = [
            "yyyy-MM-dd'T'HH:mm:ssZZZZZ",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd HH:mm",
            "yyyy-MM-dd",
            "MMM d, yyyy",
            "MMMM d, yyyy"
        ]
        return patterns.map { pattern in
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.dateFormat = pattern
            return df
        }
    }()

    static func parse(_ raw: String?) -> Date? {
        guard let s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        if let d = isoWithFractional.date(from: s) { return d }
        if let d = isoStandard.date(from: s) { return d }
        if let d = isoDateOnly.date(from: s) { return d }
        for f in fallbackFormatters {
            if let d = f.date(from: s) { return d }
        }
        return nil
    }

    static func monthAbbreviation(from date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "MMM"
        return df.string(from: date).uppercased()
    }

    static func dayNumber(from date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "d"
        return df.string(from: date)
    }

    static func formatTimeRange(start: Date?, end: Date?) -> String {
        let timeFormatter = DateFormatter()
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short

        guard let start else {
            return end.map { "Until " + timeFormatter.string(from: $0) } ?? "Date TBD"
        }

        guard let end else {
            return dateFormatter.string(from: start)
        }

        let cal = Calendar.current
        if cal.isDate(start, inSameDayAs: end) {
            return "\(timeFormatter.string(from: start)) – \(timeFormatter.string(from: end))"
        } else {
            return "\(dateFormatter.string(from: start)) – \(dateFormatter.string(from: end))"
        }
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

        let safeTitle = title.components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
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
            .replacingOccurrences(of: "\n", with: "\\n")
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
}

struct PlacesWeatherHourly: Codable, Sendable {
    let time: [String]?
    let temperature_2m: [Double]?
    let weather_code: [Int]?
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

    var gradientColors: [Color] {
        switch self {
        case .clearSky(let isDay):
            return isDay
                ? [Color(red: 0.12, green: 0.35, blue: 0.65), Color(red: 0.24, green: 0.48, blue: 0.78)]
                : [Color(red: 0.08, green: 0.10, blue: 0.22), Color(red: 0.14, green: 0.18, blue: 0.32)]
        case .partlyCloudy(let isDay):
            return isDay
                ? [Color(red: 0.16, green: 0.30, blue: 0.50), Color(red: 0.26, green: 0.40, blue: 0.60)]
                : [Color(red: 0.10, green: 0.14, blue: 0.25), Color(red: 0.18, green: 0.22, blue: 0.35)]
        case .overcast:
            return [Color(red: 0.18, green: 0.22, blue: 0.28), Color(red: 0.26, green: 0.30, blue: 0.36)]
        case .fog:
            return [Color(red: 0.20, green: 0.22, blue: 0.27), Color(red: 0.28, green: 0.30, blue: 0.35)]
        case .drizzle, .rain:
            return [Color(red: 0.12, green: 0.22, blue: 0.35), Color(red: 0.18, green: 0.32, blue: 0.48)]
        case .snow:
            return [Color(red: 0.15, green: 0.25, blue: 0.40), Color(red: 0.28, green: 0.38, blue: 0.55)]
        case .thunderstorm:
            return [Color(red: 0.16, green: 0.12, blue: 0.26), Color(red: 0.24, green: 0.18, blue: 0.36)]
        }
    }
}

@MainActor
final class PlacesWeatherService {
    static let shared = PlacesWeatherService()
    private var forecastCache: [String: PlacesWeatherResponse] = [:]
    private var geocodeCache: [String: (lat: Double, lon: Double, name: String)] = [:]

    func fetchWeather(lat: Double, lon: Double) async throws -> PlacesWeatherResponse {
        let key = String(format: "%.3f,%.3f", lat, lon)
        if let cached = forecastCache[key] {
            return cached
        }

        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&current=temperature_2m,weather_code,wind_speed_10m,relative_humidity_2m&hourly=temperature_2m,weather_code&daily=weather_code,temperature_2m_max,temperature_2m_min&timezone=auto&forecast_days=7"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        let decoded = try JSONDecoder().decode(PlacesWeatherResponse.self, from: data)
        forecastCache[key] = decoded
        return decoded
    }

    func geocode(location: String) async throws -> (lat: Double, lon: Double, name: String)? {
        let trimmed = location.trimmingCharacters(in: .whitespacesAndNewlines)
        if let cached = geocodeCache[trimmed] {
            return cached
        }

        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://geocoding-api.open-meteo.com/v1/search?name=\(encoded)&count=1") else {
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
    private var rateCache: [String: [String: Double]] = [:]

    func fetchRate(from: String, to: String) async throws -> Double? {
        let base = from.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let target = to.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)

        if let cachedRates = rateCache[base], let rate = cachedRates[target] {
            return rate
        }

        guard let url = URL(string: "https://open.er-api.com/v6/latest/\(base)") else {
            return nil
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        let resp = try JSONDecoder().decode(PlacesCurrencyResponse.self, from: data)
        if let rates = resp.rates {
            rateCache[base] = rates
            return rates[target]
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
        if !photos.isEmpty {
            TabView {
                ForEach(photos, id: \.self) { photoURL in
                    AsyncImage(url: URL(string: photoURL)) { phase in
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
    @State private var position: MapCameraPosition = .automatic

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
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Theme.surface.opacity(0.85), in: Capsule())
                            .padding(10)
                        }
                    )
            } else if let coord = coordinate, CLLocationCoordinate2DIsValid(coord) {
                Map(position: $position, interactionModes: []) {
                    Marker(name ?? "Place", coordinate: coord)
                        .tint(Theme.accent)
                }
                .onAppear {
                    position = .region(MKCoordinateRegion(center: coord, latitudinalMeters: 800, longitudinalMeters: 800))
                }
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
        .task(id: coordinate?.latitude) {
            guard let coord = coordinate, CLLocationCoordinate2DIsValid(coord) else { return }
            snapshotImage = await PlacesMapSnapshotterService.shared.snapshot(for: coord)
        }
    }
}

/// Small embedded non-interactive MapKit SwiftUI map (height 160)
struct PlacesMiniMapView: View {
    let coordinate: CLLocationCoordinate2D?
    let name: String?

    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        Group {
            if let coord = coordinate, CLLocationCoordinate2DIsValid(coord) {
                Map(position: $position, interactionModes: []) {
                    Marker(name ?? "Location", coordinate: coord)
                        .tint(Theme.accent)
                }
                .frame(height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Theme.hairline)
                )
                .overlay(alignment: .bottomTrailing) {
                    Button {
                        PlacesOpenMapsHelper.open(coordinate: coord, name: name)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.right")
                                .font(Theme.sans(11, weight: .bold))
                            Text("Open")
                                .font(Theme.sans(11, weight: .semibold))
                        }
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                    }
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .padding(8)
                }
                .onAppear {
                    position = .region(MKCoordinateRegion(center: coord, latitudinalMeters: 700, longitudinalMeters: 700))
                }
                .onChange(of: coordinate?.latitude) { _, _ in
                    position = .region(MKCoordinateRegion(center: coord, latitudinalMeters: 700, longitudinalMeters: 700))
                }
            }
        }
    }
}

/// Action buttons row in glass capsules (Directions, Call, Website, Share)
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
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                    }
                    .glassEffect(.regular.interactive(), in: .capsule)
                }

                if let phone, !phone.isEmpty {
                    let cleaned = phone.filter { $0.isNumber || $0 == "+" }
                    if let telURL = URL(string: "tel:\(cleaned)") {
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
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                        }
                        .glassEffect(.regular.interactive(), in: .capsule)
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
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                    }
                    .glassEffect(.regular.interactive(), in: .capsule)
                }

                ShareLink(item: shareText.isEmpty ? (name ?? "Place") : shareText) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Share")
                            .font(Theme.sans(13, weight: .medium))
                    }
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
                .glassEffect(.regular.interactive(), in: .capsule)
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

        HStack(spacing: 6) {
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
    }
}

/// Star rating + review count display
struct PlacesRatingView: View {
    let rating: Double?
    let reviews: Int?
    var maxStars: Int = 5

    var body: some View {
        if let rating {
            HStack(spacing: 4) {
                Image(systemName: "star.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(red: 1.0, green: 0.8, blue: 0.2))

                Text(String(format: "%.1f", rating))
                    .font(Theme.sans(13, weight: .semibold))
                    .foregroundStyle(Theme.text)

                if let reviews, reviews > 0 {
                    let formatted = formatReviews(reviews)
                    Text("(\(formatted))")
                        .font(Theme.sans(12))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
        }
    }

    private func formatReviews(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000.0)
        } else if count >= 1_000 {
            return String(format: "%.1fk", Double(count) / 1_000.0)
        } else {
            return "\(count)"
        }
    }
}
