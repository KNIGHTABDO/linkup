import SwiftUI
import MapKit
import CoreLocation
import Foundation

// MARK: - 1. PlaceCard

/// Detail card for a single place (restaurant, café, landmark, museum...)
struct PlaceCard: View {
    let card: JSONValue

    @State private var resolvedCoordinate: CLLocationCoordinate2D?

    private var name: String? { card["name"]?.string }
    private var category: String? { card["category"]?.string }
    private var address: String? { card["address"]?.string }
    private var rating: Double? { card["rating"]?.double }
    private var reviews: Int? { card["reviews"]?.int }
    private var price: String? { card["price"]?.string }
    private var photos: [String] { card.strings("photos") }
    private var website: URL? { card.url("website") }
    private var phone: String? { card["phone"]?.string }
    private var hours: String? { card["hours"]?.string }
    private var summary: String? { card["summary"]?.string }

    var body: some View {
        CardContainer(title: category ?? "Place", symbol: "mappin.circle.fill") {
            VStack(alignment: .leading, spacing: 14) {
                // Hero Photo Carousel (or MapKit snapshot if no photos)
                PlacesHeroCarousel(photos: photos, coordinate: resolvedCoordinate, name: name)

                // Name
                if let name {
                    Text(name)
                        .font(Theme.sans(19, weight: .semibold))
                        .foregroundStyle(Theme.text)
                }

                // Category • Price • Rating
                let metaRow = buildMetaLine()
                if !metaRow.isEmpty || rating != nil {
                    HStack(spacing: 8) {
                        if !metaRow.isEmpty {
                            Text(metaRow)
                                .font(Theme.sans(13, weight: .medium))
                                .foregroundStyle(Theme.secondaryText)
                        }
                        PlacesRatingView(rating: rating, reviews: reviews)
                    }
                }

                // Address
                if let address {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "mappin")
                            .font(Theme.sans(12))
                            .foregroundStyle(Theme.secondaryText)
                        Text(address)
                            .font(Theme.sans(13))
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(2)
                    }
                }

                // Hours
                if let hours {
                    PlacesHoursView(hours: hours)
                }

                // Summary
                if let summary {
                    Text(summary)
                        .font(Theme.serif(14))
                        .foregroundStyle(Theme.text.opacity(0.9))
                        .lineSpacing(3)
                }

                // Embedded small non-interactive Map
                PlacesMiniMapView(coordinate: resolvedCoordinate, name: name)

                // Action buttons row (Directions, Call, Website, Share)
                PlacesActionButtonsRow(
                    coordinate: resolvedCoordinate,
                    name: name,
                    phone: phone,
                    website: website
                )
            }
        }
        .task {
            await resolveCoordinates()
        }
    }

    private func buildMetaLine() -> String {
        var parts: [String] = []
        if let category { parts.append(category) }
        if let price { parts.append(price) }
        return parts.joined(separator: " • ")
    }

    private func resolveCoordinates() async {
        if let lat = card["lat"]?.double, let lon = card["lon"]?.double,
           CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(latitude: lat, longitude: lon)) {
            resolvedCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            return
        }

        if let query = address ?? name {
            resolvedCoordinate = await PlacesGeocodingService.shared.geocode(query: query)
        }
    }
}

// MARK: - 2. PlacesCard

private struct PlacesItemWrapper: Identifiable {
    let id = UUID()
    let json: JSONValue
}

/// List of places with compact rows; tap expands to full PlaceCard in a sheet
struct PlacesCard: View {
    let card: JSONValue

    @State private var selectedPlace: PlacesItemWrapper?

    private var title: String? { card["title"]?.string }
    private var items: [JSONValue] { card.objects("items") }

    var body: some View {
        CardContainer(title: title ?? "Places", symbol: "square.grid.2x2") {
            VStack(spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    let name = item["name"]?.string ?? "Place"
                    let photos = item.strings("photos")
                    let rating = item["rating"]?.double
                    let reviews = item["reviews"]?.int
                    let category = item["category"]?.string
                    let price = item["price"]?.string
                    let address = item["address"]?.string

                    Button {
                        selectedPlace = PlacesItemWrapper(json: item)
                    } label: {
                        HStack(spacing: 12) {
                            // Thumbnail 64x64
                            Group {
                                if let firstPhoto = photos.first, let url = URL(string: firstPhoto) {
                                    AsyncImage(url: url) { phase in
                                        switch phase {
                                        case .empty:
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .fill(Theme.elevated)
                                                .overlay(ProgressView().tint(Theme.secondaryText))
                                        case .success(let image):
                                            image
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                        case .failure:
                                            thumbnailFallback(category: category)
                                        @unknown default:
                                            thumbnailFallback(category: category)
                                        }
                                    }
                                } else {
                                    thumbnailFallback(category: category)
                                }
                            }
                            .frame(width: 64, height: 64)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                            // Details
                            VStack(alignment: .leading, spacing: 3) {
                                Text(name)
                                    .font(Theme.sans(15, weight: .semibold))
                                    .foregroundStyle(Theme.text)
                                    .lineLimit(1)

                                HStack(spacing: 6) {
                                    PlacesRatingView(rating: rating, reviews: reviews)
                                    if let category {
                                        Text(category)
                                            .font(Theme.sans(12))
                                            .foregroundStyle(Theme.secondaryText)
                                            .lineLimit(1)
                                    }
                                    if let price {
                                        Text("• " + price)
                                            .font(Theme.sans(12))
                                            .foregroundStyle(Theme.secondaryText)
                                    }
                                }

                                if let address {
                                    Text(address)
                                        .font(Theme.sans(12))
                                        .foregroundStyle(Theme.tertiaryText)
                                        .lineLimit(1)
                                }
                            }

                            Spacer(minLength: 4)

                            Image(systemName: "chevron.right")
                                .font(Theme.sans(12, weight: .semibold))
                                .foregroundStyle(Theme.tertiaryText)
                        }
                        .padding(8)
                        .background(Theme.elevated.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)

                    if index < items.count - 1 {
                        Divider()
                            .overlay(Theme.hairline)
                    }
                }
            }
        }
        .sheet(item: $selectedPlace) { wrapper in
            PlacesDetailSheetView(card: wrapper.json)
        }
    }

