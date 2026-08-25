import SwiftUI

/// The HUD overlay. A frosted rounded panel with an optional search bar and a
/// grid of window cards; the selection highlight slides between cards.
struct SwitcherView: View {
    @ObservedObject var model: SwitcherModel
    @Namespace private var highlight

    private let spacing: CGFloat = 12
    private let padding: CGFloat = 18
    private let outerPadding: CGFloat = 24

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.fixed(model.cardWidth), spacing: spacing),
              count: max(model.columns, 1))
    }

    var body: some View {
        VStack(spacing: 12) {
            if !model.searchText.isEmpty {
                searchBar
            }

            if model.filtered.isEmpty {
                emptyState
            } else {
                grid
            }
        }
        .padding(padding)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(.white.opacity(0.14), lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: .black.opacity(0.38), radius: 34, y: 14)
        .padding(outerPadding)
        .animation(model.animationsEnabled ? .spring(response: 0.26, dampingFraction: 0.82) : nil,
                   value: model.selectedIndex)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            Text(model.searchText)
                .font(.system(size: 15, weight: .medium))
            Text("|")
                .foregroundStyle(.tint)
                .opacity(0.9)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity)
        .background(
            Capsule(style: .continuous).fill(.black.opacity(0.18))
        )
        .padding(.horizontal, 2)
    }

    private var grid: some View {
        LazyVGrid(columns: gridColumns, spacing: spacing) {
            ForEach(Array(model.filtered.enumerated()), id: \.element.id) { index, window in
                card(for: window, isSelected: index == model.selectedIndex)
                    .frame(width: model.cardWidth, height: model.cardHeight)
                    .contentShape(Rectangle())
                    .onTapGesture { model.onActivate?(index) }
                    .onHover { hovering in if hovering { model.onHover?(index) } }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text("Aucune fenêtre pour « \(model.searchText) »")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(width: 360, height: 160)
    }

    @ViewBuilder
    private func card(for window: WindowInfo, isSelected: Bool) -> some View {
        VStack(spacing: 7) {
            thumbnail(for: window)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if model.showTitles {
                Text(window.displayTitle)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(9)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.accentColor.opacity(0.28))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.accentColor, lineWidth: 2.5)
                    )
                    .matchedGeometryEffect(id: "selection", in: highlight)
            }
        }
        .scaleEffect(isSelected ? 1.0 : 0.965)
        .opacity(isSelected ? 1.0 : 0.8)
    }

    @ViewBuilder
    private func thumbnail(for window: WindowInfo) -> some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(.black.opacity(0.16))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                )

            if let image = model.thumbnails[window.id] {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.medium)
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .padding(4)
                    .opacity(window.isMinimized ? 0.5 : 1)
            } else if let icon = window.appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 52, height: 52)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(window.isMinimized ? 0.45 : 0.9)
            }

            // App icon badge, overlapping the bottom-left corner (AltTab-style).
            if let icon = window.appIcon, model.thumbnails[window.id] != nil {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 30, height: 30)
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                    .padding(6)
            }

            // Minimized marker, top-right.
            if window.isMinimized {
                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(.white, .black.opacity(0.55))
                            .padding(6)
                    }
                    Spacer()
                }
            }
        }
    }
}
