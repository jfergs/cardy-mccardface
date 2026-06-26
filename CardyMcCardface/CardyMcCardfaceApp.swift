import AppKit
import Foundation
import ServiceManagement
import SwiftUI

private enum CardyPaths {
    static let home = FileManager.default.homeDirectoryForCurrentUser.path
    static let supportDirectory = "\(home)/Library/Application Support/CardyMcCardface"
    static let configuration = "\(supportDirectory)/config.plist"
    static let status = "\(supportDirectory)/status.plist"
    static let log = "\(home)/Library/Logs/CardyMcCardface.log"
}

private enum OrganizationMode: String, CaseIterable {
    case daily
    case shoots

    var title: String {
        switch self {
        case .daily: return "One folder per day"
        case .shoots: return "Separate shoots within each day"
        }
    }
}

private enum DateFolderStyle: String, CaseIterable {
    case yearDate = "year-date"
    case dateOnly = "date-only"
    case nestedDate = "nested-date"

    var title: String {
        switch self {
        case .yearDate: return "Year / YYYY-MM-DD"
        case .dateOnly: return "YYYY-MM-DD"
        case .nestedDate: return "Year / Month / Day"
        }
    }
}

private enum ShootFolderStyle: String, CaseIterable {
    case timeVolume = "time-volume"
    case timeCamera = "time-camera"
    case timeOnly = "time-only"

    var title: String {
        switch self {
        case .timeVolume: return "Time + card name"
        case .timeCamera: return "Time + camera model"
        case .timeOnly: return "Time only"
        }
    }
}

private enum WorkflowPreset: String, CaseIterable {
    case personalPhoto = "personal-photo"
    case captureOne = "capture-one"
    case adobePhoto = "adobe-photo"
    case videoProduction = "video-production"
    case hybridProduction = "hybrid-production"
    case ingestVillage = "ingest-village"

    var title: String {
        switch self {
        case .personalPhoto: return "Personal Photo Archive"
        case .captureOne: return "Capture One Session"
        case .adobePhoto: return "Adobe Lightroom / Bridge"
        case .videoProduction: return "Premiere / Resolve Video"
        case .hybridProduction: return "Hybrid Photo + Video"
        case .ingestVillage: return "Ingest Village"
        }
    }
}

private enum MediaMode: String, CaseIterable {
    case photosOnly = "photos-only"
    case videosOnly = "videos-only"
    case photosAndVideos = "photos-and-videos"

    var title: String {
        switch self {
        case .photosOnly: return "Photos only"
        case .videosOnly: return "Video/audio only"
        case .photosAndVideos: return "Photos + video/audio"
        }
    }
}

private enum PostImportApplication: String, CaseIterable {
    case none
    case captureOne = "capture-one"
    case adobeBridge = "adobe-bridge"
    case lightroomClassic = "lightroom-classic"
    case premierePro = "premiere-pro"

    var title: String {
        switch self {
        case .none: return "Do not open an app"
        case .captureOne: return "Capture One"
        case .adobeBridge: return "Adobe Bridge"
        case .lightroomClassic: return "Adobe Lightroom Classic"
        case .premierePro: return "Adobe Premiere Pro"
        }
    }

    var bundleIdentifiers: [String] {
        switch self {
        case .none:
            return []
        case .captureOne:
            return [
                "com.captureone.captureone16",
                "com.captureone.captureone15",
                "com.phaseone.captureone",
            ]
        case .adobeBridge:
            return [
                "com.adobe.bridge",
            ]
        case .lightroomClassic:
            return [
                "com.adobe.LightroomClassicCC7",
                "com.adobe.LightroomClassic",
            ]
        case .premierePro:
            return [
                "com.adobe.PremierePro",
            ]
        }
    }