    private func thumbnailFallback(category: String?) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Theme.elevated)
            .overlay(
                Image(systemName: iconForCategory(category))
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.secondaryText)
            )
    }

    private func iconForCategory(_ category: String?) -> String {
        guard let cat = category?.lowercased() else { return "mappin.circle.fill" }
        if cat.contains("caf") || cat.contains("coffee") { return "cup.and.saucer.fill" }
        if cat.contains("restaurant") || cat.contains("food") { return "fork.knife" }
        if cat.contains("hotel") || cat.contains("lodging") { return "bed.double.fill" }
        if cat.contains("museum") || cat.contains("gallery") { return "building.columns.fill" }
        if cat.contains("bar") || cat.contains("pub") { return "wineglass.fill" }
        if cat.contains("park") { return "tree.fill" }
        return "mappin.circle.fill"
    }
}

/// Sheet presentation view matching Claude app style
private struct PlacesDetailSheetView: View {
    let card: JSONValue

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Sheet header: glass xmark close + centered title
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(Theme.sans(13, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .frame(width: 32, height: 32)
                }
                .glassEffect(.regular.interactive(), in: .circle)

                Spacer()

                Text(card["name"]?.string ?? "Place Details")
                    .font(Theme.sans(16, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)

                Spacer()

                Color.clear
                    .frame(width: 32, height: 32)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)

            Divider()
                .overlay(Theme.hairline)

            ScrollView {
                PlaceCard(card: card)
                    .padding(Theme.margin)
            }
        }
        .background(Theme.surface)
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.surface)
    }
}

// MARK: - 3. MapCard

private struct PlacesMapPin: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let coordinate: CLLocationCoordinate2D
    let note: String?

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: PlacesMapPin, rhs: PlacesMapPin) -> Bool {
        lhs.id == rhs.id
    }
}

/// Interactive Map (height 260) with pin callouts and "Open in Maps"
struct MapCard: View {
    let card: JSONValue

    @State private var resolvedPins: [PlacesMapPin] = []
    @State private var selectedPinId: UUID?
    @State private var cameraPosition: MapCameraPosition = .automatic

    private var title: String? { card["title"]?.string }
    private var regionName: String? { card["region"]?.string }
    private var rawPins: [JSONValue] { card.objects("pins") }

