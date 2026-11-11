import PlateCore
import SwiftUI
import VisionKit

/// Scan a barcode, look the product up on Open Food Facts, then add it like any other food.
struct BarcodeAddView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var code: String?
    @State private var product: OpenFoodFacts.Product?
    @State private var looking = false
    @State private var message: String?
    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                    ScannerView { found in
                        guard code == nil else { return }
                        code = found
                        Task { await lookUp(found) }
                    }
                    .frame(maxHeight: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                } else {
                    ContentUnavailableView("Scanning isn't available", systemImage: "barcode.viewfinder",
                                           description: Text("Plate needs camera access to scan barcodes. You can allow it in the Settings app, or add food by name instead."))
                }
                if looking { ProgressView("Looking it up…") }
                if let message {
                    Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Scan again") { code = nil; self.message = nil }
                }
                Spacer()
            }
            .padding()
            .navigationTitle("Scan a barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .sheet(isPresented: $showAdd, onDismiss: { dismiss() }) {
                AddFoodView(prefill: product)
            }
        }
    }

    func lookUp(_ barcode: String) async {
        looking = true
        defer { looking = false }
        guard let url = OpenFoodFacts.url(for: barcode) else { message = "That barcode couldn't be read."; return }
        var req = URLRequest(url: url)
        req.setValue("Plate iOS app", forHTTPHeaderField: "User-Agent")
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            if let p = OpenFoodFacts.parse(data, barcode: barcode) {
                product = p
                showAdd = true
            } else {
                message = "Open Food Facts doesn't know barcode \(barcode). Add it by name instead."
            }
        } catch {
            message = "Couldn't look it up (\(error.localizedDescription)). Check your connection."
        }
    }
}

struct ScannerView: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce, .code128])],
                                           qualityLevel: .balanced, isHighlightingEnabled: true)
        vc.delegate = context.coordinator
        try? vc.startScanning()
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in addedItems {
                if case .barcode(let b) = item, let value = b.payloadStringValue {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    onCode(value)
                    return
                }
            }
        }
    }
}
