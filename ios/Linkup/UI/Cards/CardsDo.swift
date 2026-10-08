import SwiftUI
import UIKit
import SafariServices
import Contacts
import ContactsUI
import AVFoundation

// MARK: - RecipeCard

struct RecipeCard: View {
    let card: JSONValue

    @State private var checkedIngredients: Set<Int> = []
    @State private var isCookModePresented = false

    private var title: String { card["title"]?.string ?? "Recipe" }
    private var imageURL: String? { card["image"]?.string }
    private var time: String? { card["time"]?.string }
    private var servings: String? {
        card["servings"]?.string ?? (card["servings"]?.int.map { "\($0)" })
    }
    private var difficulty: String? { card["difficulty"]?.string }
    private var ingredients: [String] { card.strings("ingredients") }
    private var steps: [String] { card.strings("steps") }
    private var tips: [String] {
        let list = card.strings("tips")
        if !list.isEmpty { return list }
        if let tip = card["tips"]?.string, !tip.isEmpty { return [tip] }
        return []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Hero Image
            if let imageURL, !imageURL.isEmpty {
                DoRemoteImageView(urlString: imageURL, contentMode: .fill)
                    .frame(height: 180)
                    .frame(maxWidth: .infinity)
                    .clipped()
            }

            VStack(alignment: .leading, spacing: 14) {
                // Header Label
                Label("Recipe", systemImage: "fork.knife")
                    .font(Theme.sans(13, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .textCase(.uppercase)

                // Title
                Text(title)
                    .font(Theme.serif(20, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .cardTextDirection(title)

                // Chips Row: Time, Servings, Difficulty
                if time != nil || servings != nil || difficulty != nil {
                    HStack(spacing: 8) {
                        if let time {
                            chip(icon: "clock", text: time)
                        }
                        if let servings {
                            chip(icon: "person.2", text: servings.contains("serving") ? servings : "\(servings) servings")
                        }
                        if let difficulty {
                            chip(icon: "flame", text: difficulty)
                        }
                        Spacer(minLength: 0)
                    }
                }

                // Ingredients Section
                if !ingredients.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("INGREDIENTS")
                            .font(Theme.sans(12, weight: .semibold))
                            .foregroundStyle(Theme.secondaryText)
                            .tracking(0.5)

                        VStack(spacing: 6) {
                            ForEach(Array(ingredients.enumerated()), id: \.offset) { index, item in
                                let isChecked = checkedIngredients.contains(index)
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    withAnimation(.snappy) {
                                        if isChecked {
                                            checkedIngredients.remove(index)
                                        } else {
                                            checkedIngredients.insert(index)
                                        }
                                    }
                                } label: {
                                    HStack(alignment: .top, spacing: 10) {
                                        Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                                            .font(Theme.sans(16))
                                            .foregroundStyle(isChecked ? Theme.accent : Theme.secondaryText)
                                        Text(item)
                                            .font(Theme.sans(14))
                                            .foregroundStyle(isChecked ? Theme.secondaryText : Theme.text)
                                            .strikethrough(isChecked, color: Theme.secondaryText)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .multilineTextAlignment(.leading)
                                            .cardTextDirection(item)
                                    }
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 8)
                                    .frame(minHeight: 44)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(item)
                                .accessibilityValue(isChecked ? "Checked" : "Unchecked")
                            }
                        }
                        .padding(10)
                        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 12))
                    }
                }

                // Steps Section
                if !steps.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("STEPS")
                            .font(Theme.sans(12, weight: .semibold))
                            .foregroundStyle(Theme.secondaryText)
                            .tracking(0.5)

                        VStack(spacing: 8) {
                            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                                HStack(alignment: .top, spacing: 12) {
                                    Text("\(index + 1)")
                                        .font(Theme.sans(12, weight: .bold))
                                        .foregroundStyle(Theme.accent)
                                        .monospacedDigit()
                                        .frame(width: 24, height: 24)
                                        .background(Theme.surface, in: Circle())
                                        .overlay(Circle().stroke(Theme.hairline))

                                    Text(step)
                                        .font(Theme.sans(14))
                                        .foregroundStyle(Theme.text.opacity(0.95))
                                        .lineSpacing(3)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .cardTextDirection(step)
                                }
                                .padding(10)
                                .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }
                }

                // Tips Section
                if !tips.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(tips, id: \.self) { tip in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "lightbulb.fill")
                                    .font(Theme.sans(14))
                                    .foregroundStyle(Theme.accent)
                                Text(tip)
                                    .font(Theme.sans(13))
                                    .foregroundStyle(Theme.secondaryText)
                                    .lineSpacing(3)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .cardTextDirection(tip)
                            }
                        }
                    }
                    .padding(12)
                    .background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.accent.opacity(0.2)))
                }

                // Cook Mode Button
                if !steps.isEmpty {
                    Button {
                        isCookModePresented = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "flame.fill")
                                .font(Theme.sans(15))
                            Text("Cook Mode")
                                .font(Theme.sans(15, weight: .semibold))
                        }
                        .foregroundStyle(Theme.text)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .fullScreenCover(isPresented: $isCookModePresented) {
                        DoCookModeSheet(title: title, steps: steps)
                    }
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.hairline))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func chip(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(Theme.sans(11, weight: .medium))
            Text(text)
                .font(Theme.sans(12, weight: .medium))
        }
        .foregroundStyle(Theme.secondaryText)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Theme.elevated, in: Capsule())
    }
}

// MARK: - ChecklistCard

struct ChecklistCard: View {
    let card: JSONValue

