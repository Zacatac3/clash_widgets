import SwiftUI

struct NotificationSettingsPage: View {
    @EnvironmentObject private var dataService: DataService
    @AppStorage("globalAutoOpenClashOfClans") private var globalAutoOpenClashOfClans = false
    @AppStorage("globalNotificationOffsetMinutes") private var globalNotificationOffsetMinutes = 0

    var body: some View {
        Form {
            Section("Profile Notifications") {
                Toggle("Enable Notifications", isOn: notificationBinding(\.notificationsEnabled))
                    .tint(.accentColor)

                if dataService.notificationSettings.notificationsEnabled {
                    notificationCategoryToggle(title: "Builders", binding: notificationBinding(\.builderNotificationsEnabled))
                    notificationCategoryToggle(title: "Laboratory", binding: notificationBinding(\.labNotificationsEnabled))
                    notificationCategoryToggle(title: "Pet House", binding: notificationBinding(\.petNotificationsEnabled))
                    notificationCategoryToggle(title: "Builder Base", binding: notificationBinding(\.builderBaseNotificationsEnabled))
                    notificationCategoryToggle(title: "Helpers", binding: notificationBinding(\.helperNotificationsEnabled))
                    notificationCategoryToggle(title: "Clan War", binding: notificationBinding(\.clanWarNotificationsEnabled))
                } else {
                    Text("Allow alerts to be reminded when an upgrade finishes.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text("Notification preferences are saved per profile.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Global Notifications") {
                Toggle("Open Clash of Clans", isOn: $globalAutoOpenClashOfClans)
                    .tint(.accentColor)
                Text("Tapping a notification will redirect you to the Clash of Clans app.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Pre-notify (minutes before)")
                        Spacer()
                        Picker("", selection: $globalNotificationOffsetMinutes) {
                            ForEach(0...30, id: \.self) { minutes in
                                Text("\(minutes) min").tag(minutes)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    Text("Receive notifications X minutes before upgrades complete.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Notifications")
    }

    private func notificationBinding(_ keyPath: WritableKeyPath<NotificationSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { dataService.notificationSettings[keyPath: keyPath] },
            set: { dataService.notificationSettings[keyPath: keyPath] = $0 }
        )
    }

    @ViewBuilder
    private func notificationCategoryToggle(title: String, binding: Binding<Bool>) -> some View {
        Toggle(title, isOn: binding)
            .disabled(!dataService.notificationSettings.notificationsEnabled)
            .tint(.accentColor)
    }
}
