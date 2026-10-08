import SwiftUI
import MapKit
import CoreLocation
import Foundation

// MARK: - 1. PlaceCard

/// Detail card for a single place (restaurant, café, landmark, museum...).
/// In chat it stays compact (hero, name, rating, one action row) and opens the full detail sheet on tap;
/// `detailed` is used by that sheet.
struct PlaceCard: View {
    let card: JSONValue
    var detailed: Bool = false

    @State private var resolvedCoordinate: CLLocationCoordinate2D?
    @State private var showDetail = false

    private var name: String? { card["name"]?.string.flatMap { $0.isEmpty ? nil : $0 } }
    private var category: String? { card["category"]?.string.flatMap { $0.isEmpty ? nil : $0 } }
    private var address: String? { card["address"]?.string.flatMap { $0.isEmpty ? nil : $0 } }
    private var rating: Double? { cardSafeDouble(card["rating"]?.double) }
    private var reviews: Int? { cardSafeInt(card["reviews"]?.double, clampedTo: 0...Int.max) }
    private var price: String? { card["price"]?.string.flatMap { $0.isEmpty ? nil : $0 } }
    private var photos: [String] { card.strings("photos") }
    private var website: URL? { placesWebURL(card["website"]?.string) }
    private var phone: String? { card["phone"]?.string }
    private var hours: String? { card["hours"]?.string.flatMap { $0.isEmpty ? nil : $0 } }
    private var summary: String? { card["summary"]?.string.flatMap { $0.isEmpty ? nil : $0 } }
    private var hasPhotos: Bool { photos.contains { placesWebURL($0) != nil } }

    var body: some View {
        CardContainer(title: category ?? "Place", symbol: "mappin.circle.fill") {
            VStack(alignment: .leading, spacing: 14) {
                if detailed {
                    headerBlock
                } else {
                    headerBlock
                        .onTapGesture { showDetail = true }
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHint(Text("Shows place details"))
                        .accessibilityAction { showDetail = true }
                }

                if detailed {
                    if let address {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: "mappin")
                                .font(Theme.sans(12))
                                .foregroundStyle(Theme.secondaryText)
                                .accessibilityHidden(true)
                            Text(address)
                                .font(Theme.sans(13))
                                .foregroundStyle(Theme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                                .cardParagraph(address)
                        }
                    }
                    if let hours {
                        PlacesHoursView(hours: hours)
                    }
                    if let summary {
                        Text(summary)
                            .font(Theme.serif(14))
                            .foregroundStyle(Theme.text.opacity(0.9))
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .cardParagraph(summary)
                    }
                    // The hero already shows a map when there are no photos.
                    if hasPhotos {
                        PlacesMiniMapView(coordinate: resolvedCoordinate, name: name)
                    }
                } else if let address {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "mappin")
                            .font(Theme.sans(12))
                            .foregroundStyle(Theme.secondaryText)
                            .accessibilityHidden(true)
                        Text(address)
                            .font(Theme.sans(13))
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(1)
                            .cardParagraph(address)
                    }
                }

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
        .sheet(isPresented: $showDetail) {
            PlacesDetailSheetView(card: card)
        }
    }

    /// Hero, name and meta/rating line.
    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            PlacesHeroCarousel(photos: photos, coordinate: resolvedCoordinate, name: name)

            if let name {
                Text(name)
                    .font(Theme.sans(19, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .cardParagraph(name)
            }

            let metaRow = buildMetaLine()
            if !metaRow.isEmpty || rating != nil {
                HStack(spacing: 8) {
                    if !metaRow.isEmpty {
                        Text(metaRow)
                            .font(Theme.sans(13, weight: .medium))
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(1)
                    }
                    PlacesRatingView(rating: rating, reviews: reviews)
                    Spacer(minLength: 0)
                }
            }
        }
        .contentShape(Rectangle())
    }

    private func buildMetaLine() -> String {
        var parts: [String] = []
        if let category { parts.append(category) }
        if let price { parts.append(price) }
        return parts.joined(separator: " • ")
    }

    private func resolveCoordinates() async {
        if let lat = cardSafeDouble(card["lat"]?.double), let lon = cardSafeDouble(card["lon"]?.double),
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
                    let rating = cardSafeDouble(item["rating"]?.double)
                    let reviews = cardSafeInt(item["reviews"]?.double, clampedTo: 0...Int.max)
                    let category = item["category"]?.string.flatMap { $0.isEmpty ? nil : $0 }
                    let price = item["price"]?.string.flatMap { $0.isEmpty ? nil : $0 }
                    let address = item["address"]?.string.flatMap { $0.isEmpty ? nil : $0 }

                    Button {
                        selectedPlace = PlacesItemWrapper(json: item)
                    } label: {
                        HStack(spacing: 12) {
                            // Thumbnail 64x64
                            Group {
                                if let firstPhoto = photos.compactMap({ placesWebURL($0) }).first {
                                    AsyncImage(url: firstPhoto) { phase in
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
                            .accessibilityHidden(true)

                            // Details
                            VStack(alignment: .leading, spacing: 3) {
                                Text(name)
                                    .font(Theme.sans(15, weight: .semibold))
                                    .foregroundStyle(Theme.text)
                                    .lineLimit(1)
                                    .cardParagraph(name)

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
                                            .lineLimit(1)
                                            .fixedSize()
                                    }
                                }

                                if let address {
                                    Text(address)
                                        .font(Theme.sans(12))
                                        .foregroundStyle(Theme.tertiaryText)
                                        .lineLimit(1)
                                        .cardParagraph(address)
                                }
                            }

                            Spacer(minLength: 4)

                            Image(systemName: "chevron.right")
                                .font(Theme.sans(12, weight: .semibold))
                                .foregroundStyle(Theme.tertiaryText)
                                .accessibilityHidden(true)
                        }
                        .padding(8)
                        .frame(minHeight: 44)
                        .background(Theme.elevated.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
                        .contentShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityHint(Text("Shows place details"))

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

/// Sheet presentation view matching Claude app style (full height: hero and details are not truncated)
private struct PlacesDetailSheetView: View {
    let card: JSONValue

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: card["name"]?.string ?? String(localized: "Place Details"))

            ScrollView {
                PlaceCard(card: card, detailed: true)
                    .padding(Theme.margin)
            }
        }
        .background(Theme.surface)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.surface)
    }
}

// MARK: - Shared small views

/// Solid info chip (icon + one line of text). Never glass: this is content, not a control.
private struct PlacesChip: View {
    let symbol: String
    let text: String
    var emphasized = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(Theme.sans(12))
                .accessibilityHidden(true)
            Text(text)
                .font(Theme.sans(12, weight: emphasized ? .semibold : .medium))
                .lineLimit(1)
        }
        .foregroundStyle(Theme.text)
        .fixedSize()
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.elevated, in: Capsule())
        .overlay(Capsule().stroke(Theme.hairline))
        .accessibilityElement(children: .combine)
    }
}

