import SwiftUI

struct PVSiteEditView: View {
    @State var viewModel: PVSiteEditViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
            Form {
                Section("Site Details") {
                    TextField("Name (e.g. East Roof)", text: $viewModel.name)
                    TextField("Solcast Site ID", text: $viewModel.solcastSiteID)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                Section("Chart Color") {
                    ColorPickerSection(colorHex: $viewModel.colorHex)
                }
            }
            .navigationTitle(viewModel.name.isEmpty ? "New Site" : viewModel.name)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { Task { if await viewModel.save() { dismiss() } } }
                }
            }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: { Text(viewModel.errorMessage ?? "") }
    }
}
struct ColorPickerSection: View {
    @Binding var colorHex: String
    @State private var red:   Double = 0
    @State private var green: Double = 0
    @State private var blue:  Double = 0
    @State private var hexInput: String = ""
    @State private var hexError = false

    static let presets = [
        "#00C853","#2196F3","#FF9800","#E91E63",
        "#9C27B0","#00BCD4","#FF5722","#4CAF50",
        "#FFC107","#607D8B","#F44336","#3F51B5"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Preview").font(.system(size: 13)).foregroundStyle(Color.scMuted)
                Spacer()
                RoundedRectangle(cornerRadius: 8).fill(Color(hex: colorHex))
                    .frame(width: 44, height: 44)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.scBorder, lineWidth: 1))
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 10) {
                ForEach(Self.presets, id: \.self) { hex in
                    Circle().fill(Color(hex: hex)).frame(width: 34, height: 34)
                        .overlay(Circle().stroke(Color.scText.opacity(
                            colorHex.uppercased() == hex.uppercased() ? 1 : 0), lineWidth: 2.5))
                        .onTapGesture { colorHex = hex; syncFromHex() }
                }
            }
            Divider()
            VStack(spacing: 8) {
                colorSlider(label: "R", value: $red,   color: .red)
                colorSlider(label: "G", value: $green, color: .green)
                colorSlider(label: "B", value: $blue,  color: .blue)
            }
            .onChange(of: red)   { _,_ in syncFromRGB() }
            .onChange(of: green) { _,_ in syncFromRGB() }
            .onChange(of: blue)  { _,_ in syncFromRGB() }
            Divider()
            HStack {
                Text("#").foregroundStyle(Color.scMuted)
                TextField("Hex (e.g. FF9800)", text: $hexInput)
                    .autocorrectionDisabled().textInputAutocapitalization(.characters)
                    .onSubmit { applyHexInput() }
                if hexError { Image(systemName: "exclamationmark.circle").foregroundStyle(Color.scRed) }
                Button("Apply") { applyHexInput() }
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.scAccent)
            }
        }
        .onAppear { syncFromHex() }
    }

    @ViewBuilder
    private func colorSlider(label: String, value: Binding<Double>, color: Color) -> some View {
        HStack(spacing: 10) {
            Text(label).font(.system(size: 12, weight: .bold)).frame(width: 12)
            Slider(value: value, in: 0...255, step: 1).tint(color)
            Text(String(Int(value.wrappedValue))).font(.system(size: 12, weight: .medium))
                .frame(width: 30, alignment: .trailing).foregroundStyle(Color.scText)
        }
    }

    private func syncFromHex() {
        let cleaned = colorHex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard cleaned.count == 6, let rgb = UInt64(cleaned, radix: 16) else { return }
        red = Double((rgb >> 16) & 0xFF); green = Double((rgb >> 8) & 0xFF); blue = Double(rgb & 0xFF)
        hexInput = cleaned.uppercased(); hexError = false
    }
    private func syncFromRGB() {
        let r = Int(red.rounded()), g = Int(green.rounded()), b = Int(blue.rounded())
        colorHex = String(format: "#%02X%02X%02X", r, g, b)
        hexInput = String(format: "%02X%02X%02X", r, g, b); hexError = false
    }
    private func applyHexInput() {
        let cleaned = hexInput.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard cleaned.count == 6, UInt64(cleaned, radix: 16) != nil else { hexError = true; return }
        colorHex = "#\(cleaned.uppercased())"; syncFromHex()
    }
}
