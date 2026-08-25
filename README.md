# AltTabber

Un sélecteur de **fenêtres** natif pour macOS (Apple Silicon), façon Alt-Tab de Windows :
overlay HUD flou, vignettes live de chaque fenêtre, navigation fluide, barre de
recherche, et un panneau de réglages complet.

Contrairement au ⌘⇥ système (qui bascule entre *applications*), AltTabber bascule entre
**toutes les fenêtres ouvertes** — y compris réduites, sur d'autres bureaux (Spaces),
et masquées derrière d'autres. Comme Windows.

![macOS](https://img.shields.io/badge/macOS-14%2B-black) ![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange) ![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-arm64-blue)

## Fonctionnalités

- **Toutes les fenêtres** — visibles, réduites, autres Spaces, masquées (via l'API Accessibilité)
- **Vignettes live** capturées via ScreenCaptureKit, en parallèle, affichées au fil de l'eau
- **Deux modes d'activation**
  - *Maintenir* (façon Windows) : tu tiens la touche, Tab pour parcourir, relâche pour basculer
  - *Rester ouvert* : tu tapes touche+Tab et relâches — l'overlay reste, tu navigues tranquille
- **Barre de recherche** : tape pour filtrer les fenêtres par titre / app
- **Souris** : survole pour surligner, clique pour basculer
- **Panneau de réglages** complet (thème, taille des vignettes, colonnes, raccourci, etc.)
- **Ouvrir au démarrage** (via `SMAppService`)
- App *agent* : pas d'icône Dock, vit dans la barre de menus

## Utilisation

| Geste | Action |
|---|---|
| **⌥ + Tab** | Ouvre / avance |
| **⌥ + Maj + Tab** | Recule |
| **Flèches** ← → ↑ ↓ | Naviguer la grille |
| **Taper du texte** | Rechercher par titre (mode *Rester ouvert*) |
| **Entrée** ou **clic** | Basculer vers la fenêtre |
| **Relâcher ⌥** | Basculer (mode *Maintenir*) |
| **Échap** | Annuler |

La touche est configurable (⌥ Option, ⌘ Command, ⌃ Control) dans les réglages.
Le ⌘⇥ système reste intact tant que tu gardes le modificateur par défaut (Option).

## Build

```bash
./build.sh          # release + bundle .app signé
./build.sh debug    # build plus rapide
```

Résultat : `build/AltTabber.app`.

### Signature & permissions stables

`build.sh` choisit automatiquement, dans l'ordre :

1. une **identité valide** (ton certificat *Apple Development* s'il existe) — recommandé
2. le certificat local **AltTabber Self-Signed** (créé par `./make-identity.sh`)
3. **ad-hoc** (les permissions macOS se réinitialisent à chaque rebuild)

Une identité stable (1 ou 2) fait que macOS **garde** les autorisations
Accessibilité / Enregistrement de l'écran d'un build à l'autre. Sans ça, tu dois
les ré-accorder après chaque rebuild.

```bash
./make-identity.sh   # crée une identité stable locale (une seule fois)
```

## Lancer

```bash
open build/AltTabber.app
```

L'app vit dans la barre de menus (icône ▤). Menu → **Réglages…**, état des
permissions, et Quitter.

## Permissions (Réglages Système → Confidentialité et sécurité)

1. **Accessibilité** — *obligatoire* : intercepter le raccourci, lister et focus les fenêtres.
2. **Enregistrement de l'écran** — *optionnel* : les vignettes. Sans elle, l'icône de l'app s'affiche.

AltTabber demande l'Accessibilité au premier lancement et s'active automatiquement
dès l'autorisation cochée.

## Architecture

| Fichier | Rôle |
|---|---|
| `SwitcherController` | Event tap (CGEvent), logique d'activation, recherche, focus |
| `WindowManager` | Énumération (AX, tous Spaces), capture (ScreenCaptureKit), focus (AX) |
| `SwitcherView` | Overlay SwiftUI (grille, recherche, sélection glissante) |
| `SwitcherPanel` | `NSPanel` non-activant, flou, redimensionnement live |
| `AppSettings` | Réglages persistés (UserDefaults) |
| `PreferencesView` / `PreferencesWindowController` | Panneau de réglages |
| `LoginItem` | Ouvrir au démarrage (`SMAppService`) |
| `AXPrivate` | `_AXUIElementGetWindow` (mapping `CGWindowID` ↔ `AXUIElement`) |

### Notes

- `CGWindowListCreateImage` est **indisponible** sur macOS 26 → capture via ScreenCaptureKit.
- Les fenêtres réduites / sur d'autres Spaces n'ont pas de surface capturable : elles affichent l'icône de l'app.
- Le raccourci passe par un `CGEvent` tap au niveau session, qui intercepte et consomme la combinaison.

## Lancer au démarrage

Soit le toggle **Ouvrir au démarrage** dans les réglages, soit
Réglages Système → Général → Ouverture → ajouter `AltTabber.app`.
