import SwiftUI

struct AutoFetchSettingsCard: View {
    @Binding var autoFetchEnabled: Bool
    @Binding var autoFetchTiming: FetchTriggerConfiguration.AutoFetchTiming
    let nextAutoFetchTime: Date?

    private static let fmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()

    var body: some View {
        SettingsCard(title: "Auto Fetch") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: $autoFetchEnabled) {
                    Text("Fetch once daily").font(.system(size: 13)).foregroundStyle(Color.scText)
                }.tint(Color.scAccent)

                Text("Fetches forecast once per day, fixed time or sunrise relative.")
                    .font(.system(size: 11)).foregroundStyle(Color.scMuted)

                if autoFetchEnabled {
                    Picker("Timing", selection: timingBinding) {
                        Text("Sunrise-relative").tag(0)
                        Text("Fixed time").tag(1)
                    }.pickerStyle(.segmented)

                    switch autoFetchTiming {
                    case .sunriseRelative(let offset):
                        Stepper(
                            offset < 0 ? "\(-offset) min before sunrise" : "\(offset) min after sunrise",
                            value: Binding(
                                get: { offset },
                                set: { autoFetchTiming = .sunriseRelative(offsetMinutes: $0) }),
                            in: -120...120, step: 5
                        ).font(.system(size: 12))
                    case .fixedTime(let hour, let minute):
                        DatePicker("Time", selection: Binding(
                            get: { Self.dateFrom(hour: hour, minute: minute) },
                            set: { let c = Calendar.current.dateComponents([.hour,.minute], from: $0)
                                  autoFetchTiming = .fixedTime(hour: c.hour ?? 6, minute: c.minute ?? 0) }
                        ), displayedComponents: .hourAndMinute).font(.system(size: 12))
                    }

                    if let next = nextAutoFetchTime {
                        Text("Next auto-fetch: \(Self.fmt.string(from: next))")
                            .font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.scGreen)
                    }
                }
            }
        }
    }

    private var timingBinding: Binding<Int> {
        Binding(
            get: { if case .sunriseRelative = autoFetchTiming { return 0 }; return 1 },
            set: { autoFetchTiming = $0 == 0
                ? .sunriseRelative(offsetMinutes: -30) : .fixedTime(hour: 6, minute: 0) })
    }

    private static func dateFrom(hour: Int, minute: Int) -> Date {
        var c = DateComponents(); c.hour = hour; c.minute = minute
        return Calendar.current.date(from: c) ?? Date()
    }
}