    private var title: String { card["title"]?.string ?? "Checklist" }
    private var items: [DoChecklistItem] {
        let objects = card.objects("items")
        return objects.enumerated().map { idx, obj in
            DoChecklistItem(
                id: idx,
                text: obj["text"]?.string ?? "",
                initialDone: obj["done"]?.bool ?? false
            )
        }
    }

    private var storageKey: String {
        "checklist_\(card.prettyText.hashValue)"
    }

    var body: some View {
        DoChecklistContentView(
            card: card,
            title: title,
            items: items,
            storageKey: storageKey
        )
    }
}

// MARK: - StepsCard

struct StepsCard: View {
    let card: JSONValue

    private var title: String { card["title"]?.string ?? "How-To" }
    private var items: [JSONValue] { card.objects("items") }

    var body: some View {
        CardContainer(title: "Guide", symbol: "list.number") {
            VStack(alignment: .leading, spacing: 12) {
                if !title.isEmpty {
                    Text(title)
                        .font(Theme.sans(17, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .cardTextDirection(title)
                }

                VStack(spacing: 10) {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        let stepTitle = item["title"]?.string
                        let stepDetail = item["detail"]?.string
                        let stepImage = item["image"]?.string

                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top, spacing: 10) {
                                Text("\(index + 1)")
                                    .font(Theme.sans(12, weight: .bold))
                                    .foregroundStyle(Theme.accent)
                                    .monospacedDigit()
                                    .frame(width: 24, height: 24)
                                    .background(Theme.surface, in: Circle())
                                    .overlay(Circle().stroke(Theme.hairline))

                                if let stepTitle, !stepTitle.isEmpty {
                                    Text(stepTitle)
                                        .font(Theme.sans(15, weight: .semibold))
                                        .foregroundStyle(Theme.text)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .cardTextDirection(stepTitle)
                                }
                            }

                            if let stepDetail, !stepDetail.isEmpty {
                                Text(stepDetail)
                                    .font(Theme.sans(14))
                                    .foregroundStyle(Theme.secondaryText)
                                    .lineSpacing(3)
                                    .cardTextDirection(stepDetail)
                            }

                            if let stepImage, !stepImage.isEmpty {
                                DoRemoteImageView(urlString: stepImage, contentMode: .fill)
                                    .frame(height: 140)
                                    .frame(maxWidth: .infinity)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.hairline))
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline))
                    }
                }
            }
        }
    }
}

// MARK: - ProductCard

struct ProductCard: View {
    let card: JSONValue
    @State private var selectedImageIndex = 0
    @State private var isShowingSafari = false

