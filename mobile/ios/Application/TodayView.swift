import SwiftUI

struct TodayView: View {
    private let overview: AppOverview?
    private let failed: Bool

    init(now: Date = Date(), zoneID: String = TimeZone.current.identifier) {
        do {
            overview = try AppOverview.empty(now: now, zoneID: zoneID)
            failed = false
        } catch {
            overview = nil
            failed = true
        }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                BrandHeader()
                if let overview {
                    Text(overview.date.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Habits").font(.headline)
                    Text(overview.summary.total, format: .number)
                        .font(.largeTitle)
                    Text("No habits yet").foregroundStyle(.secondary)
                } else if failed {
                    Text("Couldn't load today").foregroundStyle(.red)
                }
                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .navigationTitle("Today")
        }
    }
}