/// Solid 44pt pill button used for card actions (no glass on content cards).
private struct PlacesPillButton: View {
    let title: LocalizedStringKey
    let symbol: String
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .accessibilityHidden(true)
                Text(title)
                    .font(Theme.sans(13, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(prominent ? Color.white : Theme.text)
            .fixedSize()
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(prominent ? Theme.accent : Theme.surface, in: Capsule())
            .overlay(Capsule().stroke(Theme.hairline))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
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

/// Map card: a non-interactive map in the chat (it never traps scrolling), pin rows below it,
/// and an explicit "Explore" sheet with the fully interactive map.
struct MapCard: View {
    let card: JSONValue

    @Environment(\.openURL) private var openURL
    @State private var resolvedPins: [PlacesMapPin] = []
    @State private var selectedPinId: UUID?
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var isResolving = true
    @State private var showExplorer = false

    private var title: String? { card["title"]?.string }
    private var regionName: String? { card["region"]?.string }
    private var rawPins: [JSONValue] { card.objects("pins") }

    var body: some View {
        CardContainer(title: title ?? "Map", symbol: "map.fill") {
            VStack(alignment: .leading, spacing: 12) {
                Map(position: $cameraPosition, interactionModes: []) {
                    ForEach(resolvedPins) { pin in
                        Marker(pin.name, coordinate: pin.coordinate)
                            .tint(pin.id == selectedPinId ? Theme.accent : Theme.secondaryText)
                    }
                }
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Theme.hairline)
                )
                .overlay {
                    if isResolving && resolvedPins.isEmpty {
                        ProgressView().tint(Theme.secondaryText)
                    }
                }
                .accessibilityLabel(Text(title ?? "Map"))

                if !isResolving && resolvedPins.isEmpty && !rawPins.isEmpty {
                    Label("Couldn't locate these places on the map.", systemImage: "exclamationmark.triangle")
                        .font(Theme.sans(13))
                        .foregroundStyle(Theme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !resolvedPins.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(resolvedPins) { pin in
                            pinRow(pin)
                            if pin.id != resolvedPins.last?.id {
                                Divider().overlay(Theme.hairline)
                            }
                        }
                    }
                    .background(Theme.elevated.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else if let regionName, !regionName.isEmpty {
                    Text(regionName)
                        .font(Theme.sans(13))
                        .foregroundStyle(Theme.secondaryText)
                        .cardParagraph(regionName)
                }

                HStack(spacing: 8) {
                    if !resolvedPins.isEmpty {
                        PlacesPillButton(title: "Explore", symbol: "arrow.up.left.and.arrow.down.right") {
                            showExplorer = true
                        }
                    }
                    PlacesPillButton(title: "Open in Maps", symbol: "map") {
                        openAllInMaps()
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .task {
            await resolvePins()
        }
        .sheet(isPresented: $showExplorer) {
            PlacesMapExplorerSheet(
                title: title ?? String(localized: "Map"),
                pins: resolvedPins,
                initialSelection: selectedPinId
            )
        }
    }

    private func pinRow(_ pin: PlacesMapPin) -> some View {
        let isSelected = pin.id == selectedPinId
        return HStack(spacing: 0) {
            Button {
                withAnimation(.smooth(duration: 0.3)) {
                    selectedPinId = isSelected ? nil : pin.id
                    cameraPosition = .region(MKCoordinateRegion(
                        center: pin.coordinate, latitudinalMeters: 1500, longitudinalMeters: 1500))
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: isSelected ? "mappin.circle.fill" : "mappin.circle")
                        .foregroundStyle(isSelected ? Theme.accent : Theme.secondaryText)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pin.name)
                            .font(Theme.sans(14, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .fixedSize(horizontal: false, vertical: true)
                            .cardParagraph(pin.name)
                        if let note = pin.note, !note.isEmpty {
                            Text(note)
                                .font(Theme.sans(12))
                                .foregroundStyle(Theme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                                .cardParagraph(note)
                        }
                    }
                }
                .padding(.leading, 12)
                .padding(.vertical, 6)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])

            if isSelected {
                Button {
                    PlacesOpenMapsHelper.open(coordinate: pin.coordinate, name: pin.name)
                } label: {
                    Image(systemName: "arrow.up.right")
                        .font(Theme.sans(13, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Open in Maps"))
            } else {
                Color.clear.frame(width: 12, height: 1)
            }
        }
    }

    private func resolvePins() async {
        var result: [PlacesMapPin] = []

        for p in rawPins.prefix(30) {
            let name = p["name"]?.string ?? p["query"]?.string ?? String(localized: "Pin")
            let note = p["note"]?.string

            if let lat = cardSafeDouble(p["lat"]?.double), let lon = cardSafeDouble(p["lon"]?.double),
               CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(latitude: lat, longitude: lon)) {
                result.append(PlacesMapPin(
                    name: name,
                    coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                    note: note
                ))
            } else if let query = p["query"]?.string ?? p["name"]?.string {
                if let coord = await PlacesGeocodingService.shared.geocode(query: query) {
                    result.append(PlacesMapPin(name: name, coordinate: coord, note: note))
                }
            }
        }

        resolvedPins = result

        if result.isEmpty, let reg = regionName {
            if let regionCoord = await PlacesGeocodingService.shared.geocode(query: reg) {
                cameraPosition = .region(MKCoordinateRegion(center: regionCoord, latitudinalMeters: 8000, longitudinalMeters: 8000))
            }
        } else if result.count > 1 {
            cameraPosition = .automatic
        } else if let only = result.first {
            cameraPosition = .region(MKCoordinateRegion(center: only.coordinate, latitudinalMeters: 1500, longitudinalMeters: 1500))
        }
        isResolving = false
    }

    private func openAllInMaps() {
        if !resolvedPins.isEmpty {
            let items = resolvedPins.map { pin -> MKMapItem in
                let item = MKMapItem(placemark: MKPlacemark(coordinate: pin.coordinate))
                item.name = pin.name
                return item
            }
            MKMapItem.openMaps(with: items, launchOptions: nil)
        } else if let reg = regionName,
                  let url = cardMakeURL(scheme: "https", host: "maps.apple.com", path: "/",
                                        queryItems: [URLQueryItem(name: "q", value: reg)]) {
            openURL(url)
        }
    }
}

/// Full-height sheet with the interactive map (explicit expand, so the chat card never traps scrolling).
private struct PlacesMapExplorerSheet: View {
    let title: String
    let pins: [PlacesMapPin]
    let initialSelection: UUID?

    @State private var selection: UUID?
    @State private var camera: MapCameraPosition = .automatic

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: title)

            Map(position: $camera, selection: $selection) {
                ForEach(pins) { pin in
                    Marker(pin.name, coordinate: pin.coordinate)
                        .tint(Theme.accent)
                        .tag(pin.id)
                }
            }
            .mapControls { MapCompass(); MapScaleView() }

            if let selected = pins.first(where: { $0.id == selection }) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selected.name)
                            .font(Theme.sans(15, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .fixedSize(horizontal: false, vertical: true)
                            .cardParagraph(selected.name)
                        if let note = selected.note, !note.isEmpty {
                            Text(note)
                                .font(Theme.sans(13))
                                .foregroundStyle(Theme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                                .cardParagraph(note)
                        }
                    }
                    PlacesPillButton(title: "Open", symbol: "arrow.up.right", prominent: true) {
                        PlacesOpenMapsHelper.open(coordinate: selected.coordinate, name: selected.name)
                    }
                }
                .padding(14)
                .background(Theme.elevated)
            }
        }
        .background(Theme.surface)
        .presentationDetents([.large])
        .presentationBackground(Theme.surface)
        .onAppear { selection = initialSelection }
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
    @State private var isLoading = true
    @State private var routeNote: String?

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
                    endpointRow(color: Theme.success, name: fromName ?? String(localized: "Start"), weight: .medium)
                    endpointRow(color: Theme.accent, name: toName ?? String(localized: "Destination"), weight: .semibold)
                }
                .accessibilityElement(children: .combine)

                // Map with route polyline (non-interactive: never traps scrolling)
                Map(position: $cameraPosition, interactionModes: []) {
                    if let fromCoord {
                        Marker(fromName ?? String(localized: "Start"), coordinate: fromCoord)
                            .tint(Theme.success)
                    }
                    if let toCoord {
                        Marker(toName ?? String(localized: "End"), coordinate: toCoord)
                            .tint(Theme.accent)
                    }
                    if polylineCoordinates.count > 1 {
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
                .overlay {
                    if isLoading { ProgressView().tint(Theme.secondaryText) }
                }
                .accessibilityHidden(true)

                // Mode, duration, distance chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        PlacesChip(symbol: modeIcon(mode), text: modeTitle(mode))
                        if let duration, !duration.isEmpty {
                            PlacesChip(symbol: "clock", text: duration, emphasized: true)
                        }
                        if let distance, !distance.isEmpty {
                            PlacesChip(symbol: "arrow.left.and.right", text: distance, emphasized: true)
                        }
                    }
                }

                if let routeNote {
                    Label(routeNote, systemImage: "exclamationmark.triangle")
                        .font(Theme.sans(12))
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
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
                                Text("\(steps.count) steps")
                                    .font(Theme.sans(13, weight: .semibold))
                                    .foregroundStyle(Theme.text)
                                Spacer()
                                Image(systemName: isStepsExpanded ? "chevron.up" : "chevron.down")
                                    .font(Theme.sans(12, weight: .semibold))
                                    .foregroundStyle(Theme.secondaryText)
                                    .accessibilityHidden(true)
                            }
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityValue(Text(isStepsExpanded ? "Expanded" : "Collapsed"))

                        if isStepsExpanded {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(Array(steps.enumerated()), id: \.offset) { idx, step in
                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        Text("\((idx + 1).formatted()).")
                                            .font(Theme.sans(12, weight: .bold))
                                            .monospacedDigit()
                                            .foregroundStyle(Theme.secondaryText)
                                            .frame(minWidth: 20, alignment: .trailing)
                                        Text(step)
                                            .font(Theme.sans(13))
                                            .foregroundStyle(Theme.text)
                                            .fixedSize(horizontal: false, vertical: true)
                                            .cardParagraph(step)
                                    }
                                    .accessibilityElement(children: .combine)
                                }
                            }
                            .padding(10)
                            .background(Theme.elevated.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                            .transition(.opacity)
                        }
                    }
                }

                // Bottom button: launch navigation in Apple Maps
                if let to = toCoord {
                    PlacesPillButton(title: "Open in Maps", symbol: "arrow.triangle.turn.up.right.diamond.fill", prominent: true) {
                        PlacesOpenMapsHelper.openRoute(
                            from: fromCoord,
                            fromName: fromName,
                            to: to,
                            toName: toName,
                            mode: mode
                        )
                    }
                }
            }
        }
        .task {
            await calculateRoute()
        }
    }

    private func endpointRow(color: Color, name: String, weight: Font.Weight) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)
            Text(name)
                .font(Theme.sans(14, weight: weight))
                .foregroundStyle(Theme.text)
                .lineLimit(2)
                .cardParagraph(name)
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
        case "walking": return String(localized: "Walking")
        case "transit": return String(localized: "Transit")
        case "cycling": return String(localized: "Cycling")
        default: return String(localized: "Driving")
        }
    }

    private func calculateRoute() async {
        defer { isLoading = false }
        guard let fromStr = fromName, let toStr = toName else { return }

        async let fCoord = PlacesGeocodingService.shared.geocode(query: fromStr)
        async let tCoord = PlacesGeocodingService.shared.geocode(query: toStr)

        fromCoord = await fCoord
        toCoord = await tCoord

        guard let src = fromCoord, let dst = toCoord else {
            routeNote = String(localized: "Couldn't locate one of the places on the map.")
            return
        }

        // MKDirections has no cycling mode: draw a straight line and rely on the card's own numbers.
        if mode?.lowercased() == "cycling" {
            polylineCoordinates = [src, dst]
            return
        }

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

                if let seconds = cardSafeDouble(route.expectedTravelTime), seconds >= 0 {
                    let minutes = (seconds / 60).rounded()
                    calculatedDuration = Duration.seconds(minutes * 60)
                        .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
                }
                if let meters = cardSafeDouble(route.distance) {
                    calculatedDistance = Measurement(value: meters, unit: UnitLength.meters)
                        .formatted(.measurement(width: .abbreviated, usage: .road))
                }
                calculatedSteps = route.steps.map(\.instructions).filter { !$0.isEmpty }
            }
        } catch {
            // Transit or remote route: show the straight line and say so.
            polylineCoordinates = [src, dst]
            routeNote = String(localized: "Turn-by-turn directions aren't available for this route; the line is approximate.")
        }
    }
}

