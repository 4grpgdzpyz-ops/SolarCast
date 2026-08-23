import SwiftUI

struct DatePickerSheet: View {
    let selectedDate: Date
    let datesWithData: Set<String>
    let onSelect: (Date) -> Void

    @State private var displayMonth: Date
    @State private var showMonthYearPicker = false
    @Environment(\.dismiss) private var dismiss

    private static let keyFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = .current; return f
    }()
    private static let monthFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"; return f
    }()
    private var calendar: Calendar { Calendar.current }
    private let totalCells = 42 // 6 rows × 7 columns — fixed height

    init(selectedDate: Date, datesWithData: Set<String>, onSelect: @escaping (Date) -> Void) {
        self.selectedDate = selectedDate
        self.datesWithData = datesWithData
        self.onSelect = onSelect
        _displayMonth = State(initialValue: selectedDate)
    }

    private func hasData(_ date: Date) -> Bool {
        datesWithData.contains(Self.keyFmt.string(from: date))
    }

    private func daysInMonth() -> [Date?] {
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: displayMonth)),
              let range = calendar.range(of: .day, in: .month, for: monthStart) else { return [] }
        let weekday = calendar.component(.weekday, from: monthStart) - 1
        var days: [Date?] = Array(repeating: nil, count: weekday)
        for d in range {
            if let date = calendar.date(byAdding: .day, value: d - 1, to: monthStart) {
                days.append(date)
            }
        }
        // Pad to exactly 42 cells (6 rows)
        while days.count < totalCells { days.append(nil) }
        return days
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(Color.scBorder).frame(width: 36, height: 4)
                .padding(.top, 10).padding(.bottom, 8)

            if showMonthYearPicker {
                monthYearPicker
            } else {
                calendarGrid

            // Legend
            HStack(spacing: 20) {
                HStack(spacing: 6) {
                    Circle().fill(Color.scAccent).frame(width: 8, height: 8)
                    Text("Has data").font(.system(size: 11)).foregroundStyle(Color.scMuted)
                }
                HStack(spacing: 6) {
                    Circle().fill(Color.scBorder).frame(width: 8, height: 8)
                    Text("No data").font(.system(size: 11)).foregroundStyle(Color.scMuted)
                }
            }
            .padding(.top, 12).padding(.bottom, 16)
            } // end else (calendar view)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.scCard)
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
        .presentationBackground(Color.scCard)
    }

    // MARK: - Calendar Grid

    private var calendarGrid: some View {
        VStack(spacing: 0) {
            // Month header — tappable to switch to month/year picker
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showMonthYearPicker = true }
                } label: {
                    HStack(spacing: 6) {
                        Text(Self.monthFmt.string(from: displayMonth))
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Color.scText)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.scAccent)
                    }
                }
                Spacer()
                Button {
                    displayMonth = calendar.date(byAdding: .month, value: -1, to: displayMonth) ?? displayMonth
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.scAccent)
                        .frame(width: 40, height: 40)
                }
                Button {
                    displayMonth = calendar.date(byAdding: .month, value: 1, to: displayMonth) ?? displayMonth
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.scAccent)
                        .frame(width: 40, height: 40)
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 12)

            // Day of week headers
            HStack(spacing: 0) {
                ForEach(["S","M","T","W","T","F","S"], id: \.self) { d in
                    Text(d)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.scMuted)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 8).padding(.bottom, 6)

            // 6-row grid (always 42 cells)
            let days = daysInMonth()
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 4) {
                ForEach(0..<totalCells, id: \.self) { i in
                    if i < days.count, let date = days[i] {
                        let dataAvailable = hasData(date)
                        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
                        let isToday = calendar.isDateInToday(date)

                        Button {
                            if dataAvailable {
                                onSelect(date)
                                dismiss()
                            }
                        } label: {
                            ZStack {
                                if isSelected {
                                    Circle().fill(Color.scAccent)
                                } else if isToday {
                                    Circle().stroke(Color.scAccent, lineWidth: 1.5)
                                }
                                Text("\(calendar.component(.day, from: date))")
                                    .font(.system(size: 16, weight: isToday || isSelected ? .semibold : .regular))
                                    .foregroundStyle(
                                        isSelected ? .white :
                                        dataAvailable ? Color.scText :
                                        Color.scBorder
                                    )
                            }
                            .frame(width: 36, height: 36)
                            .overlay(alignment: .bottom) {
                                if dataAvailable && !isSelected {
                                    Circle().fill(Color.scAccent).frame(width: 4, height: 4)
                                        .offset(y: -2)
                                }
                            }
                        }
                        .disabled(!dataAvailable)
                    } else {
                        Color.clear.frame(width: 36, height: 36)
                    }
                }
            }
            .padding(.horizontal, 8)
        }
    }

    // MARK: - Month/Year Picker

    @State private var pickerMonth: Int = 1
    @State private var pickerYear: Int = 2026

    private var monthYearPicker: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Select Month & Year")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.scText)
                Spacer()
                Button("Done") {
                    var comps = DateComponents()
                    comps.year = pickerYear; comps.month = pickerMonth; comps.day = 1
                    if let date = calendar.date(from: comps) {
                        displayMonth = date
                    }
                    withAnimation(.easeInOut(duration: 0.2)) { showMonthYearPicker = false }
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.scAccent)
            }
            .padding(.horizontal, 16)

            HStack(spacing: 0) {
                Picker("Month", selection: $pickerMonth) {
                    ForEach(1...12, id: \.self) { m in
                        Text(Calendar.current.monthSymbols[m - 1]).tag(m)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)
                .clipped()

                Picker("Year", selection: $pickerYear) {
                    ForEach(2025...2050, id: \.self) { y in
                        Text(String(y)).tag(y)
                    }
                }
                .pickerStyle(.wheel)
                .frame(width: 170)
                .clipped()
            }
            .frame(height: 180)
        }
        .onAppear {
            pickerMonth = calendar.component(.month, from: displayMonth)
            pickerYear = calendar.component(.year, from: displayMonth)
        }
    }
}
