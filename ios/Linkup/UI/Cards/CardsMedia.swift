import SwiftUI

// MARK: - PersonCard

/// Person detail card: circular photo, role, born/died/nationality meta line, summary, and links.
struct PersonCard: View {
    let card: JSONValue

    @Environment(LinkupClient.self) private var client
    @State private var safariURL: MediaIdentifiableURL?

    var body: some View {
        let photoURL = mediaResolveURL(card["photo"]?.string, client: client)
        let name = card["name"]?.string ?? "Unknown"
        let role = card["role"]?.string
        let born = card["born"]?.string
        let died = card["died"]?.string
        let nationality = card["nationality"]?.string
        let summary = card["summary"]?.string
        let links = card.objects("links")

        let bornDied: String? = {
            if let born, let died { return "\(born) – \(died)" }
            if let born { return "b. \(born)" }
            if let died { return "d. \(died)" }
            return nil
        }()

        let metaItems = [bornDied, nationality].compactMap { $0 }
        let metaLine = metaItems.joined(separator: " · ")

        CardContainer(title: "Person", symbol: "person.crop.circle") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 14) {
                    MediaAsyncImage(url: photoURL, contentMode: .fill)
                        .frame(width: 76, height: 76)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Theme.hairline, lineWidth: 1))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(name)
                            .font(Theme.serif(20, weight: .bold))
                            .foregroundStyle(Theme.text)
                            .lineLimit(2)

                        if let role, !role.isEmpty {
                            Text(role)
                                .font(Theme.sans(14, weight: .medium))
                                .foregroundStyle(Theme.accent)
                                .lineLimit(1)
                        }

                        if !metaLine.isEmpty {
                            Text(metaLine)
                                .font(Theme.sans(13))
                                .foregroundStyle(Theme.secondaryText)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let summary, !summary.isEmpty {
                    MediaExpandableSummary(text: summary, lineLimit: 4)
                }

                if !links.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(links.enumerated()), id: \.offset) { _, link in
                                if let urlStr = link["url"]?.string,
                                   let url = mediaResolveURL(urlStr, client: client) {
                                    let title = link["title"]?.string ?? link["label"]?.string ?? "Link"
                                    Button {
                                        safariURL = MediaIdentifiableURL(url: url)
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: "arrow.up.right")
                                                .font(.system(size: 11, weight: .medium))
                                            Text(title)
                                                .font(Theme.sans(12, weight: .medium))
                                        }
                                        .foregroundStyle(Theme.text)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 7)
                                    }
                                    .glassEffect(.regular.interactive(), in: .capsule)
                                }
                            }
                        }
                    }
                }
            }
            .background(MediaBackdrop(url: photoURL))
        }
        .sheet(item: $safariURL) { item in
            MediaSafariView(url: item.url)
                .ignoresSafeArea()
        }
    }
}

// MARK: - BookCard

/// Book detail card: 2:3 cover, author, pages/year meta line, star rating, summary, and external link.
struct BookCard: View {
    let card: JSONValue

    @Environment(LinkupClient.self) private var client
    @State private var safariURL: MediaIdentifiableURL?

    var body: some View {
        let coverURL = mediaResolveURL(card["cover"]?.string, client: client)
        let title = card["title"]?.string ?? "Untitled"
        let author = card["author"]?.string
        let year = card["year"]?.string
        let pages = card["pages"]?.int.map { "\($0) pages" } ?? card["pages"]?.string
        let rating = card["rating"]?.double
        let summary = card["summary"]?.string
        let bookURL = mediaResolveURL(card["url"]?.string, client: client)

        let metaItems = [year, pages].compactMap { $0 }
        let metaLine = metaItems.joined(separator: " · ")

        CardContainer(title: "Book", symbol: "book.closed") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    MediaAsyncImage(url: coverURL, contentMode: .fill)
                        .frame(width: 76, height: 114)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.hairline, lineWidth: 1))

                    VStack(alignment: .leading, spacing: 5) {
                        Text(title)
                            .font(Theme.serif(20, weight: .bold))
                            .foregroundStyle(Theme.text)
                            .lineLimit(2)

                        if let author, !author.isEmpty {
                            Text(author)
                                .font(Theme.sans(14, weight: .medium))
                                .foregroundStyle(Theme.secondaryText)
                                .lineLimit(1)
                        }

                        if !metaLine.isEmpty {
                            Text(metaLine)
                                .font(Theme.sans(12))
                                .foregroundStyle(Theme.tertiaryText)
                                .lineLimit(1)
                        }

                        if let rating {
                            MediaRatingView(rating: rating)
                                .padding(.top, 2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let summary, !summary.isEmpty {
                    MediaExpandableSummary(text: summary, lineLimit: 4)
                }

                if let bookURL {
                    Button {
                        safariURL = MediaIdentifiableURL(url: bookURL)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 11, weight: .medium))
                            Text("Open Book")
                                .font(Theme.sans(12, weight: .medium))
                        }
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                    }
                    .glassEffect(.regular.interactive(), in: .capsule)
                }
            }
            .background(MediaBackdrop(url: coverURL))
        }
        .sheet(item: $safariURL) { item in
            MediaSafariView(url: item.url)
                .ignoresSafeArea()
        }
    }
}