// MARK: - 5. WeatherCard

/// Wall-clock parsing for Open-Meteo local times ("2026-10-08T14:00" / "2026-10-08"), which carry no zone:
/// parse and format both in GMT so the displayed hour is the hour at the forecast location.
private enum PlacesWeatherTime {
    static let gmt = TimeZone(secondsFromGMT: 0) ?? .current

    private static let hourParser: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = gmt
        df.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return df
    }()

    private static let dayParser: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = gmt
        df.dateFormat = "yyyy-MM-dd"
        return df
    }()

    static func hourLabel(_ iso: String) -> String {
        guard let d = hourParser.date(from: iso) else { return String(iso.split(separator: "T").last ?? Substring(iso)) }
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = gmt
        return d.formatted(style)
    }

    static func weekday(_ day: String) -> String {
        guard let d = dayParser.date(from: day) else { return day }
        var style = Date.FormatStyle().weekday(.abbreviated)
        style.timeZone = gmt
        return d.formatted(style)
    }

    static func temperature(_ celsius: Double) -> String {
        Measurement(value: celsius, unit: UnitTemperature.celsius)
            .formatted(.measurement(width: .narrow, usage: .weather,
                                    numberFormatStyle: .number.precision(.fractionLength(0))))
    }
}

/// Live weather from Open-Meteo with condition gradient, hourly strip, and 7-day forecast
struct WeatherCard: View {
    let card: JSONValue

