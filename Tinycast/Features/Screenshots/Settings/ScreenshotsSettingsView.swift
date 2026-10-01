import SwiftUI

struct ScreenshotsSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(ScreenshotsCoordinator.self) private var coordinator

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                Toggle(isOn: $settings.screenshotsEnabled) {
                    SettingsFeatureToggleLabel(
                        anchor: .screenshotsScreenshots, title: "Enable Screenshots",
                        subtitle: "Search and manage your screenshots.")
                }
            }
            .settingsAnchor(.screenshotsScreenshots)

            Section {
                ScreenshotColumnPicker(selection: $settings.screenshotColumns)
            }
            .settingsAnchor(.screenshotsAppearance)
            .settingsEnabled(settings.screenshotsEnabled)

            ScreenshotScopesSection()
                .settingsEnabled(settings.screenshotsEnabled)

            Section {
                Toggle(isOn: $settings.screenshotIncludeAllMedia) {
                    SettingsRowTitle(.screenshotsMedia, "Include All Media")
                    Text("Index all images and videos in the search folders.")
                }
            }
            .settingsAnchor(.screenshotsMedia)
            .settingsEnabled(settings.screenshotsEnabled)

            Section {
                Toggle(isOn: $settings.screenshotRecognizeText) {
                    SettingsRowTitle(.screenshotsText, "Text Recognition")
                    Text("Extract text on this Mac so you can search image contents.")
                }
                Picker(selection: $settings.screenshotRecognitionMode) {
                    ForEach(ScreenshotRecognitionMode.allCases) { mode in Text(mode.title).tag(mode) }
                } label: {
                    SettingsRowTitle(.screenshotsText, "Recognition Mode")
                    Text("Accurate mode uses more CPU resources.")
                }
                .settingsEnabled(settings.screenshotRecognizeText)
                Toggle(isOn: $settings.screenshotAllowCloudFiles) {
                    SettingsRowTitle(.screenshotsText, "Allow Text Recognition for Cloud Files")
                    Text("Download cloud-only images to extract their text.")
                }
                .settingsEnabled(settings.screenshotRecognizeText)
            }
            .settingsAnchor(.screenshotsText)
            .settingsEnabled(settings.screenshotsEnabled)

            Section {
                Picker(selection: Binding(
                    get: { settings.screenshotRetentionDays }, set: coordinator.setRetention)
                ) {
                    Text("Never").tag(0)
                    Text("1 Week").tag(7)
                    Text("1 Month").tag(30)
                    Text("3 Months").tag(90)
                    Text("1 Year").tag(365)
                } label: {
                    SettingsRowTitle(.screenshotsStorage, "Storage Duration")
                    Text("Move older original screenshots to Trash. Pinned files and other media are kept.")
                }
            }
            .settingsAnchor(.screenshotsStorage)
            .settingsEnabled(settings.screenshotsEnabled)

            FeatureCommandsSection(owner: .screenshots, anchor: .screenshotsCommands)
                .settingsEnabled(settings.screenshotsEnabled)
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.screenshots)
    }
}

private struct ScreenshotScopesSection: View {
    @Environment(AppSettings.self) private var settings
    @Environment(ScreenshotsCoordinator.self) private var coordinator
    private let home = FileManager.default.homeDirectoryForCurrentUser

    var body: some View {
        Section {
            ForEach(settings.screenshotScopes, id: \.self) { scope in
                SettingsScopeRow(
                    scope: FileSearchScope.abbreviate(scope, homeDirectory: home),
                    path: FileSearchScope.expand(scope, homeDirectory: home).path,
                    isMissing: false
                ) { settings.screenshotScopes.removeAll { $0 == scope } }
            }
            Button("Add Folder…", action: addFolders)
            if let problem = coordinator.store.problem {
                Text(problem).foregroundStyle(.secondary)
            }
        } header: {
            SettingsSectionHeader(.screenshotsScopes)
        } footer: {
            Text("Search these folders and their subfolders. New files appear automatically.")
        }
    }

    private func addFolders() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        NSApp.activate()
        guard panel.runModal() == .OK else { return }
        settings.screenshotScopes = FileSearchScope.normalize(
            settings.screenshotScopes + panel.urls.map(\.path), homeDirectory: home)
    }
}

private struct ScreenshotColumnPicker: View {
    @Binding var selection: Int

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            SettingsRowTitle(.screenshotsAppearance, "Column Count")
            HStack(spacing: Theme.Spacing.xl) {
                ForEach(3...6, id: \.self) { count in
                    Button { selection = count } label: {
                        VStack(spacing: Theme.Spacing.sm) {
                            ScreenshotColumnPreview(columns: count)
                                .stroke(Theme.Colors.border, style: StrokeStyle(
                                    lineWidth: Theme.Size.hairline, dash: [Theme.Spacing.xxs]))
                                .background(selection == count ? Theme.Colors.controlSurface : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                                    .strokeBorder(Theme.Colors.border, lineWidth: Theme.Size.hairline))
                                .frame(width: Theme.Size.screenshotSettingsGridPreview,
                                       height: Theme.Size.screenshotSettingsGridPreview)
                            Text(count, format: .number)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(count) columns")
                    .accessibilityAddTraits(selection == count ? .isSelected : [])
                }
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
    }
}

private struct ScreenshotColumnPreview: Shape {
    let columns: Int

    func path(in rect: CGRect) -> Path {
        Path { path in
            for index in 1..<columns {
                let fraction = CGFloat(index) / CGFloat(columns)
                path.move(to: CGPoint(x: rect.width * fraction, y: 0))
                path.addLine(to: CGPoint(x: rect.width * fraction, y: rect.height))
                path.move(to: CGPoint(x: 0, y: rect.height * fraction))
                path.addLine(to: CGPoint(x: rect.width, y: rect.height * fraction))
            }
        }
    }
}