// MARK: - MovieCard

/// Movie detail card: 2:3 poster, rating, runtime/director, genre chips, cast, summary, and trailer player.
struct MovieCard: View {
    let card: JSONValue

    @Environment(LinkupClient.self) private var client
    @State private var showTrailer = false

    var body: some View {
        let posterURL = mediaResolveURL(card["poster"]?.string, client: client)
        let title = card["title"]?.string ?? "Untitled Movie"
        let year = card["year"]?.string
        let rating = card["rating"]?.double
        let runtime = card["runtime"]?.string
        let genres = card.strings("genres")
        let director = card["director"]?.string
        let cast = card.strings("cast")
        let summary = card["summary"]?.string
        let trailerURL = card["trailer"]?.string

        let metaItems = [year, runtime, director.map { "Dir. \($0)" }].compactMap { $0 }
        let metaLine = metaItems.joined(separator: " · ")

        CardContainer(title: "Movie", symbol: "film") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    MediaAsyncImage(url: posterURL, contentMode: .fill)
                        .frame(width: 76, height: 114)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.hairline, lineWidth: 1))

                    VStack(alignment: .leading, spacing: 5) {
                        Text(title)
                            .font(Theme.serif(20, weight: .bold))
                            .foregroundStyle(Theme.text)
                            .lineLimit(2)

                        if !metaLine.isEmpty {
                            Text(metaLine)
                                .font(Theme.sans(12))
                                .foregroundStyle(Theme.secondaryText)
                                .lineLimit(1)
                        }

                        if let rating {
                            MediaRatingView(rating: rating)
                                .padding(.top, 2)
                        }

                        if !genres.isEmpty {
                            MediaGenreChips(genres: genres)
                                .padding(.top, 2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !cast.isEmpty {
                    Text("Cast: " + cast.joined(separator: ", "))
                        .font(Theme.sans(12))
                        .foregroundStyle(Theme.tertiaryText)
                        .lineLimit(2)
                }

                if let summary, !summary.isEmpty {
                    MediaExpandableSummary(text: summary, lineLimit: 4)
                }

                if let trailerURL, !trailerURL.isEmpty {
                    if showTrailer {
                        MediaInlineVideoView(urlString: trailerURL, onDismiss: {
                            withAnimation(.snappy(duration: 0.2)) {
                                showTrailer = false
                            }
                        })
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    } else {
                        Button {
                            withAnimation(.snappy(duration: 0.2)) {
                                showTrailer = true
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 11, weight: .medium))
                                Text("Watch Trailer")
                                    .font(Theme.sans(12, weight: .medium))
                            }
                            .foregroundStyle(Theme.text)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                        }
                        .glassEffect(.regular.interactive(), in: .capsule)
                    }
                }
            }
            .background(MediaBackdrop(url: posterURL))
        }
    }
}

// MARK: - TvshowCard

/// TV show detail card: 2:3 poster, years, seasons, network, genre chips, and summary.
struct TvshowCard: View {
    let card: JSONValue

    @Environment(LinkupClient.self) private var client