    var body: some View {
        CardContainer(title: title ?? "Map", symbol: "map.fill") {
            VStack(alignment: .leading, spacing: 12) {
                // Interactive Map
                Map(position: $cameraPosition, selection: $selectedPinId) {
                    ForEach(resolvedPins) { pin in
                        Marker(pin.name, coordinate: pin.coordinate)
                            .tint(Theme.accent)
                            .tag(pin.id)
                    }
                }
                .frame(height: 260)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Theme.hairline)
                )

                // Callout when pin selected, or global action
                if let selected = resolvedPins.first(where: { $0.id == selectedPinId }) {
                    HStack(alignment: .center, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(selected.name)
                                .font(Theme.sans(15, weight: .semibold))
                                .foregroundStyle(Theme.text)
                            if let note = selected.note {
                                Text(note)
                                    .font(Theme.sans(13))
                                    .foregroundStyle(Theme.secondaryText)
                            }
                        }

                        Spacer()

                        Button {
                            PlacesOpenMapsHelper.open(coordinate: selected.coordinate, name: selected.name)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.up.right")
                                    .font(Theme.sans(11, weight: .bold))
                                Text("Open")
                                    .font(Theme.sans(12, weight: .semibold))
                            }
                            .foregroundStyle(Theme.text)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                        }
                        .glassEffect(.regular.interactive(), in: .capsule)
                    }
                    .padding(12)
                    .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 12))
                } else {
                    HStack {
                        if !resolvedPins.isEmpty {
                            Text("\(resolvedPins.count) location\(resolvedPins.count == 1 ? "" : "s")")
                                .font(Theme.sans(13))
                                .foregroundStyle(Theme.secondaryText)
                        } else if let regionName {
                            Text(regionName)
                                .font(Theme.sans(13))
                                .foregroundStyle(Theme.secondaryText)
                        }

                        Spacer()

                        Button {
                            openAllInMaps()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "map")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("Open in Maps")
                                    .font(Theme.sans(13, weight: .medium))
                            }
                            .foregroundStyle(Theme.text)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                        }
                        .glassEffect(.regular.interactive(), in: .capsule)
                    }
                }
            }
        }
        .task {
            await resolvePins()
        }
    }

    private func resolvePins() async {
        var result: [PlacesMapPin] = []

        for p in rawPins {
            let name = p["name"]?.string ?? p["query"]?.string ?? "Pin"
            let note = p["note"]?.string

            if let lat = p["lat"]?.double, let lon = p["lon"]?.double,
               CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(latitude: lat, longitude: lon)) {
                result.append(PlacesMapPin(
                    name: name,
                    coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                    note: note
                ))
            } else if let query = p["query"]?.string ?? p["name"]?.string {
                if let coord = await PlacesGeocodingService.shared.geocode(query: query) {
                    result.append(PlacesMapPin(
                        name: name,
                        coordinate: coord,
                        note: note
                    ))
                }
            }
        }

        resolvedPins = result

        if result.isEmpty, let reg = regionName {
            if let regionCoord = await PlacesGeocodingService.shared.geocode(query: reg) {
                cameraPosition = .region(MKCoordinateRegion(center: regionCoord, latitudinalMeters: 8000, longitudinalMeters: 8000))
            }
        }
    }

    private func openAllInMaps() {
        if let first = resolvedPins.first {
            let items = resolvedPins.map { pin -> MKMapItem in
                let item = MKMapItem(placemark: MKPlacemark(coordinate: pin.coordinate))
                item.name = pin.name
                return item
            }
            MKMapItem.openMaps(with: items, launchOptions: nil)
        } else if let reg = regionName, let encoded = reg.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let url = URL(string: "http://maps.apple.com/?q=\(encoded)") {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - 4. RouteCard

/// Map route with from/to markers, polyline via MKDirections, duration/distance chips, collapsible steps
struct RouteCard: View {
    let card: JSONValue

    @State private var fromCoord: CLLocationCoordinate2D?
    @State private var toCoord: CLLocationCoordinate2D?
    @State private var polylineCoordinates: [CLLocationCoordinate2D] = []
    @State private var calculatedDuration: String?
    @State private var calculatedDistance: String?
    @State private var calculatedSteps: [String] = []
    @State private var isStepsExpanded = false
    @State private var cameraPosition: MapCameraPosition = .automatic

    private var fromName: String? { card["from"]?.string }
    private var toName: String? { card["to"]?.string }
    private var mode: String? { card["mode"]?.string }
    private var duration: String? { card["duration"]?.string ?? calculatedDuration }
    private var distance: String? { card["distance"]?.string ?? calculatedDistance }
    private var steps: [String] {
        let cardSteps = card.strings("steps")
        return cardSteps.isEmpty ? calculatedSteps : cardSteps
    }

    var body: some View {
        CardContainer(title: "Route", symbol: "arrow.triangle.swap") {
            VStack(alignment: .leading, spacing: 14) {
                // Route endpoints header
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Theme.success)
                            .frame(width: 10, height: 10)
                        Text(fromName ?? "Start")
                            .font(Theme.sans(14, weight: .medium))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                    }

                    HStack(spacing: 8) {
                        Circle()
                            .fill(Theme.accent)
                            .frame(width: 10, height: 10)
                        Text(toName ?? "Destination")
                            .font(Theme.sans(14, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                    }
                }

                // Map with route polyline
                Map(position: $cameraPosition, interactionModes: []) {
                    if let fromCoord {
                        Marker(fromName ?? "Start", coordinate: fromCoord)
                            .tint(Theme.success)
                    }
                    if let toCoord {
                        Marker(toName ?? "End", coordinate: toCoord)
                            .tint(Theme.accent)
                    }
                    if !polylineCoordinates.isEmpty {
                        MapPolyline(coordinates: polylineCoordinates)
                            .stroke(Theme.accent, lineWidth: 4)
                    }
                }
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Theme.hairline)
                )

                // Mode, duration, distance chips
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: modeIcon(mode))
                            .font(Theme.sans(12))
                        Text(modeTitle(mode))
                            .font(Theme.sans(12, weight: .medium))
                    }
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Theme.elevated, in: Capsule())

                    if let duration {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(Theme.sans(12))
                            Text(duration)
                                .font(Theme.sans(12, weight: .semibold))
                        }
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Theme.elevated, in: Capsule())
                    }

                    if let distance {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.left.and.right")
                                .font(Theme.sans(12))
                            Text(distance)
                                .font(Theme.sans(12, weight: .semibold))
                        }
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Theme.elevated, in: Capsule())
                    }
                }

                // Collapsible steps
                if !steps.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            withAnimation(.snappy) {
                                isStepsExpanded.toggle()
                            }
                        } label: {
                            HStack {
                                Text("\(steps.count) step\(steps.count == 1 ? "" : "s")")
                                    .font(Theme.sans(13, weight: .semibold))
                                    .foregroundStyle(Theme.text)
                                Spacer()
                                Image(systemName: isStepsExpanded ? "chevron.up" : "chevron.down")
                                    .font(Theme.sans(12, weight: .semibold))
                                    .foregroundStyle(Theme.secondaryText)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)

                        if isStepsExpanded {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(Array(steps.enumerated()), id: \.offset) { idx, step in
                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        Text("\(idx + 1).")
                                            .font(Theme.sans(12, weight: .bold))
                                            .foregroundStyle(Theme.secondaryText)
                                            .frame(width: 20, alignment: .trailing)
                                        Text(step)
                                            .font(Theme.sans(13))
                                            .foregroundStyle(Theme.text)
                                    }
                                }
                            }
                            .padding(10)
                            .background(Theme.elevated.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }

                // Bottom button: launch navigation in Apple Maps
                if let to = toCoord {
                    Button {
                        PlacesOpenMapsHelper.openRoute(
                            from: fromCoord,
                            fromName: fromName,
                            to: to,
                            toName: toName,
                            mode: mode
                        )
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Open in Maps")
                                .font(Theme.sans(13, weight: .semibold))
                        }
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                    }
                    .glassEffect(.regular.interactive(), in: .capsule)
                }
            }
        }
        .task {
            await calculateRoute()
        }
    }

    private func modeIcon(_ m: String?) -> String {
        switch m?.lowercased() {
        case "walking": return "figure.walk"
        case "transit": return "tram.fill"
        case "cycling": return "bicycle"
        default: return "car.fill"
        }
    }

    private func modeTitle(_ m: String?) -> String {
        switch m?.lowercased() {
        case "walking": return "Walking"
        case "transit": return "Transit"
        case "cycling": return "Cycling"
        default: return "Driving"
        }
    }

    private func calculateRoute() async {
        guard let fromStr = fromName, let toStr = toName else { return }

        async let fCoord = PlacesGeocodingService.shared.geocode(query: fromStr)
        async let tCoord = PlacesGeocodingService.shared.geocode(query: toStr)

        fromCoord = await fCoord
        toCoord = await tCoord

        guard let src = fromCoord, let dst = toCoord else { return }

        // Directions calculation
        let req = MKDirections.Request()
        req.source = MKMapItem(placemark: MKPlacemark(coordinate: src))
        req.destination = MKMapItem(placemark: MKPlacemark(coordinate: dst))

        switch mode?.lowercased() {
        case "walking": req.transportType = .walking
        case "transit": req.transportType = .transit
        default: req.transportType = .automobile
        }

        let directions = MKDirections(request: req)
        do {
            let resp = try await directions.calculate()
            if let route = resp.routes.first {
                var coords = [CLLocationCoordinate2D](repeating: CLLocationCoordinate2D(), count: route.polyline.pointCount)
                route.polyline.getCoordinates(&coords, range: NSRange(location: 0, length: route.polyline.pointCount))
                polylineCoordinates = coords

                let mins = Int(round(route.expectedTravelTime / 60))
                calculatedDuration = mins >= 60 ? "\(mins / 60)h \(mins % 60)m" : "\(mins) min"
                calculatedDistance = String(format: "%.1f km", route.distance / 1000.0)
                calculatedSteps = route.steps.map(\.instructions).filter { !$0.isEmpty }
            }
        } catch {
            // Transit or remote route fallback: draw straight line
            polylineCoordinates = [src, dst]
        }
    }
}

