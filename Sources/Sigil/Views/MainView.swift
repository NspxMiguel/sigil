import AppKit
import SwiftUI

struct MainView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(Localization.self) private var text

    @State private var drives: [Drive] = []
    @State private var selectedDrive: Drive?
    @State private var catalog: CatalogState = .loading
    @State private var image: HeaderImage?
    @State private var busy = false
    @State private var confirming = false
    @State private var notice: String?

    private var canPatch: Bool { image != nil && selectedDrive != nil && !busy }

    var body: some View {
        ZStack {
            GradientBackground()

            ScrollView {
                VStack(spacing: 0) {
                    header
                    Spacer(minLength: 26)
                    catalogSection
                    Spacer(minLength: 18)
                    actions
                    Spacer(minLength: 26)
                    driveList
                }
                .padding(.horizontal, 40)
                .padding(.vertical, 36)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.never)
        }
        .frame(minWidth: 540, minHeight: 660)
        .overlay(alignment: .topTrailing) { languageMenu }
        .task {
            rescan()
            catalog = await HeaderCatalog.load()
        }
        .confirmationDialog(
            text(.confirmTitle),
            isPresented: $confirming,
            titleVisibility: .visible
        ) {
            Button(text(.confirmAction), role: .destructive, action: performWrite)
            Button(text(.cancel), role: .cancel) {}
        } message: {
            if let drive = selectedDrive, let image {
                Text("\(image.name) → \(drive.name) (\(drive.devicePath))\n\n\(text(.confirmBody))")
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 18) {
            SigilMark(active: busy)

            Text(text(.appName))
                .font(.system(size: 34, weight: .heavy))
                .tracking(-0.9)
                .foregroundStyle(Palette.primaryText(scheme))

            Text(text(.tagline))
                .font(.system(size: 17))
                .multilineTextAlignment(.center)
                .foregroundStyle(Palette.secondaryText(scheme))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Catalog

    @ViewBuilder
    private var catalogSection: some View {
        switch catalog {
        case .loading:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(text(.catalogLoading))
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.secondaryText(scheme))
            }

        case .ready(let entries) where entries.isEmpty:
            InfoPanel(
                title: text(.catalogEmptyTitle),
                message: text(.catalogEmptyBody)
            )

        case .ready(let entries):
            VStack(alignment: .leading, spacing: 0) {
                SectionLabel(text(.catalogSectionLabel))
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 { Hairline() }
                    catalogRow(entry)
                }
            }

        case .unreachable(let detail):
            VStack(spacing: 10) {
                InfoPanel(
                    title: text(.catalogOfflineTitle),
                    message: text(.catalogOfflineBody),
                    detail: detail
                )
                Button(text(.retry)) {
                    Task {
                        catalog = .loading
                        catalog = await HeaderCatalog.load()
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.accent(scheme))
            }
        }
    }

    private func catalogRow(_ entry: CatalogEntry) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Palette.primaryText(scheme))
                Text("\(entry.firmware) · \(entry.formattedSize)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Palette.tertiaryText(scheme))
            }
            Spacer()
            Button(text(.patchAction)) {
                Task { await fetch(entry) }
            }
            .buttonStyle(.plain)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Palette.accent(scheme))
            .disabled(busy)
        }
        .frame(minHeight: Palette.Size.touch)
    }

    // MARK: Actions

    private var actions: some View {
        VStack(spacing: 14) {
            if let image {
                HStack(spacing: 8) {
                    Text(text(.selectedImage))
                        .font(.system(size: 12, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(Palette.tertiaryText(scheme))
                    Text("\(image.name) · \(image.formattedSize)")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(Palette.secondaryText(scheme))
                }
            }

            GlassButton(
                title: busy ? text(.patchActionBusy) : text(.patchAction),
                prominent: true,
                enabled: canPatch
            ) {
                confirming = true
            }

            GlassButton(
                title: text(.chooseOwnImage),
                prominent: false,
                enabled: !busy
            ) {
                pickImage()
            }

            GlassButton(
                title: text(.contributeAction),
                prominent: false,
                enabled: selectedDrive != nil && !busy
            ) {
                Task { await capture() }
            }

            Text(text(.contributeSubtitle))
                .font(.system(size: 13))
                .multilineTextAlignment(.center)
                .foregroundStyle(Palette.tertiaryText(scheme))
                .fixedSize(horizontal: false, vertical: true)

            if let notice {
                Text(notice)
                    .font(.system(size: 13))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Palette.secondaryText(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Drives — a list is text, not a stack of cards

    private var driveList: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(text(.driveSectionLabel))

            if drives.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(text(.noDriveTitle))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Palette.secondaryText(scheme))
                    Text(text(.noDriveBody))
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.tertiaryText(scheme))
                    Button(text(.rescan), action: rescan)
                        .buttonStyle(.plain)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.accent(scheme))
                        .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(Array(drives.enumerated()), id: \.element.id) { index, drive in
                    if index > 0 { Hairline() }
                    driveRow(drive)
                }
                Text(text(.internalDriveExcluded))
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.tertiaryText(scheme))
                    .padding(.top, 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func driveRow(_ drive: Drive) -> some View {
        let selected = selectedDrive?.id == drive.id
        return Button {
            selectedDrive = selected ? nil : drive
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .strokeBorder(
                        selected ? Palette.accent(scheme) : Palette.hairline(scheme),
                        lineWidth: selected ? 5 : 1.5
                    )
                    .frame(width: 14, height: 14)

                VStack(alignment: .leading, spacing: 2) {
                    Text(drive.name)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Palette.primaryText(scheme))
                    Text(drive.devicePath)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Palette.tertiaryText(scheme))
                }
                Spacer()
                Text(drive.formattedSize)
                    .font(.system(size: 15, design: .monospaced))
                    .foregroundStyle(Palette.secondaryText(scheme))
            }
            .frame(minHeight: Palette.Size.touch)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    // MARK: Language

    private var languageMenu: some View {
        @Bindable var localization = text
        return Picker(text(.languageLabel), selection: $localization.language) {
            ForEach(Language.allCases) { language in
                Text(language.displayName).tag(language)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
        .padding(16)
    }

    // MARK: Behaviour

    private func rescan() {
        do {
            drives = try DriveScanner.scan()
            if let selected = selectedDrive, !drives.contains(where: { $0.id == selected.id }) {
                selectedDrive = nil
            }
        } catch {
            drives = []
            selectedDrive = nil
            notice = "\(error)"
        }
    }

    private func pickImage() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = text(.chooseOwnImagePrompt)

        guard panel.runModal() == .OK, let url = panel.url else { return }
        image = HeaderImage(url: url)
        notice = nil
    }

    private func fetch(_ entry: CatalogEntry) async {
        busy = true
        notice = nil
        defer { busy = false }
        do {
            image = try await HeaderCatalog.download(entry)
        } catch {
            notice = error.localizedDescription
        }
    }

    private func performWrite() {
        guard let image, let drive = selectedDrive else { return }
        busy = true
        notice = nil
        Task.detached {
            do {
                try PatchWriter.write(image: image, to: drive)
                await MainActor.run {
                    notice = text(.succeeded)
                    busy = false
                }
            } catch {
                await MainActor.run {
                    notice = error.localizedDescription
                    busy = false
                }
            }
        }
    }

    private func capture() async {
        guard let drive = selectedDrive else { return }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(drive.id)-header.img"
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        busy = true
        notice = nil
        defer { busy = false }
        do {
            try PatchWriter.capture(from: drive, bytes: 64 * 1024 * 1024, to: destination)
            let opened = ContributionMailer.compose(
                attaching: destination,
                drive: drive,
                language: text.language
            )
            notice = opened ? text(.mailOpened) : text(.mailUnavailable)
        } catch {
            notice = error.localizedDescription
        }
    }
}

// MARK: - Small pieces

private struct SectionLabel: View {
    @Environment(\.colorScheme) private var scheme
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .bold))
            .tracking(1.2)
            .foregroundStyle(Palette.tertiaryText(scheme))
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct Hairline: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Rectangle()
            .fill(Palette.hairline(scheme))
            .frame(height: 1)
    }
}

private struct InfoPanel: View {
    @Environment(\.colorScheme) private var scheme
    let title: String
    let message: String
    var detail: String?

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.primaryText(scheme).opacity(0.86))
            Text(message)
                .font(.system(size: 13))
                .multilineTextAlignment(.center)
                .foregroundStyle(Palette.secondaryText(scheme))
                .fixedSize(horizontal: false, vertical: true)
            if let detail {
                Text(detail)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Palette.tertiaryText(scheme))
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background {
            RoundedRectangle(cornerRadius: Palette.Radius.card, style: .continuous)
                .fill(Palette.glassFallback(scheme).opacity(0.5))
        }
        .overlay {
            RoundedRectangle(cornerRadius: Palette.Radius.card, style: .continuous)
                .strokeBorder(Palette.hairline(scheme), lineWidth: 1)
        }
    }
}
