import SwiftUI
import UIKit

struct RemoteContentImageView: View {
    let reference: RemoteImage
    @State private var remoteImage: UIImage?
    // Extend this list when shipping additional bundled artwork.
    private let allowedAssets: Set<String> = ["extras/builder_potion", "extras/research_potion", "extras/pet_potion", "profile/gold_pass", "profile/free_pass", "changelog/home_example", "changelog/progress", "changelog/equipment"]
    var body: some View {
        Group {
            if reference.source == "bundle", allowedAssets.contains(reference.value), let image = UIImage(named: reference.value) {
                Image(uiImage: image).resizable().scaledToFit()
            } else if let remoteImage {
                Image(uiImage: remoteImage).resizable().scaledToFit()
            }
        }
        .frame(maxHeight: 420)
        .task(id: reference.value) {
            remoteImage = nil
            guard reference.source == "remote", let url = URL(string: reference.value),
                  let bytes = try? await RemoteImageCache.shared.data(for: url) else { return }
            remoteImage = UIImage(data: bytes)
        }
    }
}

struct RemoteArticleView: View {
    let presentation: RemotePresentation
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let image = presentation.image { RemoteContentImageView(reference: image) }
                Text(presentation.title).font(.title.bold())
                Text(presentation.summary)
                ForEach(Array(presentation.sections.enumerated()), id: \.offset) { _, section in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(section.title).font(.headline)
                        Text(section.body)
                        if let image = section.image { RemoteContentImageView(reference: image) }
                    }
                }
            }.frame(maxWidth: 700, alignment: .leading).padding().frame(maxWidth: .infinity)
        }
        .navigationTitle(presentation.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct RemoteNewsSheet: View {
    let item: RemoteNews
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            RemoteArticleView(presentation: item.presentation)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.onAppear { RemoteContentService.shared.markSeen(item) }
    }
}

struct RemoteEventDetailView: View {
    let event: RemoteEvent
    @ObservedObject private var content = RemoteContentService.shared
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if content.now >= event.end {
                    Text("Event ended")
                } else {
                    Text(content.now < event.start ? "Starts in" : "Ends in")
                    Text(content.now < event.start ? event.start : event.end, style: .timer).monospacedDigit()
                }
            }.font(.subheadline).padding()
            RemoteArticleView(presentation: event.presentation)
        }
    }
}

struct RemoteNewsListView: View {
    @ObservedObject private var content = RemoteContentService.shared
    var body: some View {
        List {
            Section("News") {
                ForEach(content.news.filter { $0.published <= content.now }) { item in
                    NavigationLink { RemoteArticleView(presentation: item.presentation).onAppear { content.markSeen(item) } } label: {
                        VStack(alignment: .leading) {
                            Text(item.presentation.title).font(.headline)
                            Text(item.published, style: .date).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if !content.news.contains(where: { $0.published <= content.now }) { Text("No news yet.").foregroundStyle(.secondary) }
            }
            if let error = content.lastError { Section { Text(error).font(.caption).foregroundStyle(.secondary) } }
        }
        .refreshable { await content.refreshIfNeeded(force: true) }
    }
}