    @State private var weatherData: PlacesWeatherResponse?
    @State private var resolvedLocationName: String?
    @State private var isLoading = true
    @State private var failed = false

    private var locationName: String? { card["location"]?.string }
    private var summary: String? { card["summary"]?.string }

    var body: some View {
        let code = weatherData?.current?.weather_code ?? 0
        let isDay = (weatherData?.current?.is_day ?? 1) != 0
        let condition = PlacesWeatherCondition.from(code: code, isDay: isDay)

        VStack(alignment: .leading, spacing: 14) {
            // Header: Location name + condition description
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    let title = resolvedLocationName ?? locationName ?? String(localized: "Weather")
                    Text(title)
                        .font(Theme.sans(19, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .cardParagraph(title)
                    let sub = summary ?? (weatherData == nil ? "" : condition.description)
                    if !sub.isEmpty {
                        Text(sub)
                            .font(Theme.sans(13))
                            .foregroundStyle(Theme.text.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                            .cardParagraph(sub)
                    }
                }

                Spacer(minLength: 8)

                if weatherData != nil {
                    Image(systemName: condition.symbol)
                        .font(.system(size: 38))
                        .symbolRenderingMode(.multicolor)
                        .accessibilityLabel(Text(condition.description))
                }
            }

            if weatherData == nil {
                if isLoading {
                    HStack(spacing: 8) {
                        ProgressView().tint(Theme.text)
                        Text("Loading forecast")
                            .font(Theme.sans(13))
                            .foregroundStyle(Theme.text.opacity(0.85))
                    }
                    .frame(minHeight: 44)
                } else if failed {
                    HStack(spacing: 10) {
                        Label("Forecast unavailable", systemImage: "exclamationmark.triangle")
                            .font(Theme.sans(13))
                            .foregroundStyle(Theme.text)
                        Spacer(minLength: 0)
                        Button {
                            Task { await fetchWeather() }
                        } label: {
                            Text("Retry")
                                .font(Theme.sans(13, weight: .semibold))
                                .foregroundStyle(Theme.text)
                                .padding(.horizontal, 14)
                                .frame(minHeight: 44)
                                .background(Color.black.opacity(0.25), in: Capsule())
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Big temperature + High/Low
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                if let temp = cardSafeDouble(weatherData?.current?.temperature_2m) {
                    Text(PlacesWeatherTime.temperature(temp))
                        .font(Theme.sans(48, weight: .light))
                        .monospacedDigit()
                        .foregroundStyle(Theme.text)
                }

                if let daily = weatherData?.daily,
                   let maxT = cardSafeDouble(daily.temperature_2m_max?.first),
                   let minT = cardSafeDouble(daily.temperature_2m_min?.first) {
                    Text("H: \(PlacesWeatherTime.temperature(maxT))  L: \(PlacesWeatherTime.temperature(minT))")
                        .font(Theme.sans(14, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(Theme.text.opacity(0.85))
                }
            }

            // Current stats chips (Wind, Humidity)
            HStack(spacing: 8) {
                if let wind = cardSafeDouble(weatherData?.current?.wind_speed_10m) {
                    statChip(symbol: "wind",
                             text: Measurement(value: wind, unit: UnitSpeed.kilometersPerHour)
                                .formatted(.measurement(width: .abbreviated, usage: .general,
                                                        numberFormatStyle: .number.precision(.fractionLength(0...1)))))
                }

                if let humidity = cardSafeDouble(weatherData?.current?.relative_humidity_2m) {
                    statChip(symbol: "humidity.fill",
                             text: (humidity / 100).formatted(.percent.precision(.fractionLength(0))))
                }
            }

            hourlyStrip
            dailyRows
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
        .animation(.smooth(duration: 0.3), value: weatherData != nil)
        .task {
            await fetchWeather()
        }
    }

    private func statChip(symbol: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .accessibilityHidden(true)
            Text(text)
                .monospacedDigit()
                .lineLimit(1)
        }
        .font(Theme.sans(12))
        .foregroundStyle(Theme.text)
        .fixedSize()
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.12), in: Capsule())
        .accessibilityElement(children: .combine)
    }

    /// Next 12 hours starting at the current hour (not at midnight).
    @ViewBuilder private var hourlyStrip: some View {
        if let hourly = weatherData?.hourly, let times = hourly.time, let temps = hourly.temperature_2m, let codes = hourly.weather_code {
            let total = min(times.count, min(temps.count, codes.count))
            let nowKey = String((weatherData?.current?.time ?? "").prefix(13))
            let start = nowKey.isEmpty ? 0 : (times.prefix(total).firstIndex(where: { String($0.prefix(13)) >= nowKey }) ?? 0)
            let end = min(total, start + 12)
            if start < end {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Hourly Forecast")
                        .font(Theme.sans(11, weight: .semibold))
                        .foregroundStyle(Theme.text.opacity(0.75))
                        .textCase(.uppercase)
                        .accessibilityAddTraits(.isHeader)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(start..<end, id: \.self) { i in
                                let hourIsDay = (hourly.is_day.flatMap { i < $0.count ? $0[i] : nil } ?? 1) != 0
                                let hCond = PlacesWeatherCondition.from(code: codes[i], isDay: hourIsDay)

                                VStack(spacing: 6) {
                                    Text(i == start ? String(localized: "Now") : PlacesWeatherTime.hourLabel(times[i]))
                                        .font(Theme.sans(12))
                                        .foregroundStyle(Theme.text.opacity(0.85))
                                        .lineLimit(1)
                                        .fixedSize()

                                    Image(systemName: hCond.symbol)
                                        .font(.system(size: 18))
                                        .symbolRenderingMode(.multicolor)
                                        .accessibilityHidden(true)

                                    Text(cardSafeDouble(temps[i]).map(PlacesWeatherTime.temperature) ?? "--")
                                        .font(Theme.sans(13, weight: .semibold))
                                        .monospacedDigit()
                                        .foregroundStyle(Theme.text)
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                    }
                    .background(Color.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    /// 7-day rows with a min/max range bar.
    @ViewBuilder private var dailyRows: some View {
        if let daily = weatherData?.daily,
           let times = daily.time,
           let codes = daily.weather_code,
           let maxs = daily.temperature_2m_max,
           let mins = daily.temperature_2m_min {

            let count = min(7, min(times.count, min(codes.count, min(maxs.count, mins.count))))
            if count > 0 {
                let weekMin = mins.prefix(count).filter { $0.isFinite }.min() ?? 0
                let weekMax = maxs.prefix(count).filter { $0.isFinite }.max() ?? 40

                VStack(alignment: .leading, spacing: 8) {
                    Text("7-Day Forecast")
                        .font(Theme.sans(11, weight: .semibold))
                        .foregroundStyle(Theme.text.opacity(0.75))
                        .textCase(.uppercase)
                        .accessibilityAddTraits(.isHeader)

                    VStack(spacing: 8) {
                        ForEach(0..<count, id: \.self) { i in
                            let dayName = i == 0 ? String(localized: "Today") : PlacesWeatherTime.weekday(times[i])
                            let dCond = PlacesWeatherCondition.from(code: codes[i], isDay: true)
                            let dMin = mins[i].isFinite ? mins[i] : weekMin
                            let dMax = maxs[i].isFinite ? maxs[i] : weekMax

                            HStack(spacing: 10) {
                                Text(dayName)
                                    .font(Theme.sans(13, weight: .medium))
                                    .foregroundStyle(Theme.text)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                    .frame(width: 52, alignment: .leading)

                                Image(systemName: dCond.symbol)
                                    .font(.system(size: 16))
                                    .symbolRenderingMode(.multicolor)
                                    .frame(width: 24)
                                    .accessibilityLabel(Text(dCond.description))

                                Text(PlacesWeatherTime.temperature(dMin))
                                    .font(Theme.sans(13))
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.text.opacity(0.75))
                                    .frame(minWidth: 34, alignment: .trailing)

                                GeometryReader { geo in
                                    let totalRange = Swift.max(1.0, weekMax - weekMin)
                                    let startFrac = Swift.max(0.0, (dMin - weekMin) / totalRange)
                                    let endFrac = Swift.min(1.0, (dMax - weekMin) / totalRange)
                                    let startX = geo.size.width * CGFloat(startFrac)
                                    let barWidth = Swift.min(geo.size.width - startX,
                                                             Swift.max(6.0, geo.size.width * CGFloat(endFrac - startFrac)))

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
                                            .frame(width: Swift.max(0, barWidth), height: 4)
                                            .offset(x: startX)
                                    }
                                }
                                .frame(height: 4)
                                .environment(\.layoutDirection, .leftToRight)
                                .accessibilityHidden(true)

                                Text(PlacesWeatherTime.temperature(dMax))
                                    .font(Theme.sans(13, weight: .semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.text)
                                    .frame(minWidth: 34, alignment: .leading)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .padding(12)
                    .background(Color.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private func fetchWeather() async {
        isLoading = true
        failed = false
        var lat = cardSafeDouble(card["lat"]?.double)
        var lon = cardSafeDouble(card["lon"]?.double)

        if lat == nil || lon == nil, let loc = locationName {
            if let geo = try? await PlacesWeatherService.shared.geocode(location: loc) {
                lat = geo.lat
                lon = geo.lon
                resolvedLocationName = geo.name
            }
        }

        guard let latitude = lat, let longitude = lon else {
            isLoading = false
            failed = true
            return
        }

        do {
            let data = try await PlacesWeatherService.shared.fetchWeather(lat: latitude, lon: longitude)
            weatherData = data
        } catch {
            failed = true
        }
        isLoading = false
    }
}

// MARK: - 6. FlightCard

/// Boarding pass style flight detail card
struct FlightCard: View {
    let card: JSONValue

    private func text(_ v: JSONValue?) -> String? {
        guard let s = v?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }

    private var airline: String? { text(card["airline"]) }
    private var number: String? { text(card["number"]) }
    private var status: String? { text(card["status"]) }
    private var terminal: String? { text(card["terminal"]) }
    private var gate: String? { text(card["gate"]) }
    private var duration: String? { text(card["duration"]) }

    private var fromCode: String { text(card["from"]?["code"])?.uppercased() ?? "DEP" }
    private var fromCity: String? { text(card["from"]?["city"]) }
    private var fromTime: String? { displayTime(text(card["from"]?["time"])) }

    private var toCode: String { text(card["to"]?["code"])?.uppercased() ?? "ARR" }
    private var toCity: String? { text(card["to"]?["city"]) }
    private var toTime: String? { displayTime(text(card["to"]?["time"])) }

    /// ISO date-times are shown in the user's locale; free text from the model is shown as is.
    private func displayTime(_ raw: String?) -> String? {
        guard let raw else { return nil }
        if raw.contains("T"), let date = CardDates.parse(raw) {
            return date.formatted(.dateTime.hour().minute())
        }
        return raw
    }

    var body: some View {
        CardContainer(title: "Flight", symbol: "airplane.departure") {
            VStack(spacing: 16) {
                // Top Header: Airline + Flight # and Status Badge
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "airplane")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.accent)
                            .accessibilityHidden(true)
                        Text(flightHeader)
                            .font(Theme.sans(15, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .cardTextDirection(flightHeader)
                    }

                    Spacer(minLength: 4)

                    if let status {
                        Text(status)
                            .font(Theme.sans(12, weight: .bold))
                            .foregroundStyle(statusColor(status))
                            .lineLimit(1)
                            .fixedSize()
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(statusColor(status).opacity(0.16), in: Capsule())
                            .overlay(Capsule().stroke(statusColor(status).opacity(0.35)))
                    }
                }

                // Main Flight Route Block (airport codes always read left to right)
                HStack(alignment: .center, spacing: 6) {
                    // Origin
                    VStack(alignment: .leading, spacing: 2) {
                        Text(fromCode)
                            .font(Theme.sans(28, weight: .bold))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        if let fromCity {
                            Text(fromCity)
                                .font(Theme.sans(12))
                                .foregroundStyle(Theme.secondaryText)
                                .lineLimit(1)
                        }
                        if let fromTime {
                            Text(fromTime)
                                .font(Theme.sans(15, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(Theme.text)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Plane Path + Duration
                    VStack(spacing: 4) {
                        if let duration {
                            Text(duration)
                                .font(Theme.sans(12, weight: .medium))
                                .foregroundStyle(Theme.secondaryText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
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
                        .frame(minWidth: 44, maxWidth: 100)
                    }
                    .layoutPriority(1)

                    // Destination
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(toCode)
                            .font(Theme.sans(28, weight: .bold))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        if let toCity {
                            Text(toCity)
                                .font(Theme.sans(12))
                                .foregroundStyle(Theme.secondaryText)
                                .lineLimit(1)
                        }
                        if let toTime {
                            Text(toTime)
                                .font(Theme.sans(15, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(Theme.text)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .environment(\.layoutDirection, .leftToRight)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(routeAccessibilityLabel))

                // Perforated ticket tear line
                Rectangle()
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                    .foregroundStyle(Theme.hairline)
                    .frame(height: 1)

                // Bottom boarding pass metadata
                HStack(spacing: 16) {
                    if let terminal {
                        metaBlock(label: "TERMINAL", value: terminal, alignment: .leading)
                    }

                    if let gate {
                        metaBlock(label: "GATE", value: gate, alignment: .leading)
                    }

                    Spacer(minLength: 0)

                    if let duration, terminal == nil && gate == nil {
                        metaBlock(label: "FLIGHT TIME", value: duration, alignment: .trailing)
                    }
                }
            }
        }
    }

    private func metaBlock(label: LocalizedStringKey, value: String, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(label)
                .font(Theme.sans(11, weight: .semibold))
                .foregroundStyle(Theme.tertiaryText)
            Text(value)
                .font(Theme.sans(14, weight: .semibold))
                .foregroundStyle(Theme.text)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var routeAccessibilityLabel: String {
        var parts: [String] = []
        parts.append([fromCity, fromCode].compactMap { $0 }.joined(separator: " "))
        if let fromTime { parts[0] += " " + fromTime }
        var dest = [toCity, toCode].compactMap { $0 }.joined(separator: " ")
        if let toTime { dest += " " + toTime }
        parts.append(dest)
        if let duration { parts.append(duration) }
        return parts.joined(separator: " – ")
    }

    private var flightHeader: String {
        var parts: [String] = []
        if let airline { parts.append(airline) }
        if let number { parts.append(number) }
        return parts.isEmpty ? String(localized: "Flight") : parts.joined(separator: " ")
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

    private var name: String? { card["name"]?.string.flatMap { $0.isEmpty ? nil : $0 } }
    private var address: String? { card["address"]?.string.flatMap { $0.isEmpty ? nil : $0 } }
    private var stars: Int? { cardSafeInt(card["stars"]?.double, clampedTo: 0...5) }
    private var rating: Double? { cardSafeDouble(card["rating"]?.double) }
    private var price: String? { card["price"]?.string.flatMap { $0.isEmpty ? nil : $0 } }
    private var photos: [String] { card.strings("photos") }
    private var amenities: [String] { card.strings("amenities").filter { !$0.isEmpty } }
    private var website: URL? { placesWebURL(card["website"]?.string) }
    private var hasPhotos: Bool { photos.contains { placesWebURL($0) != nil } }

    var body: some View {
        CardContainer(title: "Hotel", symbol: "bed.double.fill") {
            VStack(alignment: .leading, spacing: 14) {
                // Hero Photo Carousel (shows a map when there are no photos)
                PlacesHeroCarousel(photos: photos, coordinate: resolvedCoordinate, name: name)

                // Hotel Name
                if let name {
                    Text(name)
                        .font(Theme.sans(19, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .cardParagraph(name)
                }

                // Stars • Rating • Price row
                HStack(spacing: 8) {
                    if let stars, stars > 0 {
                        HStack(spacing: 2) {
                            ForEach(0..<stars, id: \.self) { _ in
                                Image(systemName: "star.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(cardStarColor)
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text("\(stars) stars"))
                    }

                    PlacesRatingView(rating: rating, reviews: nil)

                    if let price {
                        Text((stars != nil || rating != nil ? "• " : "") + price)
                            .font(Theme.sans(14, weight: .bold))
                            .foregroundStyle(Theme.accent)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: 0)
                }

                // Address
                if let address {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "mappin")
                            .font(Theme.sans(12))
                            .foregroundStyle(Theme.secondaryText)
                            .accessibilityHidden(true)
                        Text(address)
                            .font(Theme.sans(13))
                            .foregroundStyle(Theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .cardParagraph(address)
                    }
                }

                // Amenities Pills
                if !amenities.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(Array(amenities.enumerated()), id: \.offset) { _, am in
                                HStack(spacing: 4) {
                                    Image(systemName: amenityIcon(am))
                                        .font(.system(size: 11))
                                        .accessibilityHidden(true)
                                    Text(am)
                                        .font(Theme.sans(12, weight: .medium))
                                        .lineLimit(1)
                                }
                                .foregroundStyle(Theme.text)
                                .fixedSize()
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Theme.elevated, in: Capsule())
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                }

                // Embedded map only when the hero is not already a map
                if hasPhotos {
                    PlacesMiniMapView(coordinate: resolvedCoordinate, name: name)
                }

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
        if lower.contains("wifi") || lower.contains("wi-fi") || lower.contains("internet") { return "wifi" }
        if lower.contains("pool") || lower.contains("swim") { return "figure.pool.swim" }
        if lower.contains("gym") || lower.contains("fitness") { return "dumbbell.fill" }
        if lower.contains("spa") || lower.contains("sauna") { return "sparkles" }
        if lower.contains("breakfast") || lower.contains("dining") || lower.contains("restaurant") { return "cup.and.saucer.fill" }
        if lower.contains("parking") { return "parkingsign.circle.fill" }
        if lower.contains("air") || lower.contains("a/c") || lower.split(separator: " ").contains("ac") { return "air.conditioner.horizontal" }
        if lower.contains("pet") { return "pawprint.fill" }
        if lower.contains("bar") { return "wineglass.fill" }
        return "checkmark.circle"
    }

    private func resolveCoordinates() async {
        if let lat = cardSafeDouble(card["lat"]?.double), let lon = cardSafeDouble(card["lon"]?.double),
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

    @Environment(\.openURL) private var openURL
    @State private var icsFileURL: URL?

    private var title: String? { card["title"]?.string.flatMap { $0.isEmpty ? nil : $0 } }
    private var location: String? { card["location"]?.string.flatMap { $0.isEmpty ? nil : $0 } }
    private var description: String? { card["description"]?.string.flatMap { $0.isEmpty ? nil : $0 } }
    private var url: URL? { placesWebURL(card["url"]?.string) }

    private var startDate: Date? { PlacesDateParser.parse(card["start"]?.string) }
    private var endDate: Date? { PlacesDateParser.parse(card["end"]?.string) }

    /// Date-only strings ("2026-10-08") have no time of day to show.
    private var startHasTime: Bool {
        guard let raw = card["start"]?.string else { return false }
        return raw.contains("T") || raw.contains(":")
    }

    private var whenText: String {
        if let startDate, !startHasTime, endDate == nil {
            return startDate.formatted(date: .complete, time: .omitted)
        }
        return PlacesDateParser.formatTimeRange(start: startDate, end: endDate)
    }

    var body: some View {
        CardContainer(title: "Event", symbol: "calendar") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    // Date Badge (Month / Day)
                    VStack(spacing: 0) {
                        Text(monthString)
                            .font(Theme.sans(11, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 3)
                            .background(Theme.accent)

                        Text(dayString)
                            .font(Theme.sans(22, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.text)
                            .frame(maxHeight: .infinity)
                    }
                    .frame(width: 54, height: 60)
                    .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 12))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .accessibilityHidden(true)

                    // Title & Time & Location
                    VStack(alignment: .leading, spacing: 4) {
                        let heading = title ?? String(localized: "Event")
                        Text(heading)
                            .font(Theme.sans(17, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                            .cardParagraph(heading)

                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Image(systemName: "clock")
                                .font(Theme.sans(12))
                                .accessibilityHidden(true)
                            Text(whenText)
                                .font(Theme.sans(13))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .foregroundStyle(Theme.secondaryText)

                        if let location {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Image(systemName: "mappin.and.ellipse")
                                    .font(Theme.sans(12))
                                    .accessibilityHidden(true)
                                Text(location)
                                    .font(Theme.sans(13))
                                    .lineLimit(2)
                                    .cardParagraph(location)
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
                        .fixedSize(horizontal: false, vertical: true)
                        .cardParagraph(description)
                }

                // Actions: Add to Calendar (ICS) + Website
                if icsFileURL != nil || url != nil {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            if let icsFileURL {
                                ShareLink(item: icsFileURL, preview: SharePreview(title ?? String(localized: "Event"), image: Image(systemName: "calendar"))) {
                                    actionLabel("Add to Calendar", symbol: "calendar.badge.plus")
                                }
                                .buttonStyle(.plain)
                            }

                            if let url {
                                Button {
                                    openURL(url)
                                } label: {
                                    actionLabel("Event Page", symbol: "safari")
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
        .task(id: card) {
            generateICS()
        }
    }

    private func actionLabel(_ title: LocalizedStringKey, symbol: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .accessibilityHidden(true)
            Text(title)
                .font(Theme.sans(13, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(Theme.text)
        .fixedSize()
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().stroke(Theme.hairline))
        .contentShape(Capsule())
    }

    private var monthString: String {
        if let s = startDate {
            return PlacesDateParser.monthAbbreviation(from: s)
        }
        return String(localized: "EVENT")
    }

    private var dayString: String {
        if let s = startDate {
            return PlacesDateParser.dayNumber(from: s)
        }
        return "--"
    }

    private func generateICS() {
        // A calendar entry needs a start; without one the share button would export a wrong date.
        guard startDate != nil else {
            icsFileURL = nil
            return
        }
        icsFileURL = PlacesICSGenerator.createEventICS(
            title: title ?? String(localized: "Event"),
            start: startDate,
            end: endDate,
            location: location,
            description: description,
            url: url
        )
    }
}

// MARK: - 9. CountdownCard

/// Live countdown in days/hours/min/sec. Only the digits sit inside the TimelineView.
struct CountdownCard: View {
    let card: JSONValue

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var title: String? { card["title"]?.string.flatMap { $0.isEmpty ? nil : $0 } }
    private var emoji: String? { card["emoji"]?.string.flatMap { $0.isEmpty ? nil : $0 } }
    private var targetDate: Date? { PlacesDateParser.parse(card["target"]?.string) }

    var body: some View {
        CardContainer(title: "Countdown", symbol: "timer") {
            VStack(alignment: .leading, spacing: 14) {
                // Header with Emoji and Title
                HStack(spacing: 10) {
                    if let emoji {
                        Text(emoji)
                            .font(.system(size: 32))
                            .accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        let heading = title ?? String(localized: "Countdown")
                        Text(heading)
                            .font(Theme.sans(18, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                            .cardParagraph(heading)
                        if let targetDate {
                            Text(targetDate.formatted(date: .abbreviated, time: .shortened))
                                .font(Theme.sans(12))
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                }

                if let target = targetDate {
                    PlacesCountdownDigits(target: target, reduceMotion: reduceMotion)
                } else {
                    Text("Target date missing or invalid")
                        .font(Theme.sans(13))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
        }
    }
}

/// The ticking part of the countdown, with a smooth hand-off to "Completed".
private struct PlacesCountdownDigits: View {
    let target: Date
    let reduceMotion: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { context in
            let remaining = target.timeIntervalSince(context.date)
            let done = remaining <= 0
            ZStack {
                if done {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Theme.success)
                            .accessibilityHidden(true)
                        Text("Completed")
                            .font(Theme.sans(15, weight: .semibold))
                            .foregroundStyle(Theme.text)
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .background(Theme.elevated, in: Capsule())
                    .frame(maxWidth: .infinity)
                    .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
                } else {
                    let totalSec = cardSafeInt(min(remaining, 3.0e11)) ?? 0
                    HStack(spacing: 8) {
                        countdownBox(value: totalSec / 86400, label: "Days")
                        countdownBox(value: (totalSec % 86400) / 3600, label: "Hours")
                        countdownBox(value: (totalSec % 3600) / 60, label: "Min")
                        countdownBox(value: totalSec % 60, label: "Sec")
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(Duration.seconds(totalSec)
                        .formatted(.units(allowed: [.days, .hours, .minutes, .seconds], width: .wide))))
                    .accessibilityAddTraits(.updatesFrequently)
                    .transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : Animation.smooth(duration: 0.3), value: done)
        }
    }

    private func countdownBox(value: Int, label: LocalizedStringKey) -> some View {
        VStack(spacing: 4) {
            Text(value.formatted(.number.precision(.integerLength(2...)).grouping(.never)))
                .font(Theme.mono(24, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(reduceMotion ? .identity : .numericText())

            Text(label)
                .font(Theme.sans(11, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
                .textCase(.uppercase)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - 10. TimezonesCard

/// Live clocks for world cities with day/night icon and offset vs local.
/// Only each time text re-renders every second; the rest of the row refreshes once a minute.
struct TimezonesCard: View {
    let card: JSONValue

    private var items: [JSONValue] { card.objects("items") }

    var body: some View {
        CardContainer(title: "World Clocks", symbol: "globe") {
            VStack(spacing: 12) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    PlacesClockRow(
                        city: item["city"]?.string ?? "",
                        timeZoneID: item["timezone"]?.string ?? ""
                    )

                    if index < items.count - 1 {
                        Divider()
                            .overlay(Theme.hairline)
                    }
                }
            }
        }
    }
}

private struct PlacesClockRow: View {
    let city: String
    let timeZoneID: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var timeZone: TimeZone? {
        let id = timeZoneID.trimmingCharacters(in: .whitespacesAndNewlines)
        return TimeZone(identifier: id) ?? TimeZone(abbreviation: id)
    }

    private var displayCity: String {
        if !city.isEmpty { return city }
        if let last = timeZoneID.split(separator: "/").last { return last.replacingOccurrences(of: "_", with: " ") }
        return String(localized: "City")
    }

    var body: some View {
        TimelineView(.everyMinute) { context in
            let isDay = timeZone.map { hour(of: context.date, in: $0) }.map { $0 >= 6 && $0 < 18 }
            HStack(spacing: 12) {
                // Day / Night icon
                Image(systemName: (isDay ?? true) ? "sun.max.fill" : "moon.stars.fill")
                    .font(.system(size: 20))
                    .foregroundStyle((isDay ?? true) ? cardStarColor : Color(red: 0.55, green: 0.6, blue: 1.0))
                    .frame(width: 28)
                    .accessibilityHidden(true)

                // City & Offset
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayCity)
                        .font(Theme.sans(16, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(2)
                        .cardParagraph(displayCity)

                    Text(offsetText(at: context.date))
                        .font(Theme.sans(12))
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)

                // Live clock: the only per-second view
                if let timeZone {
                    TimelineView(.periodic(from: .now, by: 1.0)) { tick in
                        Text(clockString(tick.date, timeZone))
                            .font(Theme.mono(19, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .contentTransition(reduceMotion ? .identity : .numericText())
                    }
                    .fixedSize()
                } else {
                    Text("--:--")
                        .font(Theme.mono(19, weight: .bold))
                        .foregroundStyle(Theme.tertiaryText)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func hour(of date: Date, in zone: TimeZone) -> Int {
        var cal = Calendar.current
        cal.timeZone = zone
        return cal.component(.hour, from: date)
    }

    private func clockString(_ date: Date, _ zone: TimeZone) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .standard)
        style.timeZone = zone
        return date.formatted(style)
    }

    private func offsetText(at date: Date) -> String {
        guard let timeZone else { return String(localized: "Unknown time zone") }
        let diff = timeZone.secondsFromGMT(for: date) - TimeZone.current.secondsFromGMT(for: date)
        if diff == 0 { return String(localized: "Same time") }
        let span = Duration.seconds(abs(diff)).formatted(.units(allowed: [.hours, .minutes], width: .narrow))
        let sign = diff > 0 ? "+" : "-"
        return "\(sign)\(span) " + String(localized: "vs local")
    }
}

// MARK: - 11. CurrencyCard

/// Currency conversion card. The live rate (open.er-api.com) wins; the rate in the card is only a
/// fallback when the live fetch fails, and it is labelled as such.
struct CurrencyCard: View {
    let card: JSONValue

    @State private var fetchedRate: Double?
    @State private var isLoading = true
    @State private var fetchFailed = false

    private var fromCurrency: String { (card["from"]?.string ?? "USD").uppercased() }
    private var toCurrency: String { (card["to"]?.string ?? "EUR").uppercased() }
    private var amount: Double { cardSafeDouble(card["amount"]?.double) ?? 1.0 }
    private var modelRate: Double? {
        guard let r = cardSafeDouble(card["rate"]?.double), r > 0 else { return nil }
        return r
    }
    private var usingFallback: Bool { fetchedRate == nil && fetchFailed && modelRate != nil }
    private var rate: Double? {
        if let fetchedRate, fetchedRate > 0 { return fetchedRate }
        return fetchFailed ? modelRate : nil
    }
    private var dateText: String? {
        guard let raw = card["date"]?.string, !raw.isEmpty else { return nil }
        if let d = CardDates.parse(raw) { return d.formatted(date: .abbreviated, time: .omitted) }
        return raw
    }

    var body: some View {
        CardContainer(title: "Currency", symbol: "dollarsign.arrow.circlepath") {
            VStack(spacing: 16) {
                // Source Amount
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(formatNumber(amount))
                        .font(Theme.sans(22, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text(fromCurrency)
                        .font(Theme.sans(16, weight: .bold))
                        .foregroundStyle(Theme.secondaryText)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)

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
                        .accessibilityHidden(true)
                    Spacer()
                }

                // Converted Amount
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if let rate {
                        Text(formatNumber(amount * rate))
                            .font(Theme.sans(32, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .contentTransition(.numericText())
                    } else {
                        Text("--")
                            .font(Theme.sans(32, weight: .bold))
                            .foregroundStyle(Theme.tertiaryText)
                    }

                    Text(toCurrency)
                        .font(Theme.sans(20, weight: .bold))
                        .foregroundStyle(Theme.accent)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)

                Divider()
                    .overlay(Theme.hairline)

                // Exchange Rate & Date Pill
                HStack(alignment: .top) {
                    if let r = rate {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("1 \(fromCurrency) = \(formatRate(r)) \(toCurrency)")
                                .font(Theme.sans(13, weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(Theme.text)
                                .fixedSize(horizontal: false, vertical: true)

                            Text("1 \(toCurrency) = \(formatRate(1.0 / r)) \(fromCurrency)")
                                .font(Theme.sans(12))
                                .monospacedDigit()
                                .foregroundStyle(Theme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else if isLoading {
                        HStack(spacing: 6) {
                            ProgressView()
                                .tint(Theme.secondaryText)
                            Text("Fetching live rate...")
                                .font(Theme.sans(12))
                                .foregroundStyle(Theme.secondaryText)
                        }
                    } else {
                        Label("Rate unavailable", systemImage: "exclamationmark.triangle")
                            .font(Theme.sans(12))
                            .foregroundStyle(Theme.danger)
                    }

                    Spacer(minLength: 8)

                    Text(footnote)
                        .font(Theme.sans(12))
                        .foregroundStyle(Theme.tertiaryText)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .animation(.smooth(duration: 0.3), value: rate)
        .task(id: "\(fromCurrency)>\(toCurrency)") {
            await fetchRate()
        }
    }

    private var footnote: String {
        if usingFallback {
            return String(localized: "Live rate unavailable; rate from the assistant")
        }
        if fetchedRate != nil { return String(localized: "Live rate") }
        return dateText ?? ""
    }

    private func fetchRate() async {
        isLoading = true
        fetchFailed = false
        do {
            let r = try await PlacesCurrencyService.shared.fetchRate(from: fromCurrency, to: toCurrency)
            fetchedRate = r
            fetchFailed = (r == nil)
        } catch {
            fetchedRate = nil
            fetchFailed = true
        }
        isLoading = false
    }

    private func formatNumber(_ val: Double) -> String {
        guard val.isFinite else { return "--" }
        return val.formatted(.number.precision(.fractionLength(val.rounded() == val ? 0 : 2)))
    }

    private func formatRate(_ val: Double) -> String {
        guard val.isFinite else { return "--" }
        return val.formatted(.number.precision(.fractionLength(2...4)))
    }
}
