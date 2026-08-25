import SwiftUI

/// The preferences window content — native, grouped, System-Settings-style tabs.
struct PreferencesView: View {
    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        TabView {
            GeneralTab(settings: settings)
                .tabItem { Label("Général", systemImage: "gearshape") }

            AppearanceTab(settings: settings)
                .tabItem { Label("Apparence", systemImage: "paintbrush") }

            ShortcutTab(settings: settings)
                .tabItem { Label("Raccourci", systemImage: "keyboard") }

            AboutTab()
                .tabItem { Label("À propos", systemImage: "info.circle") }
        }
        .frame(width: 540, height: 460)
    }
}

// MARK: - General

private struct GeneralTab: View {
    @ObservedObject var settings: AppSettings
    @State private var launchAtLogin = LoginItem.isEnabled

    var body: some View {
        Form {
            Section {
                Toggle("Ouvrir au démarrage", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        if !LoginItem.set(newValue) { launchAtLogin = LoginItem.isEnabled }
                    }
            } header: {
                Text("Démarrage")
            }

            Section {
                Toggle("Inclure toutes les fenêtres de tous les bureaux (Spaces)", isOn: $settings.allSpaces)
                Toggle("Inclure les fenêtres réduites", isOn: $settings.includeMinimized)
            } header: {
                Text("Fenêtres affichées")
            } footer: {
                Text("Désactive « tous les bureaux » pour ne voir que les fenêtres du bureau courant.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Appearance

private struct AppearanceTab: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Picker("Thème", selection: $settings.appearance) {
                    ForEach(AppearanceMode.allCases) { Text($0.label).tag($0) }
                }
                Picker("Taille des vignettes", selection: $settings.thumbnailSize) {
                    ForEach(ThumbnailSize.allCases) { Text($0.label).tag($0) }
                }
                Stepper(value: $settings.maxColumns, in: 3...10) {
                    HStack {
                        Text("Colonnes maximum")
                        Spacer()
                        Text("\(settings.maxColumns)").foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Overlay")
            }

            Section {
                Toggle("Afficher les titres des fenêtres", isOn: $settings.showTitles)
                Toggle("Animations", isOn: $settings.animations)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Shortcut

private struct ShortcutTab: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Picker("Touche maintenue", selection: $settings.modifier) {
                    ForEach(HoldModifier.allCases) { Text($0.label).tag($0) }
                }
                if let warning = settings.modifier.warning {
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                Picker("Comportement", selection: $settings.activationStyle) {
                    ForEach(ActivationStyle.allCases) { Text($0.label).tag($0) }
                }
            } header: {
                Text("Déclencheur")
            } footer: {
                Text(settings.activationStyle == .hold
                     ? "Maintiens la touche, appuie sur Tab pour parcourir, relâche pour basculer."
                     : "Tape la touche+Tab puis relâche : l'overlay reste. Tab/flèches pour parcourir, tape pour rechercher, Entrée ou clic pour valider, Échap pour annuler.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                shortcutRow("Suivant", keys: "⇥")
                shortcutRow("Précédent", keys: "⇧⇥")
                shortcutRow("Naviguer", keys: "← → ↑ ↓")
                shortcutRow("Valider", keys: "↩ / relâcher")
                shortcutRow("Annuler", keys: "⎋")
            } header: {
                Text("Pendant l'affichage")
            }
        }
        .formStyle(.grouped)
    }

    private func shortcutRow(_ title: String, keys: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(keys)
                .font(.system(.body, design: .rounded).weight(.medium))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - About

private struct AboutTab: View {
    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "Version \(v)"
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
                .padding(.top, 8)
            Text("AltTabber")
                .font(.system(size: 26, weight: .bold, design: .rounded))
            Text(version)
                .foregroundStyle(.secondary)
            Text("Sélecteur de fenêtres fluide pour macOS, façon Alt-Tab de Windows.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 360)
            Link("github.com/S7venz/macos-alttabber",
                 destination: URL(string: "https://github.com/S7venz/macos-alttabber")!)
                .font(.callout)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