// MARK: - 5. WeatherCard

/// Live weather from Open-Meteo with condition gradient, hourly strip, and 7-day forecast
struct WeatherCard: View {
    let card: JSONValue

    @State private var weatherData: PlacesWeatherResponse?
    @State private var resolvedLocationName: String?
    @State private var isLoading = true

    private var locationName: String? { card["location"]?.string }
    private var summary: String? { card["summary"]?.string }

    var body: some View {
        let code = weatherData?.current?.weather_code ?? 0
        let condition = PlacesWeatherCondition.from(code: code, isDay: true)

        VStack(alignment: .leading, spacing: 14) {
            // Header: Location name + condition description
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(resolvedLocationName ?? locationName ?? "Weather")
                        .font(Theme.sans(19, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text(summary ?? condition.description)
                        .font(Theme.sans(13))
                        .foregroundStyle(Theme.text.opacity(0.85))
                }

                Spacer()

                Image(systemName: condition.symbol)
                    .font(.system(size: 38))
                    .symbolRenderingMode(.multicolor)
            }

            // Big temperature + High/Low
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                if let temp = weatherData?.current?.temperature_2m {
                    Text("\(Int(round(temp)))°")
                        .font(Theme.sans(48, weight: .light))
                        .foregroundStyle(Theme.text)
                }

                if let daily = weatherData?.daily,
                   let max = daily.temperature_2m_max?.first,
                   let min = daily.temperature_2m_min?.first {
                    Text("H: \(Int(round(max)))°  L: \(Int(round(min)))°")
                        .font(Theme.sans(14, weight: .medium))
                        .foregroundStyle(Theme.text.opacity(0.85))
                }
            }

            // Current stats chips (Wind, Humidity)
            HStack(spacing: 8) {
                if let wind = weatherData?.current?.wind_speed_10m {
                    HStack(spacing: 4) {
                        Image(systemName: "wind")
                        Text(String(format: "%.1f km/h", wind))
                    }
                    .font(Theme.sans(12))
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.12), in: Capsule())
                }

                if let humidity = weatherData?.current?.relative_humidity_2m {
                    HStack(spacing: 4) {
                        Image(systemName: "humidity.fill")
                        Text("\(Int(humidity))%")
                    }
                    .font(Theme.sans(12))
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.12), in: Capsule())
                }
            }

            // Hourly strip (next 12 hours)
            if let hourly = weatherData?.hourly, let times = hourly.time, let temps = hourly.temperature_2m, let codes = hourly.weather_code {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Hourly Forecast")
                        .font(Theme.sans(11, weight: .semibold))
                        .foregroundStyle(Theme.text.opacity(0.75))
                        .textCase(.uppercase)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            let count = min(12, min(times.count, min(temps.count, codes.count)))
                            ForEach(0..<count, id: \.self) { i in
                                let tStr = times[i]
                                let hourText = formatHour(tStr, isFirst: i == 0)
                                let hCond = PlacesWeatherCondition.from(code: codes[i], isDay: true)

                                VStack(spacing: 6) {
                                    Text(hourText)
                                        .font(Theme.sans(12))
                                        .foregroundStyle(Theme.text.opacity(0.85))

                                    Image(systemName: hCond.symbol)
                                        .font(.system(size: 18))
                                        .symbolRenderingMode(.multicolor)

                                    Text("\(Int(round(temps[i])))°")
                                        .font(Theme.sans(13, weight: .semibold))
                                        .foregroundStyle(Theme.text)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                    }
                    .background(Color.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
                }
            }

            // 7-Day Forecast Rows
            if let daily = weatherData?.daily,
               let times = daily.time,
               let codes = daily.weather_code,
               let maxs = daily.temperature_2m_max,
               let mins = daily.temperature_2m_min {

                let weekMin = mins.min() ?? 0
                let weekMax = maxs.max() ?? 40

                VStack(alignment: .leading, spacing: 8) {
                    Text("7-Day Forecast")
                        .font(Theme.sans(11, weight: .semibold))
                        .foregroundStyle(Theme.text.opacity(0.75))
                        .textCase(.uppercase)

                    VStack(spacing: 8) {
                        let count = min(7, min(times.count, min(codes.count, min(maxs.count, mins.count))))
                        ForEach(0..<count, id: \.self) { i in
                            let dayName = formatDayName(times[i], isFirst: i == 0)
                            let dCond = PlacesWeatherCondition.from(code: codes[i], isDay: true)
                            let dMin = mins[i]
                            let dMax = maxs[i]

                            HStack(spacing: 10) {
                                Text(dayName)
                                    .font(Theme.sans(13, weight: .medium))
                                    .foregroundStyle(Theme.text)
                                    .frame(width: 48, alignment: .leading)

                                Image(systemName: dCond.symbol)
                                    .font(.system(size: 16))
                                    .symbolRenderingMode(.multicolor)
                                    .frame(width: 24)

                                Text("\(Int(round(dMin)))°")
                                    .font(Theme.sans(13))
                                    .foregroundStyle(Theme.text.opacity(0.75))
                                    .frame(width: 28, alignment: .trailing)

                                // Min/Max Range Bar
                                GeometryReader { geo in
                                    let totalRange = max(1.0, weekMax - weekMin)
                                    let startFrac = max(0.0, (dMin - weekMin) / totalRange)
                                    let endFrac = min(1.0, (dMax - weekMin) / totalRange)
                                    let startX = geo.size.width * CGFloat(startFrac)
                                    let barWidth = max(6.0, geo.size.width * CGFloat(endFrac - startFrac))

                                    ZStack(alignment: .leading) {
                                        Capsule()
                                            .fill(Color.white.opacity(0.15))
                                            .frame(height: 4)

                                        Capsule()
                                            .fill(
                                                LinearGradient(
                                                    colors: [Color.cyan, Color.orange],
                                                    startPoint: .leading,
                                                    endPoint: .trailing
                                                )
                                            )
                                            .frame(width: barWidth, height: 4)
                                            .offset(x: startX)
                                    }
                                }
                                .frame(height: 4)

                                Text("\(Int(round(dMax)))°")
                                    .font(Theme.sans(13, weight: .semibold))
                                    .foregroundStyle(Theme.text)
                                    .frame(width: 28, alignment: .leading)
                            }
                        }
                    }
                    .padding(12)
                    .background(Color.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: condition.gradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Theme.hairline)
        )
        .task {
            await fetchWeather()
        }
    }

    private func fetchWeather() async {
        var lat = card["lat"]?.double
        var lon = card["lon"]?.double

        if lat == nil || lon == nil, let loc = locationName {
            if let geo = try? await PlacesWeatherService.shared.geocode(location: loc) {
                lat = geo.lat
                lon = geo.lon
                resolvedLocationName = geo.name
            }
        }

        guard let latitude = lat, let longitude = lon else {
            isLoading = false
            return
        }

        do {
            let data = try await PlacesWeatherService.shared.fetchWeather(lat: latitude, lon: longitude)
            weatherData = data
        } catch {
            // Handled gracefully with fallback summary
        }
        isLoading = false
    }

    private func formatHour(_ isoString: String, isFirst: Bool) -> String {
        if isFirst { return "Now" }
        let parts = isoString.components(separatedBy: "T")
        if parts.count > 1 {
            return parts[1]
        }
        return isoString
    }

    private func formatDayName(_ dateStr: String, isFirst: Bool) -> String {
        if isFirst { return "Today" }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        if let d = df.date(from: dateStr) {
            let outF = DateFormatter()
            outF.dateFormat = "EEE"
            return outF.string(from: d)
        }
        return dateStr
    }
}

