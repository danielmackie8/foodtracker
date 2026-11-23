import SwiftUI
import VisionKit

/// Full-screen camera barcode scanner (VisionKit DataScannerViewController),
/// with manual entry as a fallback.
struct BarcodeScannerSheet: View {
    var onCode: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var manual = ""
    @State private var showManual = false

    private var scannerAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if scannerAvailable {
                DataScannerRepresentable { code in
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    onCode(code)
                }
                .ignoresSafeArea()
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(.white.opacity(0.9), lineWidth: 3)
                    .frame(width: 280, height: 160)
                    .allowsHitTesting(false)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "camera.fill").font(.system(size: 34))
                    Text("Camera scanning isn't available").font(.manrope(17, .bold))
                    Text("Check camera access in Settings, or type the barcode number instead.")
                        .font(.manrope(14)).multilineTextAlignment(.center).opacity(0.8)
                }
                .foregroundStyle(.white)
                .padding(32)
            }

            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 17, weight: .bold))
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .accessibilityLabel("Close scanner")
                    Spacer()
                }
                Spacer()
                VStack(spacing: 10) {
                    Text("Point the camera at the barcode on the pack")
                        .font(.manrope(14, .semibold))
                    Button("Type the number instead") { showManual = true }
                        .font(.manrope(14, .bold))
                        .padding(.horizontal, 18).frame(minHeight: 44)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .padding(.bottom, 24)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
        }
        .alert("Enter barcode", isPresented: $showManual) {
            TextField("e.g. 5000159484695", text: $manual).keyboardType(.numberPad)
            Button("Look up") {
                let code = manual.filter(\.isNumber)
                if !code.isEmpty { onCode(code) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

private struct DataScannerRepresentable: UIViewControllerRepresentable {
    var onCode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce, .code128, .itf14])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        vc.delegate = context.coordinator
        try? vc.startScanning()
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {
        if !vc.isScanning { try? vc.startScanning() }
    }

    static func dismantleUIViewController(_ vc: DataScannerViewController, coordinator: Coordinator) {
        vc.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        private var delivered = false
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            handle(addedItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            handle([item])
        }

        private func handle(_ items: [RecognizedItem]) {
            guard !delivered else { return }
            for item in items {
                if case .barcode(let b) = item, let value = b.payloadStringValue, !value.isEmpty {
                    delivered = true
                    onCode(value)
                    return
                }
            }
        }
    }
}