    var body: some View {
        let posterURL = mediaResolveURL(card["poster"]?.string, client: client)
        let title = card["title"]?.string ?? "Untitled TV Show"
        let years = card["years"]?.string ?? card["year"]?.string
        let rating = card["rating"]?.double
        let seasons: String? = {
            if let s = card["seasons"]?.int {
                return "\(s) \(s == 1 ? "season" : "seasons")"
            }
            return card["seasons"]?.string
        }()
        let network = card["network"]?.string
        let genres = card.strings("genres")
        let summary = card["summary"]?.string

        let metaItems = [years, seasons, network].compactMap { $0 }
        let metaLine = metaItems.joined(separator: " · ")

        CardContainer(title: "TV Show", symbol: "tv") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    MediaAsyncImage(url: posterURL, contentMode: .fill)
                        .frame(width: 76, height: 114)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.hairline, lineWidth: 1))

                    VStack(alignment: .leading, spacing: 5) {
                        Text(title)
                            .font(Theme.serif(20, weight: .bold))
                            .foregroundStyle(Theme.text)
                            .lineLimit(2)

                        if !metaLine.isEmpty {
                            Text(metaLine)
                                .font(Theme.sans(12))
                                .foregroundStyle(Theme.secondaryText)
                                .lineLimit(1)
                        }

                        if let rating {
                            MediaRatingView(rating: rating)
                                .padding(.top, 2)
                        }

                        if !genres.isEmpty {
                            MediaGenreChips(genres: genres)
                                .padding(.top, 2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let summary, !summary.isEmpty {
                    MediaExpandableSummary(text: summary, lineLimit: 4)
                }
            }
            .background(MediaBackdrop(url: posterURL))
        }
    }
}

// MARK: - MusicCard

/// Music track/album card: square artwork, artist, album, year, formatted duration, and listen link.
struct MusicCard: View {
    let card: JSONValue

    @Environment(LinkupClient.self) private var client
    @State private var safariURL: MediaIdentifiableURL?

    var body: some View {
        let artworkURL = mediaResolveURL(card["artwork"]?.string, client: client)
        let title = card["title"]?.string ?? "Untitled Track"
        let artist = card["artist"]?.string
        let album = card["album"]?.string
        let year = card["year"]?.string
        let durationFormatted = MediaFormatters.formatDuration(card["duration"])
        let musicURL = mediaResolveURL(card["url"]?.string, client: client)

        let metaItems = [album, year, durationFormatted].compactMap { $0 }
        let metaLine = metaItems.joined(separator: " · ")

        CardContainer(title: "Music", symbol: "music.note") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 14) {
                    MediaAsyncImage(url: artworkURL, contentMode: .fill)
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.hairline, lineWidth: 1))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(Theme.serif(20, weight: .bold))
                            .foregroundStyle(Theme.text)
                            .lineLimit(2)

                        if let artist, !artist.isEmpty {
                            Text(artist)
                                .font(Theme.sans(15, weight: .medium))
                                .foregroundStyle(Theme.accent)
                                .lineLimit(1)
                        }

                        if !metaLine.isEmpty {
                            Text(metaLine)
                                .font(Theme.sans(13))
                                .foregroundStyle(Theme.secondaryText)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let musicURL {
                    Button {
                        safariURL = MediaIdentifiableURL(url: musicURL)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 11, weight: .medium))
                            Text("Listen")
                                .font(Theme.sans(12, weight: .medium))
                        }
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                    }
                    .glassEffect(.regular.interactive(), in: .capsule)
                }
            }
            .background(MediaBackdrop(url: artworkURL))
        }
        .sheet(item: $safariURL) { item in
            MediaSafariView(url: item.url)
                .ignoresSafeArea()
        }
    }
}

// MARK: - VideoCard

/// Video card: 16:9 thumbnail with play glass circle, inline YouTube WKWebView / AVKit VideoPlayer, and metadata.
struct VideoCard: View {
    let card: JSONValue

    @Environment(LinkupClient.self) private var client
    @State private var isPlaying = false

