import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct AddAccountView: View {
    @EnvironmentObject var store: AccountStore
    @Environment(\.dismiss) var dismiss

    @State private var inputMode: Int = 0 // 0: Manual, 1: URI, 2: Camera, 3: Image

    @State private var name: String = ""
    @State private var issuer: String = ""
    @State private var secret: String = ""
    @State private var uriString: String = ""

    @State private var errorMessage: String?
    @State private var isChoosingImage = false
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            Text("Add Account")
                .font(.headline)
                .padding()

            Picker("", selection: $inputMode) {
                Text("Manual").tag(0)
                Text("URI").tag(1)
                Text("Camera").tag(2)
                Text("Image").tag(3)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 16)
            .onChange(of: inputMode) { errorMessage = nil }

            if inputMode == 2 {
                VStack {
                    QRScannerView { payload in
                        handleScan(payload: payload)
                    }
                    .frame(height: 220)
                    .cornerRadius(8)
                    .padding(.horizontal)

                    Text("Point the QR Code at the viewfinder.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
            } else if inputMode == 3 {
                imageDropZone
            } else {
                Form {
                    if inputMode == 0 {
                        Section {
                            TextField("Account Name (e.g. user@email.com)", text: $name)
                                .textFieldStyle(.roundedBorder)

                            TextField("Issuer (e.g. Google) [Optional]", text: $issuer)
                                .textFieldStyle(.roundedBorder)

                            TextField("Base32 Secret", text: $secret)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                                .disableAutocorrection(true)
                        }
                    } else {
                        Section {
                            TextEditor(text: $uriString)
                                .frame(height: 100)
                                .font(.system(.body, design: .monospaced))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))
                            Text("Paste the otpauth:// URI obtained from a QR reader.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal)
            }

            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding(.horizontal)
                    .padding(.top, 8)
            }

            Spacer()

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                if inputMode <= 1 {
                    Button("Save") {
                        save()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding()
        }
        .frame(width: 400, height: 420)
        .animation(.easeInOut, value: inputMode)
    }

    private var imageDropZone: some View {
        VStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 12)
                .fill(isDropTargeted ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.4),
                                      style: StrokeStyle(lineWidth: 2, dash: [8]))
                }
                .overlay {
                    VStack(spacing: 12) {
                        Image(systemName: "qrcode")
                            .font(.system(size: 36))
                            .foregroundColor(.secondary)
                        Text("Drop a QR code image here")
                            .font(.subheadline)
                        Button("Choose File…") {
                            isChoosingImage = true
                        }
                    }
                }
                .frame(height: 170)
                .padding(.horizontal)
                .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)

            Text("Works with a photo or a screenshot of the QR code.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .fileImporter(isPresented: $isChoosingImage,
                      allowedContentTypes: [.image],
                      allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { importImage(at: url) }
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: URL.self) }) else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, error in
            DispatchQueue.main.async {
                guard let url else {
                    errorMessage = error?.localizedDescription ?? QRImageError.unreadableImage.localizedDescription
                    return
                }
                importImage(at: url)
            }
        }
        return true
    }

    /// Imports every QR code in the image. One file can legitimately yield several accounts:
    /// multiple codes in a screenshot, or a single `otpauth-migration://` export.
    private func importImage(at url: URL) {
        errorMessage = nil
        do {
            let payloads = try QRImageDecoder.payloads(in: url)
            var imported = 0
            var firstError: Error?

            for payload in payloads {
                let before = store.accounts.count
                do {
                    try store.parseURI(payload)
                    imported += store.accounts.count - before
                } catch {
                    if firstError == nil { firstError = error }
                }
            }

            guard imported > 0 else {
                throw firstError ?? QRImageError.noCodeFound
            }
            NSSound(named: "Glass")?.play()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            NSSound(named: "Basso")?.play()
        }
    }

    private func handleScan(payload: String) -> Bool {
        do {
            try store.parseURI(payload)
            NSSound(named: "Glass")?.play()
            dismiss()
            return true
        } catch {
            errorMessage = String(localized: "Invalid QR code: ") + error.localizedDescription
            NSSound(named: "Basso")?.play()
            return false
        }
    }

    private func save() {
        errorMessage = nil
        do {
            if inputMode == 0 {
                guard !name.isEmpty, !secret.isEmpty else {
                    errorMessage = String(localized: "Name and Secret are required.")
                    return
                }
                try store.addAccount(name: name, issuer: issuer.isEmpty ? nil : issuer, secret: secret)
            } else {
                guard !uriString.isEmpty else {
                    errorMessage = String(localized: "URI cannot be empty.")
                    return
                }
                try store.parseURI(uriString)
            }
            dismiss()
        } catch Base32Error.invalidCharacters {
            errorMessage = String(localized: "The Base32 secret contains invalid characters.")
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
