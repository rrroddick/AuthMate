import SwiftUI
import AppKit

struct AddAccountView: View {
    @EnvironmentObject var store: AccountStore
    @Environment(\.dismiss) var dismiss

    @State private var inputMode: Int = 0 // 0: Manual, 1: URI, 2: Camera

    @State private var name: String = ""
    @State private var issuer: String = ""
    @State private var secret: String = ""
    @State private var uriString: String = ""

    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            Text("Add Account")
                .font(.headline)
                .padding()

            Picker("", selection: $inputMode) {
                Text("Manual").tag(0)
                Text("Text URI").tag(1)
                Text("QR Camera").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 16)

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

                if inputMode != 2 {
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