    private var name: String { card["name"]?.string ?? "Product" }
    private var brand: String? { card["brand"]?.string }
    private var price: String? {
        if let p = card["price"]?.string { return p }
        if let d = cardSafeDouble(card["price"]?.double) { return d.formatted(.number.precision(.fractionLength(2))) }
        return nil
    }
    private var currency: String { card["currency"]?.string ?? "$" }
    private var formattedPrice: String? {
        guard let price else { return nil }
        if price.contains("$") || price.contains("€") || price.contains("£") || price.contains("¥") {
            return price
        }
        return "\(currency)\(price)"
    }
    private var rating: Double? { card["rating"]?.double }
    private var reviews: String? {
        card["reviews"]?.string ?? (card["reviews"]?.int.map { "\($0)" })
    }
    private var images: [String] {
        let imgs = card.strings("images")
        if !imgs.isEmpty { return imgs }
        if let single = card["image"]?.string, !single.isEmpty { return [single] }
        return []
    }
    private var specs: [String: JSONValue]? { card["specs"]?.object }
    private var summary: String? { card["summary"]?.string }
    private var productURL: URL? { card.url("url").flatMap { ["http", "https"].contains($0.scheme?.lowercased() ?? "") ? $0 : nil } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Image Carousel
            if !images.isEmpty {
                TabView(selection: $selectedImageIndex) {
                    ForEach(Array(images.enumerated()), id: \.offset) { index, imgURL in
                        DoRemoteImageView(urlString: imgURL, contentMode: .fill)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: images.count > 1 ? .always : .never))
                .frame(height: 200)
                .frame(maxWidth: .infinity)
                .clipped()
            }

            VStack(alignment: .leading, spacing: 12) {
                // Header / Brand
                HStack {
                    if let brand, !brand.isEmpty {
                        Text(brand.uppercased())
                            .font(Theme.sans(11, weight: .bold))
                            .foregroundStyle(Theme.secondaryText)
                            .tracking(1.0)
                    } else {
                        Label("Product", systemImage: "cart")
                            .font(Theme.sans(12, weight: .semibold))
                            .foregroundStyle(Theme.secondaryText)
                            .textCase(.uppercase)
                    }
                    Spacer()
                }

                // Name
                Text(name)
                    .font(Theme.sans(18, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                    .cardTextDirection(name)

                // Rating & Reviews
                if let rating {
                    HStack(spacing: 5) {
                        HStack(spacing: 2) {
                            ForEach(0..<5) { starIndex in
                                Image(systemName: Double(starIndex) < rating ? "star.fill" : "star")
                                    .font(Theme.sans(11))
                                    .foregroundStyle(Double(starIndex) < rating ? cardStarColor : Theme.tertiaryText)
                            }
                        }
                        Text(rating.formatted(.number.precision(.fractionLength(1))))
                            .font(Theme.sans(13, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .monospacedDigit()
                        if let reviews {
                            Text("(\(reviews) reviews)")
                                .font(Theme.sans(12))
                                .foregroundStyle(Theme.secondaryText)
                                .monospacedDigit()
                        }
                    }
                }

                // Price Big
                if let formattedPrice {
                    Text(formattedPrice)
                        .font(Theme.sans(24, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .monospacedDigit()
                }

                // Summary
                if let summary, !summary.isEmpty {
                    Text(summary)
                        .font(Theme.sans(14))
                        .foregroundStyle(Theme.secondaryText)
                        .cardTextDirection(summary)
                        .lineSpacing(3)
                }

                // Specs Grid
                if let specs, !specs.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("SPECIFICATIONS")
                            .font(Theme.sans(11, weight: .bold))
                            .foregroundStyle(Theme.secondaryText)
                            .tracking(0.8)

                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                            ForEach(Array(specs.keys.sorted()), id: \.self) { key in
                                if let val = specs[key]?.string {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(key)
                                            .font(Theme.sans(11))
                                            .foregroundStyle(Theme.secondaryText)
                                            .lineLimit(1)
                                        Text(val)
                                            .font(Theme.sans(13, weight: .medium))
                                            .foregroundStyle(Theme.text)
                                            .lineLimit(2)
                                    }
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 10))
                                }
                            }
                        }
                    }
                }

                // View Link Button
                if let productURL {
                    Button {
                        isShowingSafari = true
                    } label: {
                        HStack {
                            Text("View Product")
                                .font(Theme.sans(14, weight: .semibold))
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(Theme.sans(13, weight: .semibold))
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 44)
                        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(Theme.text)
                    }
                    .buttonStyle(.plain)
                    .sheet(isPresented: $isShowingSafari) {
                        DoSafariSheet(url: productURL)
                    }
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.hairline))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

// MARK: - CodeCard

struct CodeCard: View {
    let card: JSONValue

    private var language: String { card["language"]?.string ?? "" }
    private var title: String? { card["title"]?.string }
    private var code: String { card["code"]?.string ?? "" }
    private var explanation: String? { card["explanation"]?.string }

    var body: some View {
        CardContainer(title: "Code", symbol: "chevron.left.forwardslash.chevron.right") {
            VStack(alignment: .leading, spacing: 10) {
                if let title, !title.isEmpty {
                    Text(title)
                        .font(Theme.sans(16, weight: .semibold))
                        .foregroundStyle(Theme.text)
                }

                ChatCodeBlockView(language: language, code: code)

                if let explanation, !explanation.isEmpty {
                    Text(explanation)
                        .font(Theme.sans(14))
                        .foregroundStyle(Theme.secondaryText)
                        .lineSpacing(3)
                }
            }
        }
    }
}

// MARK: - ContactCard

struct ContactCard: View {
    let card: JSONValue
    @Environment(\.openURL) private var openURL
    @State private var isShowingSaveContact = false

    private var name: String { card["name"]?.string ?? "Contact" }
    private var role: String? { card["role"]?.string }
    private var company: String? { card["company"]?.string }
    private var phone: String? { card["phone"]?.string }
    private var email: String? { card["email"]?.string }
    private var website: String? { card["website"]?.string }
    private var address: String? { card["address"]?.string }
    private var photo: String? { card["photo"]?.string }

    private var roleCompanySubtitle: String? {
        if let role, let company { return "\(role) · \(company)" }
        return role ?? company
    }

    private var initials: String {
        let parts = name.split(separator: " ").map(String.init)
        if parts.count >= 2 {
            let first = parts[0].prefix(1)
            let second = parts[1].prefix(1)
            return "\(first)\(second)".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    var body: some View {
        CardContainer(title: "Contact", symbol: "person.crop.circle") {
            VStack(alignment: .leading, spacing: 14) {
                // Avatar + Name + Role
                HStack(spacing: 14) {
                    if let photo, !photo.isEmpty {
                        DoRemoteImageView(urlString: photo, contentMode: .fill)
                            .frame(width: 58, height: 58)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Theme.hairline))
                    } else {
                        Circle()
                            .fill(Theme.elevated)
                            .frame(width: 58, height: 58)
                            .overlay(
                                Text(initials.isEmpty ? "ID" : initials)
                                    .font(Theme.sans(18, weight: .bold))
                                    .foregroundStyle(Theme.text)
                            )
                            .overlay(Circle().stroke(Theme.hairline))
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(name)
                            .font(Theme.sans(17, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                            .cardTextDirection(name)

                        if let roleCompanySubtitle {
                            Text(roleCompanySubtitle)
                                .font(Theme.sans(13))
                                .foregroundStyle(Theme.secondaryText)
                                .lineLimit(1)
                                .cardTextDirection(roleCompanySubtitle)
                        }
                    }
                }

                // Action Buttons
                HStack(spacing: 10) {
                    if let phone {
                        let cleanDigits = phone.filter { "+0123456789".contains($0) }
                        if let telURL = URL(string: "tel:\(cleanDigits)") {
                            contactActionButton(icon: "phone.fill", label: "Call") {
                                openURL(telURL)
                            }
                        }
                    }

                    if let email, let mailURL = URL(string: "mailto:\(email)") {
                        contactActionButton(icon: "envelope.fill", label: "Email") {
                            openURL(mailURL)
                        }
                    }

                    if let website, let webURL = URL(string: website), ["http", "https"].contains(webURL.scheme?.lowercased() ?? "") {
                        contactActionButton(icon: "globe", label: "Web") {
                            openURL(webURL)
                        }
                    }

                    if let address, let mapsURL = cardMakeURL(scheme: "https", host: "maps.apple.com", queryItems: [URLQueryItem(name: "q", value: address)]) {
                        contactActionButton(icon: "map.fill", label: "Maps") {
                            openURL(mapsURL)
                        }
                    }
                }

                // Detail Rows
                VStack(spacing: 8) {
                    if let phone {
                        detailRow(icon: "phone", text: phone)
                    }
                    if let email {
                        detailRow(icon: "envelope", text: email)
                    }
                    if let address {
                        detailRow(icon: "mappin.and.ellipse", text: address)
                    }
                    if let website {
                        detailRow(icon: "link", text: website)
                    }
                }
                .padding(10)
                .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 12))

                // Save to Contacts
                Button {
                    isShowingSaveContact = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(Theme.sans(15))
                        Text("Save to Contacts")
                            .font(Theme.sans(14, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.hairline))
                    .foregroundStyle(Theme.text)
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $isShowingSaveContact) {
                    DoContactSheet(contact: makeContact(), isPresented: $isShowingSaveContact)
                }
            }
        }
    }

    private func contactActionButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(Theme.sans(14))
                Text(label)
                    .font(Theme.sans(10, weight: .medium))
            }
            .foregroundStyle(Theme.text)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func detailRow(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(Theme.sans(13))
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 20)
            Text(text)
                .font(Theme.sans(13))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .cardTextDirection(text)
            Spacer()
        }
    }

    private func makeContact() -> CNContact {
        let contact = CNMutableContact()
        let parts = name.split(separator: " ", maxSplits: 1).map(String.init)
        if parts.count == 2 {
            contact.givenName = parts[0]
            contact.familyName = parts[1]
        } else {
            contact.givenName = name
        }
        if let role { contact.jobTitle = role }
        if let company { contact.organizationName = company }
        if let phone {
            contact.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMain, value: CNPhoneNumber(stringValue: phone))]
        }
        if let email {
            contact.emailAddresses = [CNLabeledValue(label: CNLabelWork, value: email as NSString)]
        }
        if let website {
            contact.urlAddresses = [CNLabeledValue(label: CNLabelURLAddressHomePage, value: website as NSString)]
        }
        if let address {
            let postal = CNMutablePostalAddress()
            postal.street = address
            contact.postalAddresses = [CNLabeledValue(label: CNLabelWork, value: postal)]
        }
        return contact
    }
}