// MARK: - 6. FlightCard

/// Boarding pass style flight detail card
struct FlightCard: View {
    let card: JSONValue

    private var airline: String? { card["airline"]?.string }
    private var number: String? { card["number"]?.string }
    private var status: String? { card["status"]?.string }
    private var terminal: String? { card["terminal"]?.string }
    private var gate: String? { card["gate"]?.string }
    private var duration: String? { card["duration"]?.string }

    private var fromCode: String { card["from"]?["code"]?.string ?? "DEP" }
    private var fromCity: String? { card["from"]?["city"]?.string }
    private var fromTime: String? { card["from"]?["time"]?.string }

    private var toCode: String { card["to"]?["code"]?.string ?? "ARR" }
    private var toCity: String? { card["to"]?["city"]?.string }
    private var toTime: String? { card["to"]?["time"]?.string }

    var body: some View {
        CardContainer(title: "Flight", symbol: "airplane.departure") {
            VStack(spacing: 16) {
                // Top Header: Airline + Flight # and Status Badge
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "airplane")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.accent)
                        Text(flightHeader)
                            .font(Theme.sans(15, weight: .semibold))
                            .foregroundStyle(Theme.text)
                    }

                    Spacer()

                    if let status {
                        Text(status)
                            .font(Theme.sans(11, weight: .bold))
                            .foregroundStyle(statusColor(status))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(statusColor(status).opacity(0.16), in: Capsule())
                            .overlay(Capsule().stroke(statusColor(status).opacity(0.35)))
                    }
                }

                // Main Flight Route Block
                HStack(alignment: .center) {
                    // Origin
                    VStack(alignment: .leading, spacing: 2) {
                        Text(fromCode)
                            .font(Theme.sans(28, weight: .bold))
                            .foregroundStyle(Theme.text)
                        if let fromCity {
                            Text(fromCity)
                                .font(Theme.sans(12))
                                .foregroundStyle(Theme.secondaryText)
                                .lineLimit(1)
                        }
                        if let fromTime {
                            Text(fromTime)
                                .font(Theme.sans(15, weight: .semibold))
                                .foregroundStyle(Theme.text)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Plane Path + Duration
                    VStack(spacing: 4) {
                        if let duration {
                            Text(duration)
                                .font(Theme.sans(11, weight: .medium))
                                .foregroundStyle(Theme.secondaryText)
                        }

                        HStack(spacing: 2) {
                            Circle()
                                .fill(Theme.secondaryText)
                                .frame(width: 4, height: 4)

                            Rectangle()
                                .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                                .foregroundStyle(Theme.secondaryText)
                                .frame(height: 1)

                            Image(systemName: "airplane")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.accent)

                            Rectangle()
                                .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                                .foregroundStyle(Theme.secondaryText)
                                .frame(height: 1)

                            Circle()
                                .fill(Theme.secondaryText)
                                .frame(width: 4, height: 4)
                        }
                        .frame(width: 100)
                    }

                    // Destination
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(toCode)
                            .font(Theme.sans(28, weight: .bold))
                            .foregroundStyle(Theme.text)
                        if let toCity {
                            Text(toCity)
                                .font(Theme.sans(12))
                                .foregroundStyle(Theme.secondaryText)
                                .lineLimit(1)
                        }
                        if let toTime {
                            Text(toTime)
                                .font(Theme.sans(15, weight: .semibold))
                                .foregroundStyle(Theme.text)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }

                // Perforated ticket tear line
                Rectangle()
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                    .foregroundStyle(Theme.hairline)
                    .frame(height: 1)

                // Bottom boarding pass metadata
                HStack(spacing: 16) {
                    if let terminal {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("TERMINAL")
                                .font(Theme.sans(10, weight: .semibold))
                                .foregroundStyle(Theme.tertiaryText)
                            Text(terminal)
                                .font(Theme.sans(14, weight: .semibold))
                                .foregroundStyle(Theme.text)
                        }
                    }

                    if let gate {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("GATE")
                                .font(Theme.sans(10, weight: .semibold))
                                .foregroundStyle(Theme.tertiaryText)
                            Text(gate)
                                .font(Theme.sans(14, weight: .semibold))
                                .foregroundStyle(Theme.text)
                        }
                    }

                    Spacer()

                    if let duration, terminal == nil && gate == nil {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("FLIGHT TIME")
                                .font(Theme.sans(10, weight: .semibold))
                                .foregroundStyle(Theme.tertiaryText)
                            Text(duration)
                                .font(Theme.sans(14, weight: .semibold))
                                .foregroundStyle(Theme.text)
                        }
                    }
                }
            }
        }
    }

    private var flightHeader: String {
        var parts: [String] = []
        if let airline { parts.append(airline) }
        if let number { parts.append(number) }
        return parts.isEmpty ? "Flight" : parts.joined(separator: " ")
    }

    private func statusColor(_ s: String) -> Color {
        let lower = s.lowercased()
        if lower.contains("on time") || lower.contains("landed") || lower.contains("scheduled") {
            return Theme.success
        } else if lower.contains("delay") || lower.contains("cancel") {
            return Theme.danger
        } else if lower.contains("board") || lower.contains("en route") {
            return Theme.accent
        } else {
            return Theme.secondaryText
        }
    }
}