    var applicationNames: [String] {
        switch self {
        case .none:
            return []
        case .captureOne:
            return ["Capture One.app"]
        case .adobeBridge:
            return ["Adobe Bridge 2026.app", "Adobe Bridge 2025.app", "Adobe Bridge.app"]
        case .lightroomClassic:
            return [
                "Adobe Lightroom Classic.app",
                "Lightroom Classic.app",
            ]
        case .premierePro:
            return [
                "Adobe Premiere Pro 2026.app",
                "Adobe Premiere Pro 2025.app",
                "Adobe Premiere Pro.app",
            ]
        }
    }
}

private struct CardyConfiguration {
    var destinationRoot = "\(CardyPaths.home)/Pictures"
    var workflowPreset = WorkflowPreset.personalPhoto
    var mediaMode = MediaMode.photosOnly
    var organizationMode = OrganizationMode.daily
    var dateFolderStyle = DateFolderStyle.yearDate
    var shootFolderStyle = ShootFolderStyle.timeVolume
    var autoEject = true
    var checksumVerify = false
    var dryRun = true
    var notificationsEnabled = true
    var revealAfterImport = false
    var postImportApplication = PostImportApplication.none
    var minCardSizeGB = 0
    var ingestVillageMode = false
    var stationName = Host.current().localizedName ?? "CardyStation"
    var operatorName = ""
    var sharedStatusEnabled = false
    var sharedManifestEnabled = false
    var sharedLocksEnabled = false
    var preserveFullCardForVideo = false
    var minFreeSpaceGB = 0

    static func load() -> CardyConfiguration {
        guard
            let dictionary = NSDictionary(contentsOfFile: CardyPaths.configuration)
                as? [String: Any]
        else {
            return CardyConfiguration()
        }

        var configuration = CardyConfiguration()
        configuration.destinationRoot =
            dictionary["destinationRoot"] as? String ?? configuration.destinationRoot
        configuration.workflowPreset = WorkflowPreset(
            rawValue: dictionary["workflowPreset"] as? String ?? ""
        ) ?? configuration.workflowPreset
        configuration.mediaMode = MediaMode(
            rawValue: dictionary["mediaMode"] as? String ?? ""
        ) ?? configuration.mediaMode
        configuration.organizationMode = OrganizationMode(
            rawValue: dictionary["organizationMode"] as? String ?? ""
        ) ?? configuration.organizationMode
        configuration.dateFolderStyle = DateFolderStyle(
            rawValue: dictionary["dateFolderStyle"] as? String ?? ""
        ) ?? configuration.dateFolderStyle
        configuration.shootFolderStyle = ShootFolderStyle(
            rawValue: dictionary["shootFolderStyle"] as? String ?? ""
        ) ?? configuration.shootFolderStyle
        configuration.autoEject =
            dictionary["autoEject"] as? Bool ?? configuration.autoEject
        configuration.checksumVerify =
            dictionary["checksumVerify"] as? Bool ?? configuration.checksumVerify
        configuration.dryRun = dictionary["dryRun"] as? Bool ?? configuration.dryRun
        configuration.notificationsEnabled =
            dictionary["notificationsEnabled"] as? Bool
                ?? configuration.notificationsEnabled
        configuration.revealAfterImport =
            dictionary["revealAfterImport"] as? Bool
                ?? configuration.revealAfterImport
        configuration.postImportApplication = PostImportApplication(
            rawValue: dictionary["postImportApplication"] as? String ?? ""
        ) ?? configuration.postImportApplication
        configuration.minCardSizeGB =
            dictionary["minCardSizeGB"] as? Int ?? configuration.minCardSizeGB
        configuration.ingestVillageMode =
            dictionary["ingestVillageMode"] as? Bool ?? configuration.ingestVillageMode
        configuration.stationName =
            dictionary["stationName"] as? String ?? configuration.stationName
        configuration.operatorName =
            dictionary["operatorName"] as? String ?? configuration.operatorName
        configuration.sharedStatusEnabled =
            dictionary["sharedStatusEnabled"] as? Bool
                ?? configuration.sharedStatusEnabled
        configuration.sharedManifestEnabled =
            dictionary["sharedManifestEnabled"] as? Bool
                ?? configuration.sharedManifestEnabled
        configuration.sharedLocksEnabled =
            dictionary["sharedLocksEnabled"] as? Bool
                ?? configuration.sharedLocksEnabled
        configuration.preserveFullCardForVideo =
            dictionary["preserveFullCardForVideo"] as? Bool
                ?? configuration.preserveFullCardForVideo
        configuration.minFreeSpaceGB =
            dictionary["minFreeSpaceGB"] as? Int ?? configuration.minFreeSpaceGB
        return configuration
    }

