import SwiftUI
import UIKit

struct RemoteContentImageView: View {
    let reference: RemoteImage
    var fallbackSystemImage: String? = nil
    @State private var remoteImage: UIImage?
    var body: some View {
        Group {
            if reference.source == "bundle", let image = UIImage(named: reference.value) {
                Image(uiImage: image).resizable().scaledToFit()
            } else if let remoteImage {
                Image(uiImage: remoteImage).resizable().scaledToFit()
            } else if let fallbackSystemImage {
                Image(systemName: fallbackSystemImage)
                    .resizable().scaledToFit().foregroundStyle(.secondary)
            } else if reference.source == "remote" {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 80)
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
        let currentEvent = content.currentEvent(id: event.id)
        VStack(spacing: 0) {
            Group {
                if let currentEvent {
                    RemoteEventCountdownView(event: currentEvent)
                } else {
                    Text("Event ended")
                }
            }.font(.subheadline).padding()
            RemoteArticleView(presentation: currentEvent?.presentation ?? event.presentation)
        }
    }
}

struct RemoteEventCountdownView: View {
    let event: RemoteEvent

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack {
                if context.date >= event.end {
                    Text("Event ended")
                } else {
                    Text(context.date < event.start ? "Starts in" : "Ends in")
                    Text(remoteEventCountdown(until: context.date < event.start ? event.start : event.end,
                                              at: context.date)).monospacedDigit()
                }
            }
        }
    }
}

struct RemoteNewsListView: View {
    @ObservedObject private var content = RemoteContentService.shared
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("News").font(.headline)
                ForEach(content.news.filter { $0.published <= content.now }) { item in
                    NavigationLink { RemoteArticleView(presentation: item.presentation).onAppear { content.markSeen(item) } } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.presentation.title).font(.headline)
                            Text(item.published, style: .date).font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
                if !content.news.contains(where: { $0.published <= content.now }) {
                    Text("No news yet.").foregroundStyle(.secondary)
                }
                if let error = content.lastError { Text(error).font(.caption).foregroundStyle(.secondary) }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(.systemGroupedBackground))
        .refreshable { await content.refreshIfNeeded(force: true) }
    }
}