// MARK: - EmailCard

struct EmailCard: View {
    let card: JSONValue
    @Environment(\.openURL) private var openURL
    @State private var isCopied = false
    @State private var copyTask: Task<Void, Never>?

    private var to: String { card["to"]?.string ?? "" }
    private var subject: String { card["subject"]?.string ?? "" }
    private var bodyText: String { card["body"]?.string ?? "" }

    var body: some View {
        CardContainer(title: "Email Draft", symbol: "envelope") {
            VStack(alignment: .leading, spacing: 12) {
                // Email Preview Box
                VStack(alignment: .leading, spacing: 8) {
                    if !to.isEmpty {
                        HStack(spacing: 6) {
                            Text("To:")
                                .font(Theme.sans(13, weight: .medium))
                                .foregroundStyle(Theme.secondaryText)
                            Text(to)
                                .font(Theme.sans(13))
                                .foregroundStyle(Theme.text)
                        }
                    }

                    if !subject.isEmpty {
                        HStack(spacing: 6) {
                            Text("Subject:")
                                .font(Theme.sans(13, weight: .medium))
                                .foregroundStyle(Theme.secondaryText)
                            Text(subject)
                                .font(Theme.sans(13, weight: .semibold))
                                .foregroundStyle(Theme.text)
                                .cardTextDirection(subject)
                        }
                    }

                    if !to.isEmpty || !subject.isEmpty {
                        Divider().overlay(Theme.hairline)
                    }

                    if !bodyText.isEmpty {
                        Text(bodyText)
                            .font(Theme.sans(14))
                            .foregroundStyle(Theme.text.opacity(0.9))
                            .lineSpacing(3)
                            .textSelection(.enabled)
                            .cardTextDirection(bodyText)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 12))

                // Actions: Open in Mail + Copy
                HStack(spacing: 10) {
                    Button {
                        openInMail()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "envelope.fill")
                                .font(Theme.sans(13))
                            Text("Open in Mail")
                                .font(Theme.sans(14, weight: .semibold))
                        }
                        .foregroundStyle(Theme.text)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)

                    Button {
                        copyEmail()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: isCopied ? "checkmark" : "square.on.square")
                                .font(Theme.sans(13))
                            Text(isCopied ? "Copied" : "Copy")
                                .font(Theme.sans(14, weight: .medium))
                        }
                        .foregroundStyle(isCopied ? Theme.success : Theme.text)
                        .frame(width: 100)
                        .frame(height: 44)
                        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.hairline))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func openInMail() {
        var comp = URLComponents()
        comp.scheme = "mailto"
        comp.path = to
        var queryItems: [URLQueryItem] = []
        if !subject.isEmpty { queryItems.append(URLQueryItem(name: "subject", value: subject)) }
        if !bodyText.isEmpty { queryItems.append(URLQueryItem(name: "body", value: bodyText)) }
        if !queryItems.isEmpty { comp.queryItems = queryItems }
        if let url = comp.url {
            openURL(url)
        }
    }

    private func copyEmail() {
        var content = ""
        if !to.isEmpty { content += "To: \(to)\n" }
        if !subject.isEmpty { content += "Subject: \(subject)\n\n" }
        content += bodyText
        UIPasteboard.general.string = content.isEmpty ? bodyText : content
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        copyTask?.cancel()
        withAnimation(.snappy) { isCopied = true }
        copyTask = Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) { isCopied = false }
        }
    }
}