    func save() throws {
        let dictionary: NSDictionary = [
            "destinationRoot": destinationRoot,
            "workflowPreset": workflowPreset.rawValue,
            "mediaMode": mediaMode.rawValue,
            "organizationMode": organizationMode.rawValue,
            "dateFolderStyle": dateFolderStyle.rawValue,
            "shootFolderStyle": shootFolderStyle.rawValue,
            "autoEject": autoEject,
            "checksumVerify": checksumVerify,
            "dryRun": dryRun,
            "notificationsEnabled": notificationsEnabled,
            "revealAfterImport": revealAfterImport,
            "postImportApplication": postImportApplication.rawValue,
            "minCardSizeGB": minCardSizeGB,
            "ingestVillageMode": ingestVillageMode,
            "stationName": stationName,
            "operatorName": operatorName,
            "sharedStatusEnabled": sharedStatusEnabled,
            "sharedManifestEnabled": sharedManifestEnabled,
            "sharedLocksEnabled": sharedLocksEnabled,
            "preserveFullCardForVideo": preserveFullCardForVideo,
            "minFreeSpaceGB": minFreeSpaceGB,
        ]

        try FileManager.default.createDirectory(
            atPath: CardyPaths.supportDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let temporary = "\(CardyPaths.configuration).tmp.\(ProcessInfo.processInfo.processIdentifier)"
        guard dictionary.write(toFile: temporary, atomically: true) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: temporary
        )
        if FileManager.default.fileExists(atPath: CardyPaths.configuration) {
            _ = try FileManager.default.replaceItemAt(
                URL(fileURLWithPath: CardyPaths.configuration),
                withItemAt: URL(fileURLWithPath: temporary),
                backupItemName: nil,
                options: []
            )
        } else {
            try FileManager.default.moveItem(
                atPath: temporary,
                toPath: CardyPaths.configuration
            )
        }
    }
}

@MainActor
private final class SettingsWindowController: NSWindowController {
    private let destinationField = NSTextField()
    private let presetPopup = NSPopUpButton()
    private let mediaModePopup = NSPopUpButton()
    private let postImportAppPopup = NSPopUpButton()
    private let organizationPopup = NSPopUpButton()
    private let datePopup = NSPopUpButton()
    private let shootPopup = NSPopUpButton()
    private let autoEjectButton = NSButton(checkboxWithTitle: "Eject after verified import", target: nil, action: nil)
    private let checksumButton = NSButton(checkboxWithTitle: "Checksum verification", target: nil, action: nil)
    private let dryRunButton = NSButton(checkboxWithTitle: "Dry run — do not copy files", target: nil, action: nil)
    private let notificationsButton = NSButton(checkboxWithTitle: "Show macOS notifications", target: nil, action: nil)
    private let revealAfterImportButton = NSButton(checkboxWithTitle: "Reveal destination after successful import", target: nil, action: nil)
    private let ingestVillageButton = NSButton(checkboxWithTitle: "Ingest Village mode", target: nil, action: nil)
    private let stationNameField = NSTextField()
    private let operatorNameField = NSTextField()
    private let sharedStatusButton = NSButton(checkboxWithTitle: "Write shared station status", target: nil, action: nil)
    private let sharedManifestButton = NSButton(checkboxWithTitle: "Write shared import manifests", target: nil, action: nil)
    private let sharedLocksButton = NSButton(checkboxWithTitle: "Use shared destination locks", target: nil, action: nil)
    private let preserveFullCardButton = NSButton(checkboxWithTitle: "Preserve full visible card structure for video", target: nil, action: nil)
    private let minimumSizeField = NSTextField()
    private let minimumFreeSpaceField = NSTextField()
    private let onSave: () -> Void