    var body: some View {
        let title = card["title"]?.string ?? "Video"
        let videoURLString = card["url"]?.string ?? ""
        let channel = card["channel"]?.string
        let durationFormatted = MediaFormatters.formatDuration(card["duration"])

        let thumbnailURL: URL? = {
            if let customThumb = card["thumbnail"]?.string, !customThumb.isEmpty {
                return mediaResolveURL(customThumb, client: client)
            }
            if let ytID = MediaYouTubeParser.extractID(from: videoURLString) {
                return MediaYouTubeParser.fallbackThumbnail(for: ytID)
            }
            return nil
        }()

        CardContainer(title: "Video", symbol: "play.rectangle.fill") {
            VStack(alignment: .leading, spacing: 10) {
                if isPlaying && !videoURLString.isEmpty {
                    MediaInlineVideoView(urlString: videoURLString, onDismiss: {
                        withAnimation(.snappy(duration: 0.2)) {
                            isPlaying = false
                        }
                    })
                } else {
                    ZStack(alignment: .bottomTrailing) {
                        MediaAsyncImage(url: thumbnailURL, contentMode: .fill)
                            .aspectRatio(16/9, contentMode: .fit)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.hairline, lineWidth: 1))

                        if !videoURLString.isEmpty {
                            Button {
                                withAnimation(.snappy(duration: 0.2)) {
                                    isPlaying = true
                                }
                            } label: {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 26, weight: .bold))
                                    .foregroundStyle(Theme.text)
                                    .offset(x: 2)
                                    .frame(width: 64, height: 64)
                            }
                            .glassEffect(.regular.interactive(), in: .circle)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }

                        if let durationFormatted {
                            Text(durationFormatted)
                                .font(Theme.mono(11).weight(.medium))
                                .foregroundStyle(Color.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .padding(10)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if !videoURLString.isEmpty {
                            withAnimation(.snappy(duration: 0.2)) {
                                isPlaying = true
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(Theme.serif(18, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(2)

                    if let channel, !channel.isEmpty {
                        Text(channel)
                            .font(Theme.sans(13))
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(1)
                    }
                }
            }
        }
    }
}

// MARK: - PodcastCard

/// Podcast episode card: square artwork, show name, formatted duration/date, summary, and listen link.
struct PodcastCard: View {
    let card: JSONValue

    @Environment(LinkupClient.self) private var client
    @State private var safariURL: MediaIdentifiableURL?

    var body: some View {
        let artworkURL = mediaResolveURL(card["artwork"]?.string, client: client)
        let title = card["title"]?.string ?? "Untitled Episode"
        let show = card["show"]?.string
        let durationFormatted = MediaFormatters.formatDuration(card["duration"])
        let dateFormatted = MediaFormatters.formatDate(card["date"]?.string)
        let summary = card["summary"]?.string
        let podcastURL = mediaResolveURL(card["url"]?.string, client: client)

        let metaItems = [durationFormatted, dateFormatted].compactMap { $0 }
        let metaLine = metaItems.joined(separator: " · ")

        CardContainer(title: "Podcast", symbol: "waveform.and.mic") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 14) {
                    MediaAsyncImage(url: artworkURL, contentMode: .fill)
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.hairline, lineWidth: 1))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(Theme.serif(20, weight: .bold))
                            .foregroundStyle(Theme.text)
                            .lineLimit(2)

                        if let show, !show.isEmpty {
                            Text(show)
                                .font(Theme.sans(14, weight: .medium))
                                .foregroundStyle(Theme.accent)
                                .lineLimit(1)
                        }

                        if !metaLine.isEmpty {
                            Text(metaLine)
                                .font(Theme.sans(13))
                                .foregroundStyle(Theme.secondaryText)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let summary, !summary.isEmpty {
                    MediaExpandableSummary(text: summary, lineLimit: 4)
                }

                if let podcastURL {
                    Button {
                        safariURL = MediaIdentifiableURL(url: podcastURL)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 11, weight: .medium))
                            Text("Listen Episode")
                                .font(Theme.sans(12, weight: .medium))
                        }
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                    }
                    .glassEffect(.regular.interactive(), in: .capsule)
                }
            }
            .background(MediaBackdrop(url: artworkURL))
        }
        .sheet(item: $safariURL) { item in
            MediaSafariView(url: item.url)
                .ignoresSafeArea()
        }
    }
}

// MARK: - NewsCard

/// News list card: article rows with source, relative date, 2-line title, 2-line summary, 72x72 square image, and in-app Safari.
struct NewsCard: View {
    let card: JSONValue