// MARK: - TranslationCard

struct TranslationCard: View {
    let card: JSONValue
    @State private var isCopied = false
    @State private var isSpeaking = false
    @State private var copyTask: Task<Void, Never>?
    @State private var speakTask: Task<Void, Never>?

    private var fromLang: String? { card["from"]?.string }
    private var toLang: String? { card["to"]?.string }
    private var source: String { card["source"]?.string ?? "" }
    private var result: String { card["result"]?.string ?? "" }
    private var pronunciation: String? { card["pronunciation"]?.string }
    private var notes: String? { card["notes"]?.string }

    var body: some View {
        CardContainer(title: "Translation", symbol: "character.bubble") {
            VStack(alignment: .leading, spacing: 14) {
                // Languages Header
                HStack(spacing: 8) {
                    Text(fromLang ?? "Original")
                        .font(Theme.sans(12, weight: .medium))
                        .foregroundStyle(Theme.secondaryText)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Theme.elevated, in: Capsule())

                    Image(systemName: "arrow.right")
                        .font(Theme.sans(11, weight: .bold))
                        .foregroundStyle(Theme.tertiaryText)

                    Text(toLang ?? "Translation")
                        .font(Theme.sans(12, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Theme.accent.opacity(0.15), in: Capsule())

                    Spacer()
                }

                // Source Box
                if !source.isEmpty {
                    Text(source)
                        .font(Theme.sans(15))
                        .foregroundStyle(Theme.secondaryText)
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        .cardTextDirection(source)
                }

                Divider().overlay(Theme.hairline)

                // Result Box
                VStack(alignment: .leading, spacing: 6) {
                    Text(result)
                        .font(Theme.serif(20, weight: .medium))
                        .foregroundStyle(Theme.text)
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .cardTextDirection(result)

                    if let pronunciation, !pronunciation.isEmpty {
                        Text(pronunciation)
                            .font(Theme.sans(13))
                            .italic()
                            .foregroundStyle(Theme.accent.opacity(0.9))
                    }

                    if let notes, !notes.isEmpty {
                        Text(notes)
                            .font(Theme.sans(12))
                            .foregroundStyle(Theme.tertiaryText)
                            .cardTextDirection(notes)
                    }
                }

                // Bottom Action Bar: Speak + Copy
                HStack(spacing: 10) {
                    Button {
                        speakResult()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: isSpeaking ? "speaker.wave.3.fill" : "speaker.wave.2.fill")
                                .font(Theme.sans(13))
                            Text("Speak")
                                .font(Theme.sans(13, weight: .medium))
                        }
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 14)
                        .frame(height: 44)
                        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)

                    Button {
                        copyResult()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: isCopied ? "checkmark" : "square.on.square")
                                .font(Theme.sans(13))
                            Text(isCopied ? "Copied" : "Copy")
                                .font(Theme.sans(13, weight: .medium))
                        }
                        .foregroundStyle(isCopied ? Theme.success : Theme.text)
                        .padding(.horizontal, 14)
                        .frame(height: 44)
                        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
            }
        }
    }

    private func speakResult() {
        guard !result.isEmpty else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        speakTask?.cancel()
        isSpeaking = true
        DoSpeechManager.shared.speak(text: result, languageCode: toLang)
        speakTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            isSpeaking = false
        }
    }

    private func copyResult() {
        guard !result.isEmpty else { return }
        UIPasteboard.general.string = result
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        copyTask?.cancel()
        withAnimation(.snappy) { isCopied = true }
        copyTask = Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) { isCopied = false }
        }
    }
}

// MARK: - MathCard

struct MathCard: View {
    let card: JSONValue

    private var expression: String? { card["expression"]?.string }
    private var result: String? { card["result"]?.string }
    private var steps: [String] { card.strings("steps") }

    var body: some View {
        CardContainer(title: "Math", symbol: "function") {
            VStack(alignment: .leading, spacing: 14) {
                // Expression & Result Card
                VStack(alignment: .leading, spacing: 8) {
                    if let expression, !expression.isEmpty {
                        Text(expression)
                            .font(Theme.mono(15))
                            .foregroundStyle(Theme.secondaryText)
                            .monospacedDigit()
                            .textSelection(.enabled)
                    }

                    if let result, !result.isEmpty {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("=")
                                .font(Theme.mono(22, weight: .light))
                                .foregroundStyle(Theme.accent)
                            Text(result)
                                .font(Theme.mono(24, weight: .bold))
                                .foregroundStyle(Theme.text)
                                .monospacedDigit()
                        }
                        .textSelection(.enabled)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 14))

                // Steps List
                if !steps.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("STEPS")
                            .font(Theme.sans(11, weight: .bold))
                            .foregroundStyle(Theme.secondaryText)
                            .tracking(0.8)

                        VStack(spacing: 6) {
                            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                                HStack(alignment: .top, spacing: 10) {
                                    Text("\(index + 1)")
                                        .font(Theme.mono(11, weight: .bold))
                                        .foregroundStyle(Theme.secondaryText)
                                        .monospacedDigit()
                                        .frame(width: 20, height: 20)
                                        .background(Theme.surface, in: Circle())
                                        .overlay(Circle().stroke(Theme.hairline))

                                    Text(step)
                                        .font(Theme.mono(13))
                                        .foregroundStyle(Theme.text.opacity(0.9))
                                        .lineSpacing(3)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .textSelection(.enabled)
                                        .cardTextDirection(step)
                                }
                                .padding(8)
                            }
                        }
                        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
    }
}

// MARK: - QuizCard

struct QuizCard: View {
    let card: JSONValue
    @Environment(\.cardActions) private var cardActions

