// ThemeManager.swift
// Tracks the effective ColorPalette + TerminalTheme combination, reacting to
// PreferencesService changes and system appearance changes.

import SwiftUI
import AppKit
import Combine

@MainActor
public final class ThemeManager: ObservableObject {
    @Published public private(set) var palette: ColorPalette = .dark
    @Published public private(set) var terminalTheme: TerminalTheme = TerminalThemes.default

    private let pref: PreferencesService
    private var cancellables = Set<AnyCancellable>()

    public init(pref: PreferencesService) {
        self.pref = pref
        recompute()
        // Recompute when preferences change
        pref.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.recompute() }
            }
            .store(in: &cancellables)
        // Recompute when system appearance changes
        DistributedNotificationCenter.default()
            .publisher(for: Notification.Name("AppleInterfaceThemeChangedNotification"))
            .sink { [weak self] _ in self?.recompute() }
            .store(in: &cancellables)
    }

    private func recompute() {
        let isDark = Self.systemIsDark()
        palette = pref.currentPalette(systemDark: isDark)
        terminalTheme = pref.currentTerminalTheme
    }

    public static func systemIsDark() -> Bool {
        let app = NSApp ?? NSApplication.shared
        if app.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return true
        }
        return false
    }
}