    @Environment(LinkupClient.self) private var client
    @State private var safariURL: MediaIdentifiableURL?

    var body: some View {
        let title = card["title"]?.string ?? "News"
        let items = card.objects("items")

        CardContainer(title: title, symbol: "newspaper") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    let itemURL = mediaResolveURL(item["url"]?.string, client: client)
                    let itemTitle = item["title"]?.string ?? ""
                    let source = item["source"]?.string
                    let date = MediaFormatters.formatDate(item["date"]?.string)
                    let summary = item["summary"]?.string
                    let imageURL = mediaResolveURL(item["image"]?.string, client: client)

                    let metaItems = [source, date].compactMap { $0 }
                    let metaLine = metaItems.joined(separator: " · ")

                    Button {
                        if let itemURL {
                            safariURL = MediaIdentifiableURL(url: itemURL)
                        }
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                if !metaLine.isEmpty {
                                    Text(metaLine)
                                        .font(Theme.sans(12))
                                        .foregroundStyle(Theme.secondaryText)
                                        .lineLimit(1)
                                }

                                if !itemTitle.isEmpty {
                                    Text(itemTitle)
                                        .font(Theme.sans(15, weight: .semibold))
                                        .foregroundStyle(Theme.text)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                }

                                if let summary, !summary.isEmpty {
                                    Text(summary)
                                        .font(Theme.sans(13))
                                        .foregroundStyle(Theme.secondaryText)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            if let imageURL {
                                MediaAsyncImage(url: imageURL, contentMode: .fill)
                                    .frame(width: 72, height: 72)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.hairline, lineWidth: 1))
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if index < items.count - 1 {
                        Divider().overlay(Theme.hairline)
                    }
                }
            }
        }
        .sheet(item: $safariURL) { item in
            MediaSafariView(url: item.url)
                .ignoresSafeArea()
        }
    }
}

// MARK: - DefinitionCard

/// Dictionary definition card: term in serif 26, phonetic, italic part of speech, numbered meanings, and quoted examples.
struct DefinitionCard: View {
    let card: JSONValue

    var body: some View {
        let term = card["term"]?.string ?? ""
        let phonetic = card["phonetic"]?.string
        let partOfSpeech = card["partOfSpeech"]?.string
        let meanings = card.strings("meanings")
        let examples = card.strings("examples")
        let origin = card["origin"]?.string

        CardContainer(title: "Definition", symbol: "character.book.closed") {
            VStack(alignment: .leading, spacing: 12) {
                Text(term)
                    .font(Theme.serif(26, weight: .bold))
                    .foregroundStyle(Theme.text)

                if (phonetic?.isEmpty == false) || (partOfSpeech?.isEmpty == false) {
                    HStack(spacing: 8) {
                        if let phonetic, !phonetic.isEmpty {
                            Text(phonetic)
                                .font(Theme.sans(14))
                                .foregroundStyle(Theme.secondaryText)
                        }
                        if let pos = partOfSpeech, !pos.isEmpty {
                            Text(pos)
                                .font(Theme.serif(14, weight: .medium).italic())
                                .foregroundStyle(Theme.accent)
                        }
                    }
                }

                if !meanings.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(meanings.enumerated()), id: \.offset) { idx, meaning in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("\(idx + 1)")
                                    .font(Theme.sans(13, weight: .bold))
                                    .foregroundStyle(Theme.accent)
                                    .frame(width: 16, alignment: .trailing)
                                Text(meaning)
                                    .font(Theme.sans(14))
                                    .foregroundStyle(Theme.text)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }

                if !examples.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(examples.enumerated()), id: \.offset) { _, example in
                            HStack(alignment: .top, spacing: 4) {
                                Text("“")
                                    .font(Theme.serif(15, weight: .bold))
                                    .foregroundStyle(Theme.accent)
                                Text(example)
                                    .font(Theme.serif(13).italic())
                                    .foregroundStyle(Theme.secondaryText)
                                Text("”")
                                    .font(Theme.serif(15, weight: .bold))
                                    .foregroundStyle(Theme.accent)
                            }
                            .padding(.leading, 12)
                        }
                    }
                }

                if let origin, !origin.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("ORIGIN")
                            .font(Theme.sans(11, weight: .semibold))
                            .foregroundStyle(Theme.tertiaryText)
                        Text(origin)
                            .font(Theme.sans(13))
                            .foregroundStyle(Theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 4)
                }
            }
        }
    }
}