    init(onSave: @escaping () -> Void) {
        self.onSave = onSave
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 750),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Cardy McCardface Settings"
        window.center()
        super.init(window: window)
        buildInterface()
        loadConfiguration()
    }

    required init?(coder: NSCoder) {
        nil
    }

    private func buildInterface() {
        guard let content = window?.contentView else { return }

        let title = NSTextField(labelWithString: "Cardy McCardface")
        title.font = .boldSystemFont(ofSize: 22)

        let description = NSTextField(
            wrappingLabelWithString:
                "Choose where camera cards are imported and how shoots are organized."
        )
        description.textColor = .secondaryLabelColor

        destinationField.isEditable = false
        destinationField.lineBreakMode = .byTruncatingMiddle
        let chooseButton = NSButton(title: "Choose…", target: self, action: #selector(chooseDestination))
        let destinationRow = NSStackView(views: [destinationField, chooseButton])
        destinationRow.orientation = .horizontal
        destinationRow.spacing = 8
        destinationField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        presetPopup.addItems(withTitles: WorkflowPreset.allCases.map(\.title))
        mediaModePopup.addItems(withTitles: MediaMode.allCases.map(\.title))
        postImportAppPopup.addItems(withTitles: PostImportApplication.allCases.map(\.title))
        organizationPopup.addItems(withTitles: OrganizationMode.allCases.map(\.title))
        datePopup.addItems(withTitles: DateFolderStyle.allCases.map(\.title))
        shootPopup.addItems(withTitles: ShootFolderStyle.allCases.map(\.title))
        minimumSizeField.placeholderString = "0"
        minimumSizeField.alignment = .right
        minimumFreeSpaceField.placeholderString = "0"
        minimumFreeSpaceField.alignment = .right
        stationNameField.placeholderString = "Ingest-01"
        operatorNameField.placeholderString = "Optional"

        let form = NSGridView(views: [
            [NSTextField(labelWithString: "Destination"), destinationRow],
            [NSTextField(labelWithString: "Workflow preset"), presetPopup],
            [NSTextField(labelWithString: "Media"), mediaModePopup],
            [NSTextField(labelWithString: "Open app after import"), postImportAppPopup],
            [NSTextField(labelWithString: "Organization"), organizationPopup],
            [NSTextField(labelWithString: "Date folders"), datePopup],
            [NSTextField(labelWithString: "Shoot folders"), shootPopup],
            [NSTextField(labelWithString: "Minimum card size (GB)"), minimumSizeField],
            [NSTextField(labelWithString: "Minimum free space (GB)"), minimumFreeSpaceField],
            [NSTextField(labelWithString: "Station name"), stationNameField],
            [NSTextField(labelWithString: "Operator"), operatorNameField],
        ])
        form.rowSpacing = 12
        form.columnSpacing = 14
        form.column(at: 0).xPlacement = .trailing
        form.column(at: 1).xPlacement = .fill

        let options = NSStackView(views: [
            autoEjectButton,
            checksumButton,
            dryRunButton,
            notificationsButton,
            revealAfterImportButton,
            ingestVillageButton,
            sharedStatusButton,
            sharedManifestButton,
            sharedLocksButton,
            preserveFullCardButton,
        ])
        options.orientation = .vertical
        options.alignment = .leading
        options.spacing = 8

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        let saveButton = NSButton(title: "Save", target: self, action: #selector(save))
        saveButton.keyEquivalent = "\r"
        let buttons = NSStackView(views: [NSView(), cancelButton, saveButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8

        let stack = NSStackView(views: [title, description, form, options, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -24),
            form.widthAnchor.constraint(equalTo: stack.widthAnchor),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor),
            minimumSizeField.widthAnchor.constraint(equalToConstant: 90),
            minimumFreeSpaceField.widthAnchor.constraint(equalToConstant: 90),
        ])
    }

    private func loadConfiguration() {
        let configuration = CardyConfiguration.load()
        destinationField.stringValue = configuration.destinationRoot
        presetPopup.selectItem(withTitle: configuration.workflowPreset.title)
        mediaModePopup.selectItem(withTitle: configuration.mediaMode.title)
        postImportAppPopup.selectItem(withTitle: configuration.postImportApplication.title)
        organizationPopup.selectItem(withTitle: configuration.organizationMode.title)
        datePopup.selectItem(withTitle: configuration.dateFolderStyle.title)
        shootPopup.selectItem(withTitle: configuration.shootFolderStyle.title)
        autoEjectButton.state = configuration.autoEject ? .on : .off
        checksumButton.state = configuration.checksumVerify ? .on : .off
        dryRunButton.state = configuration.dryRun ? .on : .off
        notificationsButton.state = configuration.notificationsEnabled ? .on : .off
        revealAfterImportButton.state = configuration.revealAfterImport ? .on : .off
        minimumSizeField.integerValue = configuration.minCardSizeGB
        ingestVillageButton.state = configuration.ingestVillageMode ? .on : .off
        stationNameField.stringValue = configuration.stationName
        operatorNameField.stringValue = configuration.operatorName
        sharedStatusButton.state = configuration.sharedStatusEnabled ? .on : .off
        sharedManifestButton.state = configuration.sharedManifestEnabled ? .on : .off
        sharedLocksButton.state = configuration.sharedLocksEnabled ? .on : .off
        preserveFullCardButton.state = configuration.preserveFullCardForVideo ? .on : .off
        minimumFreeSpaceField.integerValue = configuration.minFreeSpaceGB
    }

    @objc private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.directoryURL = URL(fileURLWithPath: destinationField.stringValue)
        if panel.runModal() == .OK, let url = panel.url {
            destinationField.stringValue = url.path
        }
    }

    @objc private func save() {
        let minimumSize = minimumSizeField.integerValue
        let minimumFreeSpace = minimumFreeSpaceField.integerValue
        guard minimumSize >= 0 else {
            showError("Minimum card size must be zero or a positive whole number.")
            return
        }
        guard minimumFreeSpace >= 0 else {
            showError("Minimum free space must be zero or a positive whole number.")
            return
        }
        guard !destinationField.stringValue.isEmpty else {
            showError("Choose a destination folder.")
            return
        }
        guard !stationNameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showError("Station name cannot be empty.")
            return
        }

        var configuration = CardyConfiguration()
        configuration.destinationRoot = destinationField.stringValue
        configuration.workflowPreset =
            WorkflowPreset.allCases[presetPopup.indexOfSelectedItem]
        configuration.mediaMode =
            MediaMode.allCases[mediaModePopup.indexOfSelectedItem]
        configuration.postImportApplication =
            PostImportApplication.allCases[postImportAppPopup.indexOfSelectedItem]
        configuration.organizationMode =
            OrganizationMode.allCases[organizationPopup.indexOfSelectedItem]
        configuration.dateFolderStyle =
            DateFolderStyle.allCases[datePopup.indexOfSelectedItem]
        configuration.shootFolderStyle =
            ShootFolderStyle.allCases[shootPopup.indexOfSelectedItem]
        configuration.autoEject = autoEjectButton.state == .on
        configuration.checksumVerify = checksumButton.state == .on
        configuration.dryRun = dryRunButton.state == .on
        configuration.notificationsEnabled = notificationsButton.state == .on
        configuration.revealAfterImport = revealAfterImportButton.state == .on
        configuration.minCardSizeGB = minimumSize
        configuration.ingestVillageMode = ingestVillageButton.state == .on
        configuration.stationName =
            stationNameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        configuration.operatorName =
            operatorNameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        configuration.sharedStatusEnabled = sharedStatusButton.state == .on
        configuration.sharedManifestEnabled = sharedManifestButton.state == .on
        configuration.sharedLocksEnabled = sharedLocksButton.state == .on
        configuration.preserveFullCardForVideo = preserveFullCardButton.state == .on
        configuration.minFreeSpaceGB = minimumFreeSpace

        applyPresetDefaults(to: &configuration)

        if configuration.ingestVillageMode {
            configuration.organizationMode = .shoots
            configuration.autoEject = false
            configuration.checksumVerify = true
            configuration.sharedStatusEnabled = true
            configuration.sharedManifestEnabled = true
            configuration.sharedLocksEnabled = true
            configuration.revealAfterImport = false
            configuration.postImportApplication = .none
        }

        do {
            try configuration.save()
            window?.close()
            onSave()
        } catch {
            showError("Could not save settings: \(error.localizedDescription)")
        }
    }

    @objc private func cancel() {
        window?.close()
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Cardy McCardface"
        alert.informativeText = message
        alert.runModal()
    }

    private func applyPresetDefaults(to configuration: inout CardyConfiguration) {
        switch configuration.workflowPreset {
        case .personalPhoto:
            break
        case .captureOne:
            configuration.mediaMode = .photosOnly
            configuration.organizationMode = .shoots
            configuration.shootFolderStyle = .timeVolume
            configuration.postImportApplication = .captureOne
        case .adobePhoto:
            configuration.mediaMode = .photosOnly
            configuration.organizationMode = .shoots
            configuration.shootFolderStyle = .timeVolume
            configuration.postImportApplication = .adobeBridge
        case .videoProduction:
            configuration.mediaMode = .videosOnly
            configuration.organizationMode = .shoots
            configuration.shootFolderStyle = .timeVolume
            configuration.autoEject = false
            configuration.checksumVerify = true
            configuration.preserveFullCardForVideo = true
            configuration.revealAfterImport = false
            configuration.postImportApplication = .premierePro
        case .hybridProduction:
            configuration.mediaMode = .photosAndVideos
            configuration.organizationMode = .shoots
            configuration.shootFolderStyle = .timeVolume
            configuration.autoEject = false
            configuration.checksumVerify = true
            configuration.preserveFullCardForVideo = true
            configuration.revealAfterImport = false
            configuration.postImportApplication = .none
        case .ingestVillage:
            configuration.ingestVillageMode = true
            configuration.mediaMode = .photosAndVideos
            configuration.organizationMode = .shoots
            configuration.shootFolderStyle = .timeVolume
            configuration.autoEject = false
            configuration.checksumVerify = true
            configuration.sharedStatusEnabled = true
            configuration.sharedManifestEnabled = true
            configuration.sharedLocksEnabled = true
            configuration.preserveFullCardForVideo = true
            configuration.revealAfterImport = false
            configuration.postImportApplication = .none
        }
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    private var launchAtLoginItem: NSMenuItem?
    private var timer: Timer?
    private var importerProcess: Process?
    private var settingsController: SettingsWindowController?
    private var handledPostImportReports = Set<String>()
    @Published var menuStatusTitle = "Service active"
    @Published var menuDetail = "Waiting for a camera card"
    @Published var menuSymbol = "sdcard.fill"
    @Published var launchAtLoginEnabled = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--unregister-login") {
            try? SMAppService.mainApp.unregister()
            DispatchQueue.main.async {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        createApplicationMenu()
        registerForVolumeMounts()
        registerLoginItem()
        refreshStatus()

        timer = Timer.scheduledTimer(
            timeInterval: 1,
            target: self,
            selector: #selector(refreshStatus),
            userInfo: nil,
            repeats: true
        )

        if !FileManager.default.fileExists(atPath: CardyPaths.configuration) {
            showSettings()
        } else {
            runImporter(reason: "application launch")
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication
    ) -> Bool {
        false
    }

    private func createApplicationMenu() {
        let mainMenu = NSMenu()

        let applicationMenuItem = NSMenuItem()
        mainMenu.addItem(applicationMenuItem)
        let applicationMenu = NSMenu(title: "Cardy McCardface")
        applicationMenuItem.submenu = applicationMenu

        applicationMenu.addItem(
            withTitle: "About Cardy McCardface",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        applicationMenu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(showSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        applicationMenu.addItem(settingsItem)
        applicationMenu.addItem(.separator())

        applicationMenu.addItem(
            withTitle: "Hide Cardy McCardface",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        applicationMenu.addItem(
            withTitle: "Hide Others",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        ).keyEquivalentModifierMask = [.command, .option]
        applicationMenu.addItem(
            withTitle: "Show All",
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: ""
        )
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(
            withTitle: "Quit Cardy McCardface",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenuItem.submenu = windowMenu
        let settingsWindowItem = NSMenuItem(
            title: "Cardy McCardface Settings",
            action: #selector(showSettings),
            keyEquivalent: "0"
        )
        settingsWindowItem.target = self
        windowMenu.addItem(settingsWindowItem)

        NSApplication.shared.mainMenu = mainMenu
        NSApplication.shared.windowsMenu = windowMenu
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        showSettings()
        return true
    }

    private func registerForVolumeMounts() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(volumeMounted),
            name: NSWorkspace.didMountNotification,
            object: nil
        )
    }

    private func registerLoginItem() {
        do {
            if SMAppService.mainApp.status == .notRegistered {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("Cardy McCardface could not register as a login item: \(error)")
        }
        updateLoginItemState()
    }

    private func updateLoginItemState() {
        launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
        launchAtLoginItem?.state = launchAtLoginEnabled ? .on : .off
    }

    @objc func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            showAlert("Could not update the login item: \(error.localizedDescription)")
        }
        updateLoginItemState()
    }

    @objc private func volumeMounted(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.runImporter(reason: "volume mounted")
        }
    }

    private func runImporter(reason: String) {
        guard importerProcess == nil else { return }
        guard
            let script = Bundle.main.url(
                forResource: "photo_import",
                withExtension: "sh"
            )
        else {
            showAlert("The bundled importer script is missing.")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [script.path]
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.importerProcess = nil
                self?.refreshStatus()
                self?.handlePostImportApplication()
            }
        }
        do {
            try process.run()
            importerProcess = process
            NSLog("Cardy McCardface started importer: \(reason)")
        } catch {
            showAlert("Could not start the importer: \(error.localizedDescription)")
        }
    }

    private func dictionary(at path: String) -> [String: Any]? {
        NSDictionary(contentsOfFile: path) as? [String: Any]
    }

    @objc private func refreshStatus() {
        let status = dictionary(at: CardyPaths.status)
        let state = status?["state"] as? String ?? "active"
        let message = status?["message"] as? String
            ?? "Service active — waiting for a camera card"

        switch state {
        case "importing":
            menuSymbol = "arrow.down.circle.fill"
            menuStatusTitle = "Import running"
        case "error":
            menuSymbol = "exclamationmark.triangle.fill"
            menuStatusTitle = "Attention required"
        default:
            menuSymbol = "sdcard.fill"
            menuStatusTitle = "Service active"
        }
        menuDetail = message
        updateLoginItemState()
    }

    private func handlePostImportApplication() {
        guard let status = dictionary(at: CardyPaths.status) else { return }
        let state = status["state"] as? String ?? ""
        guard state == "active" else { return }
        guard
            let report = status["lastImportReport"] as? String,
            !report.isEmpty,
            FileManager.default.fileExists(atPath: report),
            !handledPostImportReports.contains(report)
        else {
            return
        }

        let configuration = CardyConfiguration.load()
        guard !configuration.ingestVillageMode else { return }
        let application = configuration.postImportApplication
        guard application != .none else { return }

        if openConfiguredApplication(application) {
            handledPostImportReports.insert(report)
        } else {
            NSLog("Cardy McCardface could not find post-import app: \(application.title)")
        }
    }

    private func openConfiguredApplication(_ application: PostImportApplication) -> Bool {
        for bundleIdentifier in application.bundleIdentifiers {
            if let appURL = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: bundleIdentifier
            ) {
                NSWorkspace.shared.openApplication(
                    at: appURL,
                    configuration: NSWorkspace.OpenConfiguration()
                )
                return true
            }
        }

        for name in application.applicationNames {
            let appURL = URL(fileURLWithPath: "/Applications").appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: appURL.path) {
                NSWorkspace.shared.openApplication(
                    at: appURL,
                    configuration: NSWorkspace.OpenConfiguration()
                )
                return true
            }
        }

        return false
    }

    @objc func showSettings() {
        if settingsController == nil {
            settingsController = SettingsWindowController { [weak self] in
                self?.refreshStatus()
                self?.runImporter(reason: "settings saved")
            }
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        settingsController?.showWindow(nil)
        settingsController?.window?.makeKeyAndOrderFront(nil)
    }

    @objc func scanNow() {
        runImporter(reason: "manual scan")
    }

    @objc func openLog() {
        FileManager.default.createFile(atPath: CardyPaths.log, contents: nil)
        NSWorkspace.shared.open(URL(fileURLWithPath: CardyPaths.log))
    }

    @objc func revealDestination() {
        let configuration = CardyConfiguration.load()
        NSWorkspace.shared.selectFile(
            nil,
            inFileViewerRootedAtPath: configuration.destinationRoot
        )
    }

    @objc func revealLastImport() {
        let status = dictionary(at: CardyPaths.status)
        let fallback = CardyConfiguration.load().destinationRoot
        let destination = status?["lastImportDestination"] as? String ?? fallback
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: destination)
    }

    @objc func openLastImportReport() {
        guard
            let status = dictionary(at: CardyPaths.status),
            let report = status["lastImportReport"] as? String,
            !report.isEmpty
        else {
            showAlert("No completed import report is available yet.")
            return
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: report))
    }

    @objc func openSharedStatusFolder() {
        let status = dictionary(at: CardyPaths.status)
        let configuration = CardyConfiguration.load()
        let statusPath = status?["sharedStatusDir"] as? String
        let folder = (statusPath?.isEmpty == false)
            ? statusPath!
            : "\(configuration.destinationRoot)/.cardy-status"
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folder)
    }

    @objc func openDashboard() {
        guard
            let script = Bundle.main.url(
                forResource: "dashboard",
                withExtension: "sh"
            )
        else {
            showAlert("The bundled dashboard generator is missing.")
            return
        }

        let configuration = CardyConfiguration.load()
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [script.path, configuration.destinationRoot]
        process.standardOutput = output

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                showAlert("Could not generate the dashboard.")
                return
            }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let path, !path.isEmpty else {
                showAlert("Dashboard generator did not return a file path.")
                return
            }
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        } catch {
            showAlert("Could not open dashboard: \(error.localizedDescription)")
        }
    }

    @objc func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func showAlert(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Cardy McCardface"
        alert.informativeText = message
        alert.runModal()
    }
}

@main
private struct CardyMcCardfaceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            Text(appDelegate.menuStatusTitle)
            Text(appDelegate.menuDetail)
            Divider()
            Button("Settings…") {
                appDelegate.showSettings()
            }
            Button("Scan Mounted Volumes") {
                appDelegate.scanNow()
            }
            Button("Open Import Log") {
                appDelegate.openLog()
            }
            Button("Reveal Destination") {
                appDelegate.revealDestination()
            }
            Button("Reveal Last Import") {
                appDelegate.revealLastImport()
            }
            Button("Open Last Import Report") {
                appDelegate.openLastImportReport()
            }
            Button("Open Shared Status Folder") {
                appDelegate.openSharedStatusFolder()
            }
            Button("Open Dashboard") {
                appDelegate.openDashboard()
            }
            Divider()
            Button(
                appDelegate.launchAtLoginEnabled
                    ? "✓ Launch at Login"
                    : "Launch at Login"
            ) {
                appDelegate.toggleLaunchAtLogin()
            }
            Divider()
            Button("Quit Cardy McCardface") {
                appDelegate.quit()
            }
        } label: {
            Label("Cardy", systemImage: appDelegate.menuSymbol)
        }

        Settings {
            EmptyView()
        }
    }
}