// MARK: - 7. HotelCard

/// Detail card for a hotel with hero photos, stars, price, amenities tags, and embedded map
struct HotelCard: View {
    let card: JSONValue

    @State private var resolvedCoordinate: CLLocationCoordinate2D?

    private var name: String? { card["name"]?.string }
    private var address: String? { card["address"]?.string }
    private var stars: Int? { card["stars"]?.int }
    private var rating: Double? { card["rating"]?.double }
    private var price: String? { card["price"]?.string }
    private var photos: [String] { card.strings("photos") }
    private var amenities: [String] { card.strings("amenities") }
    private var website: URL? { card.url("website") }

    var body: some View {
        CardContainer(title: "Hotel", symbol: "bed.double.fill") {
            VStack(alignment: .leading, spacing: 14) {
                // Hero Photo Carousel
                PlacesHeroCarousel(photos: photos, coordinate: resolvedCoordinate, name: name)

                // Hotel Name
                if let name {
                    Text(name)
                        .font(Theme.sans(19, weight: .semibold))
                        .foregroundStyle(Theme.text)
                }

                // Stars • Rating • Price row
                HStack(spacing: 8) {
                    if let stars, stars > 0 {
                        HStack(spacing: 2) {
                            ForEach(0..<min(5, stars), id: \.self) { _ in
                                Image(systemName: "star.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.yellow)
                            }
                        }
                    }

                    PlacesRatingView(rating: rating, reviews: nil)

                    if let price {
                        Text("• " + price)
                            .font(Theme.sans(14, weight: .bold))
                            .foregroundStyle(Theme.accent)
                    }
                }

                // Address
                if let address {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "mappin")
                            .font(Theme.sans(12))
                            .foregroundStyle(Theme.secondaryText)
                        Text(address)
                            .font(Theme.sans(13))
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(2)
                    }
                }

                // Amenities Pills
                if !amenities.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(amenities, id: \.self) { am in
                                HStack(spacing: 4) {
                                    Image(systemName: amenityIcon(am))
                                        .font(.system(size: 11))
                                    Text(am)
                                        .font(Theme.sans(12, weight: .medium))
                                }
                                .foregroundStyle(Theme.text)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Theme.elevated, in: Capsule())
                            }
                        }
                    }
                }

                // Embedded Map
                PlacesMiniMapView(coordinate: resolvedCoordinate, name: name)

                // Action buttons row
                PlacesActionButtonsRow(
                    coordinate: resolvedCoordinate,
                    name: name,
                    phone: nil,
                    website: website
                )
            }
        }
        .task {
            await resolveCoordinates()
        }
    }

    private func amenityIcon(_ amenity: String) -> String {
        let lower = amenity.lowercased()
        if lower.contains("wifi") || lower.contains("internet") { return "wifi" }
        if lower.contains("pool") || lower.contains("swim") { return "figure.pool.swim" }
        if lower.contains("gym") || lower.contains("fitness") { return "dumbbell.fill" }
        if lower.contains("spa") || lower.contains("sauna") { return "sparkles" }
        if lower.contains("breakfast") || lower.contains("dining") || lower.contains("restaurant") { return "cup.and.saucer.fill" }
        if lower.contains("parking") { return "parkingsign.circle.fill" }
        if lower.contains("air") || lower.contains("ac") { return "air.conditioner.horizontal" }
        if lower.contains("pet") { return "pawprint.fill" }
        if lower.contains("bar") { return "wineglass.fill" }
        return "checkmark.circle"
    }

    private func resolveCoordinates() async {
        if let lat = card["lat"]?.double, let lon = card["lon"]?.double,
           CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(latitude: lat, longitude: lon)) {
            resolvedCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            return
        }

        if let query = address ?? name {
            resolvedCoordinate = await PlacesGeocodingService.shared.geocode(query: query)
        }
    }
}

// MARK: - 8. EventCard

/// Event card with date badge, time range, location, and .ics export via ShareLink
struct EventCard: View {
    let card: JSONValue

    @State private var icsFileURL: URL?