// MARK: - QuoteCard

/// Quotation card: large decorative accent quotation mark, serif text, and author/source attribution.
struct QuoteCard: View {
    let card: JSONValue

    var body: some View {
        let text = card["text"]?.string ?? ""
        let author = card["author"]?.string
        let source = card["source"]?.string

        CardContainer(title: "Quote", symbol: "quote.opening") {
            VStack(alignment: .leading, spacing: 10) {
                Text("“")
                    .font(Theme.serif(44, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .frame(height: 24, alignment: .leading)

                Text(text)
                    .font(Theme.serif(19, weight: .regular))
                    .foregroundStyle(Theme.text)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)

                if (author?.isEmpty == false) || (source?.isEmpty == false) {
                    VStack(alignment: .trailing, spacing: 2) {
                        if let author, !author.isEmpty {
                            Text("— " + author)
                                .font(Theme.sans(14, weight: .semibold))
                                .foregroundStyle(Theme.text)
                        }
                        if let source, !source.isEmpty {
                            Text(source)
                                .font(Theme.sans(12).italic())
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.top, 4)
                }
            }
        }
    }
}

// MARK: - WikiCard

/// Wikipedia card: full-bleed image header, title, summary, 2-column grid of facts, and "Read more" link.
struct WikiCard: View {
    let card: JSONValue

    @Environment(LinkupClient.self) private var client
    @State private var safariURL: MediaIdentifiableURL?

    var body: some View {
        let title = card["title"]?.string ?? "Wikipedia"
        let imageURL = mediaResolveURL(card["image"]?.string, client: client)
        let summary = card["summary"]?.string
        let facts = card.objects("facts")
        let wikiURL = mediaResolveURL(card["url"]?.string, client: client)

        VStack(alignment: .leading, spacing: 0) {
            if let imageURL {
                ZStack(alignment: .topLeading) {
                    MediaAsyncImage(url: imageURL, contentMode: .fill)
                        .frame(height: 180)
                        .frame(maxWidth: .infinity)
                        .clipped()

                    LinearGradient(
                        colors: [Color.clear, Theme.surface.opacity(0.6), Theme.surface],
                        startPoint: .center,
                        endPoint: .bottom
                    )

                    Label("Wikipedia", systemImage: "books.vertical.fill")
                        .font(Theme.sans(11, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .textCase(.uppercase)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .glassEffect(.regular.interactive(), in: .capsule)
                        .padding(12)
                }
            } else {
                Label("Wikipedia", systemImage: "books.vertical.fill")
                    .font(Theme.sans(13, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .textCase(.uppercase)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
            }

            VStack(alignment: .leading, spacing: 14) {
                Text(title)
                    .font(Theme.serif(22, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .padding(.top, imageURL == nil ? 0 : 2)

                if let summary, !summary.isEmpty {
                    MediaExpandableSummary(text: summary, lineLimit: 5)
                }

                if !facts.isEmpty {
                    LazyVGrid(columns: [GridItem(.flexible(), alignment: .top), GridItem(.flexible(), alignment: .top)], spacing: 8) {
                        ForEach(Array(facts.enumerated()), id: \.offset) { _, fact in
                            if let label = fact["label"]?.string, let value = fact["value"]?.string {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(label)
                                        .font(Theme.sans(11, weight: .semibold))
                                        .foregroundStyle(Theme.tertiaryText)
                                        .textCase(.uppercase)
                                    Text(value)
                                        .font(Theme.sans(13, weight: .medium))
                                        .foregroundStyle(Theme.text)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                        }
                    }
                }

                if let wikiURL {
                    Button {
                        safariURL = MediaIdentifiableURL(url: wikiURL)
                    } label: {
                        HStack(spacing: 6) {
                            Text("Read more on Wikipedia")
                                .font(Theme.sans(13, weight: .semibold))
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                    }
                    .glassEffect(.regular.interactive(), in: .capsule)
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.hairline))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .sheet(item: $safariURL) { item in
            MediaSafariView(url: item.url)
                .ignoresSafeArea()
        }
    }
}
