import SwiftUI

struct HistoryView: View {
    @ObservedObject var history: ScanHistory
    @ObservedObject var settings: AppSettings
    var onBack: () -> Void = {}
    @State private var copiedId: UUID?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.background)

            VStack(spacing: 0) {
                // Header
                header

                if history.entries.isEmpty {
                    emptyState
                } else {
                    listArea
                }
            }
        }
        .frame(width: 380, height: 480)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Button(action: { onBack() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(.quaternary, in: Circle())
            }
            .buttonStyle(.plain)

            Text("扫描历史")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)

            Text("\(history.entries.count)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: Capsule())

            Spacer()

            if !history.entries.isEmpty {
                Button(action: { history.clearAll() }) {
                    Text("清空")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text("暂无扫描记录")
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(.tertiary)
            Spacer()
        }
    }

    // MARK: - List

    private var listArea: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(history.entries) { entry in
                    historyRow(entry)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
    }

    private func historyRow(_ entry: ScanEntry) -> some View {
        HStack(spacing: 10) {
            // Source icon
            Image(systemName: entry.source == .camera ? "camera.fill" : "photo.fill")
                .font(.system(size: 11))
                .foregroundStyle(Color.accentColor.opacity(0.5))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.content)
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(2)
                    .foregroundStyle(.primary)

                Text(formatTime(entry.timestamp))
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            // Copy button
            Button(action: { copyEntry(entry) }) {
                Image(systemName: copiedId == entry.id ? "checkmark" : "doc.on.clipboard")
                    .font(.system(size: 11))
                    .foregroundStyle(copiedId == entry.id ? Color.green : Color.primary.opacity(0.3))
                    .frame(width: 28, height: 28)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)

            // Delete button
            Button(action: { history.remove(entry) }) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 28, height: 28)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Helpers

    private func copyEntry(_ entry: ScanEntry) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.content, forType: .string)
        withAnimation(.easeInOut(duration: 0.15)) {
            copiedId = entry.id
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation { copiedId = nil }
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(date) {
            formatter.dateFormat = "HH:mm:ss"
        } else {
            formatter.dateFormat = "MM/dd HH:mm"
        }
        return formatter.string(from: date)
    }
}