    private var title: String? { card["title"]?.string }
    private var location: String? { card["location"]?.string }
    private var description: String? { card["description"]?.string }
    private var url: URL? { card.url("url") }

    private var startDate: Date? { PlacesDateParser.parse(card["start"]?.string) }
    private var endDate: Date? { PlacesDateParser.parse(card["end"]?.string) }

    var body: some View {
        CardContainer(title: "Event", symbol: "calendar") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    // Date Badge (Month / Day)
                    VStack(spacing: 0) {
                        Text(monthString)
                            .font(Theme.sans(10, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 3)
                            .background(Theme.accent)

                        Text(dayString)
                            .font(Theme.sans(22, weight: .bold))
                            .foregroundStyle(Theme.text)
                            .frame(maxHeight: .infinity)
                    }
                    .frame(width: 54, height: 60)
                    .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 12))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    // Title & Time & Location
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title ?? "Event")
                            .font(Theme.sans(17, weight: .semibold))
                            .foregroundStyle(Theme.text)

                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(Theme.sans(12))
                            Text(PlacesDateParser.formatTimeRange(start: startDate, end: endDate))
                                .font(Theme.sans(13))
                        }
                        .foregroundStyle(Theme.secondaryText)

                        if let location {
                            HStack(spacing: 4) {
                                Image(systemName: "mappin.and.ellipse")
                                    .font(Theme.sans(12))
                                Text(location)
                                    .font(Theme.sans(13))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(Theme.secondaryText)
                        }
                    }
                }

                // Description
                if let description {
                    Text(description)
                        .font(Theme.sans(14))
                        .foregroundStyle(Theme.secondaryText)
                        .lineSpacing(3)
                }

                // Actions: Add to Calendar (ICS) + Website
                HStack(spacing: 10) {
                    if let icsFileURL {
                        ShareLink(item: icsFileURL, preview: SharePreview(title ?? "Event", image: Image(systemName: "calendar"))) {
                            HStack(spacing: 6) {
                                Image(systemName: "calendar.badge.plus")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("Add to Calendar")
                                    .font(Theme.sans(13, weight: .medium))
                            }
                            .foregroundStyle(Theme.text)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                        }
                        .glassEffect(.regular.interactive(), in: .capsule)
                    }

                    if let url {
                        Link(destination: url) {
                            HStack(spacing: 6) {
                                Image(systemName: "safari.fill")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("Event Page")
                                    .font(Theme.sans(13, weight: .medium))
                            }
                            .foregroundStyle(Theme.text)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                        }
                        .glassEffect(.regular.interactive(), in: .capsule)
                    }
                }
            }
        }
        .task {
            generateICS()
        }
    }

    private var monthString: String {
        if let s = startDate {
            return PlacesDateParser.monthAbbreviation(from: s)
        }
        return "EVENT"
    }

    private var dayString: String {
        if let s = startDate {
            return PlacesDateParser.dayNumber(from: s)
        }
        return "--"
    }

    private func generateICS() {
        icsFileURL = PlacesICSGenerator.createEventICS(
            title: title ?? "Event",
            start: startDate,
            end: endDate,
            location: location,
            description: description,
            url: url
        )
    }
}

// MARK: - 9. CountdownCard

/// Live periodic countdown timer in days/hours/min/sec with numericText transitions
struct CountdownCard: View {
    let card: JSONValue

    private var title: String? { card["title"]?.string }
    private var emoji: String? { card["emoji"]?.string }
    private var targetDate: Date? { PlacesDateParser.parse(card["target"]?.string) }