    @State private var currentQuestionIndex = 0
    @State private var selectedOption: Int? = nil
    @State private var hasSubmitted = false
    @State private var score = 0
    @State private var isFinished = false
    @State private var hasSentScore = false

    private var title: String { card["title"]?.string ?? "Quiz" }
    private var questions: [JSONValue] { card.objects("questions") }

    var body: some View {
        CardContainer(title: "Quiz", symbol: "questionmark.circle") {
            VStack(alignment: .leading, spacing: 14) {
                if !title.isEmpty {
                    Text(title)
                        .font(Theme.sans(17, weight: .bold))
                        .foregroundStyle(Theme.text)
                }

                if questions.isEmpty {
                    Text("No questions available.")
                        .font(Theme.sans(14))
                        .foregroundStyle(Theme.secondaryText)
                } else if isFinished {
                    // Results View
                    VStack(spacing: 16) {
                        Image(systemName: score == questions.count ? "trophy.fill" : "star.fill")
                            .font(Theme.sans(42))
                            .foregroundStyle(Theme.accent)
                            .padding(.top, 8)

                        VStack(spacing: 4) {
                            Text("Quiz Complete!")
                                .font(Theme.sans(18, weight: .bold))
                                .foregroundStyle(Theme.text)

                            Text("You scored \(score) out of \(questions.count)")
                                .font(Theme.sans(15))
                                .foregroundStyle(Theme.secondaryText)
                        }

                        HStack(spacing: 12) {
                            Button {
                                sendScore()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: hasSentScore ? "checkmark" : "paperplane.fill")
                                    Text(hasSentScore ? "Score Sent" : "Send My Score")
                                }
                                .font(Theme.sans(14, weight: .semibold))
                                .foregroundStyle(Theme.text)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12))
                            }
                            .disabled(hasSentScore)
                            .buttonStyle(.plain)

                            Button {
                                restartQuiz()
                            } label: {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(Theme.sans(14, weight: .semibold))
                                    .foregroundStyle(Theme.text)
                                    .frame(width: 44, height: 44)
                                    .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Restart Quiz")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                } else {
                    // Active Question
                    let q = questions[currentQuestionIndex]
                    let qText = q["question"]?.string ?? ""
                    let options = q.strings("options")
                    let answerIdx = q["answer"]?.int ?? 0
                    let explanation = q["explanation"]?.string

                    VStack(alignment: .leading, spacing: 12) {
                        // Progress Counter
                        HStack {
                            Text("Question \(currentQuestionIndex + 1) of \(questions.count)")
                                .font(Theme.sans(12, weight: .medium))
                                .foregroundStyle(Theme.secondaryText)
                                .monospacedDigit()
                            Spacer()
                            Text("Score: \(score)")
                                .font(Theme.sans(12, weight: .semibold))
                                .foregroundStyle(Theme.accent)
                                .monospacedDigit()
                        }

                        Text(qText)
                            .font(Theme.sans(15, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .cardTextDirection(qText)

                        // Options
                        VStack(spacing: 8) {
                            ForEach(Array(options.enumerated()), id: \.offset) { optIndex, optText in
                                let isSelected = selectedOption == optIndex
                                let isCorrect = optIndex == answerIdx

                                Button {
                                    selectOption(optIndex, correctIndex: answerIdx)
                                } label: {
                                    HStack(spacing: 10) {
                                        if hasSubmitted {
                                            if isCorrect {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundStyle(Theme.success)
                                            } else if isSelected {
                                                Image(systemName: "xmark.circle.fill")
                                                    .foregroundStyle(Theme.danger)
                                            } else {
                                                Image(systemName: "circle")
                                                    .foregroundStyle(Theme.tertiaryText)
                                            }
                                        } else {
                                            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                                                .foregroundStyle(isSelected ? Theme.accent : Theme.secondaryText)
                                        }

                                        Text(optText)
                                            .font(Theme.sans(14))
                                            .foregroundStyle(hasSubmitted && !isCorrect && !isSelected ? Theme.tertiaryText : Theme.text)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .multilineTextAlignment(.leading)
                                            .cardTextDirection(optText)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .frame(minHeight: 44)
                                    .background(optionBackground(isSelected: isSelected, isCorrect: isCorrect))
                                    .overlay(optionBorder(isSelected: isSelected, isCorrect: isCorrect))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                                .disabled(hasSubmitted)
                                .buttonStyle(.plain)
                                .accessibilityLabel(optText)
                            }
                        }

                        // Explanation
                        if hasSubmitted, let explanation, !explanation.isEmpty {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "info.circle.fill")
                                    .font(Theme.sans(14))
                                    .foregroundStyle(Theme.accent)
                                Text(explanation)
                                    .font(Theme.sans(13))
                                    .foregroundStyle(Theme.secondaryText)
                                    .lineSpacing(3)
                                    .cardTextDirection(explanation)
                            }
                            .padding(10)
                            .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 10))
                        }

                        // Next Button
                        if hasSubmitted {
                            Button {
                                nextQuestion()
                            } label: {
                                HStack {
                                    Text(currentQuestionIndex < questions.count - 1 ? "Next Question" : "See Results")
                                    Image(systemName: "arrow.right")
                                }
                                .font(Theme.sans(14, weight: .semibold))
                                .foregroundStyle(Theme.text)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 4)
                        }
                    }
                }
            }
        }
    }

    private func selectOption(_ index: Int, correctIndex: Int) {
        guard !hasSubmitted else { return }
        selectedOption = index
        hasSubmitted = true
        if index == correctIndex {
            score += 1
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    private func nextQuestion() {
        if currentQuestionIndex < questions.count - 1 {
            withAnimation(.snappy) {
                currentQuestionIndex += 1
                selectedOption = nil
                hasSubmitted = false
            }
        } else {
            withAnimation(.snappy) {
                isFinished = true
            }
        }
    }

    private func restartQuiz() {
        withAnimation(.snappy) {
            currentQuestionIndex = 0
            selectedOption = nil
            hasSubmitted = false
            score = 0
            isFinished = false
            hasSentScore = false
        }
    }

    private func sendScore() {
        cardActions.send("I scored \(score)/\(questions.count) on '\(title)'!")
        hasSentScore = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func optionBackground(isSelected: Bool, isCorrect: Bool) -> Color {
        if !hasSubmitted {
            return isSelected ? Theme.elevated : Theme.surface
        }
        if isCorrect {
            return Theme.success.opacity(0.16)
        }
        if isSelected {
            return Theme.danger.opacity(0.16)
        }
        return Theme.surface
    }

    @ViewBuilder
    private func optionBorder(isSelected: Bool, isCorrect: Bool) -> some View {
        if !hasSubmitted {
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Theme.accent : Theme.hairline, lineWidth: 1)
        } else if isCorrect {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.success, lineWidth: 1)
        } else if isSelected {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.danger, lineWidth: 1)
        } else {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.hairline, lineWidth: 1)
        }
    }
}