    var body: some View {
        CardContainer(title: "Countdown", symbol: "timer") {
            VStack(alignment: .leading, spacing: 14) {
                // Header with Emoji and Title
                HStack(spacing: 10) {
                    if let emoji {
                        Text(emoji)
                            .font(.system(size: 32))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title ?? "Countdown")
                            .font(Theme.sans(18, weight: .semibold))
                            .foregroundStyle(Theme.text)
                        if let targetDate {
                            Text(formatTargetDate(targetDate))
                                .font(Theme.sans(12))
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                }

                // Live TimelineView countdown
                if let target = targetDate {
                    TimelineView(.periodic(from: .now, by: 1.0)) { context in
                        let remaining = target.timeIntervalSince(context.date)
                        if remaining <= 0 {
                            HStack {
                                Spacer()
                                HStack(spacing: 8) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Theme.success)
                                    Text("Completed")
                                        .font(Theme.sans(15, weight: .semibold))
                                        .foregroundStyle(Theme.text)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(Theme.elevated, in: Capsule())
                                Spacer()
                            }
                        } else {
                            let totalSec = Int(remaining)
                            let days = totalSec / 86400
                            let hours = (totalSec % 86400) / 3600
                            let minutes = (totalSec % 3600) / 60
                            let seconds = totalSec % 60

                            HStack(spacing: 8) {
                                countdownBox(value: days, label: "Days")
                                countdownBox(value: hours, label: "Hours")
                                countdownBox(value: minutes, label: "Min")
                                countdownBox(value: seconds, label: "Sec")
                            }
                        }
                    }
                } else {
                    Text("Target date missing or invalid")
                        .font(Theme.sans(13))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
        }
    }

    private func countdownBox(value: Int, label: String) -> some View {
        VStack(spacing: 4) {
            Text(String(format: "%02d", value))
                .font(Theme.mono(24, weight: .bold))
                .foregroundStyle(Theme.text)
                .contentTransition(.numericText())

            Text(label)
                .font(Theme.sans(10, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 12))
    }

    private func formatTargetDate(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df.string(from: date)
    }
}

// MARK: - 10. TimezonesCard

/// Live clocks for world cities with day/night icon and offset vs local
struct TimezonesCard: View {
    let card: JSONValue

    private var items: [JSONValue] { card.objects("items") }

    var body: some View {
        CardContainer(title: "World Clocks", symbol: "globe") {
            TimelineView(.periodic(from: .now, by: 1.0)) { context in
                VStack(spacing: 12) {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        let city = item["city"]?.string ?? "City"
                        let tzIdentifier = item["timezone"]?.string ?? "UTC"
                        let tz = TimeZone(identifier: tzIdentifier) ?? TimeZone(abbreviation: tzIdentifier) ?? .current

                        let hourInTZ = getHour(date: context.date, timeZone: tz)
                        let isDay = hourInTZ >= 6 && hourInTZ < 18
                        let offsetText = formatOffset(date: context.date, timeZone: tz)
                        let timeString = formatTime(date: context.date, timeZone: tz)

                        HStack(spacing: 12) {
                            // Day / Night icon
                            Image(systemName: isDay ? "sun.max.fill" : "moon.stars.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(isDay ? Color.yellow : Color.indigo)
                                .frame(width: 28)

                            // City & Offset
                            VStack(alignment: .leading, spacing: 2) {
                                Text(city)
                                    .font(Theme.sans(16, weight: .semibold))
                                    .foregroundStyle(Theme.text)

                                Text(offsetText)
                                    .font(Theme.sans(12))
                                    .foregroundStyle(Theme.secondaryText)
                            }

                            Spacer()

                            // Live Clock
                            Text(timeString)
                                .font(Theme.mono(19, weight: .bold))
                                .foregroundStyle(Theme.text)
                                .contentTransition(.numericText())
                        }

                        if index < items.count - 1 {
                            Divider()
                                .overlay(Theme.hairline)
                        }
                    }
                }
            }
        }
    }

    private func getHour(date: Date, timeZone: TimeZone) -> Int {
        var cal = Calendar.current
        cal.timeZone = timeZone
        return cal.component(.hour, from: date)
    }

    private func formatTime(date: Date, timeZone: TimeZone) -> String {
        let df = DateFormatter()
        df.timeZone = timeZone
        df.dateFormat = "HH:mm:ss"
        return df.string(from: date)
    }

    private func formatOffset(date: Date, timeZone: TimeZone) -> String {
        let localOffset = TimeZone.current.secondsFromGMT(for: date)
        let tzOffset = timeZone.secondsFromGMT(for: date)
        let diffSeconds = tzOffset - localOffset
        let diffHours = Double(diffSeconds) / 3600.0

        if abs(diffHours) < 0.1 {
            return "Same time"
        } else if diffHours > 0 {
            return String(format: "+%.0f hrs vs local", diffHours)
        } else {
            return String(format: "%.0f hrs vs local", diffHours)
        }
    }
}

// MARK: - 11. CurrencyCard

/// Currency conversion card with live rate fallback from open.er-api.com
struct CurrencyCard: View {
    let card: JSONValue

    @State private var fetchedRate: Double?
    @State private var isLoading = false

    private var fromCurrency: String { card["from"]?.string ?? "USD" }
    private var toCurrency: String { card["to"]?.string ?? "EUR" }
    private var amount: Double { card["amount"]?.double ?? 1.0 }
    private var rate: Double? { card["rate"]?.double ?? fetchedRate }
    private var date: String? { card["date"]?.string }

    var body: some View {
        CardContainer(title: "Currency", symbol: "dollarsign.arrow.circlepath") {
            VStack(spacing: 16) {
                // Source Amount
                HStack(alignment: .firstTextBaseline) {
                    Text(formatNumber(amount))
                        .font(Theme.sans(22, weight: .medium))
                        .foregroundStyle(Theme.text)
                    Text(fromCurrency.uppercased())
                        .font(Theme.sans(16, weight: .bold))
                        .foregroundStyle(Theme.secondaryText)
                    Spacer()
                }

                // Direction indicator
                HStack {
                    Circle()
                        .fill(Theme.accent.opacity(0.15))
                        .frame(width: 32, height: 32)
                        .overlay(
                            Image(systemName: "arrow.down")
                                .font(Theme.sans(14, weight: .bold))
                                .foregroundStyle(Theme.accent)
                        )
                    Spacer()
                }

                // Converted Amount
                HStack(alignment: .firstTextBaseline) {
                    let conv = amount * (rate ?? 1.0)
                    Text(formatNumber(conv))
                        .font(Theme.sans(32, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .contentTransition(.numericText())

                    Text(toCurrency.uppercased())
                        .font(Theme.sans(20, weight: .bold))
                        .foregroundStyle(Theme.accent)
                    Spacer()
                }

                Divider()
                    .overlay(Theme.hairline)

                // Exchange Rate & Date Pill
                HStack {
                    if let r = rate {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("1 \(fromCurrency.uppercased()) = \(String(format: "%.4f", r)) \(toCurrency.uppercased())")
                                .font(Theme.sans(13, weight: .medium))
                                .foregroundStyle(Theme.text)

                            if r > 0 {
                                Text("1 \(toCurrency.uppercased()) = \(String(format: "%.4f", 1.0 / r)) \(fromCurrency.uppercased())")
                                    .font(Theme.sans(11))
                                    .foregroundStyle(Theme.secondaryText)
                            }
                        }
                    } else if isLoading {
                        HStack(spacing: 6) {
                            ProgressView()
                                .tint(Theme.secondaryText)
                            Text("Fetching live rate...")
                                .font(Theme.sans(12))
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }

                    Spacer()

                    if let date {
                        Text(date)
                            .font(Theme.sans(11))
                            .foregroundStyle(Theme.tertiaryText)
                    } else {
                        Text("Live rate")
                            .font(Theme.sans(11))
                            .foregroundStyle(Theme.tertiaryText)
                    }
                }
            }
        }
        .task {
            await fetchRateIfNeeded()
        }
    }

    private func fetchRateIfNeeded() async {
        if card["rate"]?.double == nil {
            isLoading = true
            do {
                fetchedRate = try await PlacesCurrencyService.shared.fetchRate(from: fromCurrency, to: toCurrency)
            } catch {
                // Graceful fallback
            }
            isLoading = false
        }
    }

    private func formatNumber(_ val: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = val.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: val)) ?? String(format: "%.2f", val)
    }
}