// MARK: - PaletteCard

struct PaletteCard: View {
    let card: JSONValue
    @State private var copiedHex: String?

    private var title: String { card["title"]?.string ?? "Palette" }
    private var colors: [JSONValue] { card.objects("colors") }

    var body: some View {
        CardContainer(title: "Palette", symbol: "paintpalette") {
            VStack(alignment: .leading, spacing: 14) {
                if !title.isEmpty {
                    Text(title)
                        .font(Theme.sans(17, weight: .bold))
                        .foregroundStyle(Theme.text)
                }

                // Continuous gradient ribbon of all colors
                if !colors.isEmpty {
                    HStack(spacing: 0) {
                        ForEach(Array(colors.enumerated()), id: \.offset) { _, col in
                            let hex = col["hex"]?.string ?? "#FFFFFF"
                            Rectangle()
                                .fill(DoColorHelper.parseHex(hex) ?? Theme.elevated)
                        }
                    }
                    .frame(height: 14)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Theme.hairline))
                }

                // Swatches Grid
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(Array(colors.enumerated()), id: \.offset) { _, col in
                        let hex = col["hex"]?.string ?? "#000000"
                        let name = col["name"]?.string ?? hex
                        let color = DoColorHelper.parseHex(hex) ?? Theme.elevated
                        let isCopied = copiedHex == hex

                        Button {
                            copyColor(hex)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                // Color Block
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(color)
                                        .frame(height: 54)
                                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.hairline))

                                    if isCopied {
                                        HStack(spacing: 4) {
                                            Image(systemName: "checkmark")
                                                .font(Theme.sans(11, weight: .bold))
                                            Text("Copied")
                                                .font(Theme.sans(11, weight: .bold))
                                        }
                                        .foregroundStyle(Theme.text)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Theme.surface.opacity(0.85), in: Capsule())
                                        .transition(.scale.combined(with: .opacity))
                                    }
                                }

                                // Color Labels
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(name)
                                        .font(Theme.sans(13, weight: .medium))
                                        .foregroundStyle(Theme.text)
                                        .lineLimit(1)
                                    Text(hex.uppercased())
                                        .font(Theme.mono(11))
                                        .foregroundStyle(Theme.secondaryText)
                                }
                            }
                            .padding(8)
                            .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func copyColor(_ hex: String) {
        UIPasteboard.general.string = hex
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.snappy) {
            copiedHex = hex
        }
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if copiedHex == hex {
                withAnimation(.snappy) {
                    copiedHex = nil
                }
            }
        }
    }
}

// MARK: - LinkCard

struct LinkCard: View {
    let card: JSONValue
    @State private var isShowingSafari = false

    private var url: URL? { card.url("url").flatMap { ["http", "https"].contains($0.scheme?.lowercased() ?? "") ? $0 : nil } }
    private var title: String? { card["title"]?.string }
    private var description: String? { card["description"]?.string }
    private var imageURL: String? { card["image"]?.string }
    private var site: String? { card["site"]?.string ?? url?.host }

    var body: some View {
        CardContainer(title: "Link", symbol: "link") {
            Button {
                if url != nil {
                    isShowingSafari = true
                }
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    if let imageURL, !imageURL.isEmpty {
                        DoRemoteImageView(urlString: imageURL, contentMode: .fill)
                            .frame(height: 150)
                            .frame(maxWidth: .infinity)
                            .clipped()
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        if let site, !site.isEmpty {
                            HStack(spacing: 5) {
                                Image(systemName: "safari")
                                    .font(Theme.sans(11))
                                Text(site)
                                    .font(Theme.sans(12, weight: .medium))
                            }
                            .foregroundStyle(Theme.secondaryText)
                        }

                        if let title, !title.isEmpty {
                            Text(title)
                                .font(Theme.sans(16, weight: .semibold))
                                .foregroundStyle(Theme.text)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }

                        if let description, !description.isEmpty {
                            Text(description)
                                .font(Theme.sans(13))
                                .foregroundStyle(Theme.secondaryText)
                                .lineLimit(3)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    .padding(14)
                }
                .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $isShowingSafari) {
                if let url {
                    DoSafariSheet(url: url)
                }
            }
        }
    }
}

// MARK: - GalleryCard

struct GalleryCard: View {
    let card: JSONValue
    @State private var selectedItem: DoGalleryItem?

    private var title: String { card["title"]?.string ?? "Gallery" }
    private var items: [DoGalleryItem] { DoGalleryExtractor.extractItems(from: card) }

    var body: some View {
        CardContainer(title: "Gallery", symbol: "photo.stack") {
            VStack(alignment: .leading, spacing: 12) {
                if !title.isEmpty {
                    Text(title)
                        .font(Theme.sans(17, weight: .bold))
                        .foregroundStyle(Theme.text)
                }

                if !items.isEmpty {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        ForEach(items) { item in
                            Button {
                                selectedItem = item
                            } label: {
                                ZStack(alignment: .bottomLeading) {
                                    DoRemoteImageView(urlString: item.url, contentMode: .fill)
                                        .frame(height: 110)
                                        .frame(maxWidth: .infinity)
                                        .clipped()

                                    if let caption = item.caption, !caption.isEmpty {
                                        Text(caption)
                                            .font(Theme.sans(11))
                                            .foregroundStyle(Color.white)
                                            .lineLimit(1)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 3)
                                            .background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
                                            .padding(6)
                                    }
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.hairline))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .fullScreenCover(item: $selectedItem) { item in
            let initialIdx = items.firstIndex(of: item) ?? 0
            DoGalleryViewerSheet(images: items, initialIndex: initialIdx)
        }
    }
}

// MARK: - CalloutCard

struct CalloutCard: View {
    let card: JSONValue

    private var style: String { card["style"]?.string?.lowercased() ?? "info" }
    private var title: String? { card["title"]?.string }
    private var text: String { card["text"]?.string ?? "" }

    private var symbol: String {
        switch style {
        case "tip": return "lightbulb"
        case "warning": return "exclamationmark.triangle"
        case "success": return "checkmark.seal"
        case "error": return "xmark.octagon"
        default: return "info.circle"
        }
    }

    private var tintColor: Color {
        switch style {
        case "tip": return Theme.accent
        case "warning": return Color(red: 0.95, green: 0.72, blue: 0.3)
        case "success": return Theme.success
        case "error": return Theme.danger
        default: return Theme.link
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(Theme.sans(18, weight: .semibold))
                .foregroundStyle(tintColor)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                if let title, !title.isEmpty {
                    Text(title)
                        .font(Theme.sans(15, weight: .semibold))
                        .foregroundStyle(Theme.text)
                }

                if !text.isEmpty {
                    Text(text)
                        .font(Theme.sans(14))
                        .foregroundStyle(Theme.text.opacity(0.92))
                        .lineSpacing(3)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(tintColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(tintColor.opacity(0.28), lineWidth: 1))
    }
}

// MARK: - FileCard

struct FileCard: View {
    let card: JSONValue
    @Environment(UIState.self) private var ui

    private var name: String { card["name"]?.string ?? "File" }
    private var url: String { card["url"]?.string ?? "" }
    private var kind: String { card["kind"]?.string?.lowercased() ?? "file" }
    private var sizeText: String? {
        if let s = card["size"]?.string { return s }
        if let bytes = card["size"]?.int { return DoFormatHelper.formatBytes(bytes) }
        return nil
    }

    private var iconInfo: (symbol: String, color: Color) {
        switch kind {
        case "pdf":
            return ("doc.text.fill", Theme.danger)
        case "image", "png", "jpg", "jpeg", "webp", "gif":
            return ("photo.fill", Theme.link)
        case "code", "swift", "py", "python", "js", "ts", "json", "html", "css":
            return ("curlybraces", Theme.accent)
        case "archive", "zip", "tar", "gz", "rar":
            return ("archivebox.fill", Color(red: 0.75, green: 0.6, blue: 0.95))
        case "video", "mp4", "mov":
            return ("film.fill", Color(red: 0.5, green: 0.7, blue: 0.9))
        case "audio", "mp3", "wav", "m4a":
            return ("waveform", Theme.success)
        default:
            return ("doc.fill", Theme.secondaryText)
        }
    }

    var body: some View {
        CardContainer(title: "File", symbol: "doc") {
            Button {
                openFile()
            } label: {
                HStack(spacing: 12) {
                    // File Icon
                    RoundedRectangle(cornerRadius: 10)
                        .fill(iconInfo.color.opacity(0.16))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Image(systemName: iconInfo.symbol)
                                .font(Theme.sans(18))
                                .foregroundStyle(iconInfo.color)
                        )

                    // File Details
                    VStack(alignment: .leading, spacing: 3) {
                        Text(name)
                            .font(Theme.sans(15, weight: .medium))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)

                        HStack(spacing: 6) {
                            if let sizeText {
                                Text(sizeText)
                            }
                            if !kind.isEmpty && kind != "file" {
                                Text("·")
                                Text(kind.uppercased())
                            }
                        }
                        .font(Theme.sans(12))
                        .foregroundStyle(Theme.secondaryText)
                    }

                    Spacer()

                    Image(systemName: "arrow.up.forward.app")
                        .font(Theme.sans(14))
                        .foregroundStyle(Theme.secondaryText)
                }
                .padding(12)
                .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.hairline))
            }
            .buttonStyle(.plain)
        }
    }

    private func openFile() {
        guard !url.isEmpty else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        ui.openArtifact = ArtifactRef(
            id: url,
            kind: kind.isEmpty ? "file" : kind,
            title: name,
            url: url,
            path: nil,
            mime: nil,
            size: card["size"]?.int
        )
    }
}
