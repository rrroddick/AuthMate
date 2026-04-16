import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: AccountStore
    @State private var showingAddAccount = false
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool

    private var filteredAccounts: [OTPAccount] {
        guard !searchText.isEmpty else { return store.accounts }
        let query = searchText.lowercased()
        return store.accounts.filter {
            $0.issuer?.lowercased().contains(query) == true || $0.name.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Floating transparent header
            HStack(alignment: .center) {
                Text("AuthMate")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Spacer()

                if !store.accounts.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                        TextField("Search", text: $searchText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .frame(width: 90)
                            .focused($searchFocused)
                            .onKeyPress(.escape) {
                                searchText = ""
                                searchFocused = false
                                return .handled
                            }
                        if !searchText.isEmpty {
                            Button(action: {
                                searchText = ""
                                searchFocused = false
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.07))
                    .clipShape(Capsule())
                }

                HStack(spacing: 10) {
                    Button(action: {
                        showingAddAccount = true
                    }) {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.primary)
                    }
                    .buttonStyle(.plain)
                    .padding(7)
                    .background(Color.primary.opacity(0.1))
                    .clipShape(Circle())
                    .help("Add account")

                    Button(action: {
                        confirmQuit()
                    }) {
                        Image(systemName: "power")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(7)
                    .background(Color.primary.opacity(0.07))
                    .clipShape(Circle())
                    .help("Quit")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            // Account list
            if store.accounts.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 44))
                        .foregroundColor(.secondary)
                    Text("No Accounts")
                        .font(.headline)
                    Text("Press + to add an account\nor paste an otpauth:// URI")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .frame(maxHeight: .infinity)
            } else if filteredAccounts.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 44))
                        .foregroundColor(.secondary)
                    Text("No Results")
                        .font(.headline)
                    Text("No accounts match \"\(searchText)\"")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredAccounts) { account in
                            AccountRowView(account: account)
                                .contextMenu {
                                    Button {
                                        if let index = store.accounts.firstIndex(where: { $0.id == account.id }) {
                                            withAnimation {
                                                store.delete(at: IndexSet(integer: index))
                                            }
                                        }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 14)
                }
                .frame(maxHeight: .infinity)
            }
        }
        .frame(width: 340, height: 500)
        .background {
            WindowConfigurator()
        }
        .popover(isPresented: $showingAddAccount) {
            AddAccountView()
        }
    }

    private func confirmQuit() {
        let alert = NSAlert()
        alert.messageText = String(localized: "Do you want to quit AuthMate?")
        alert.informativeText = String(localized: "The app will close and will no longer be available in the menu bar.")
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "Quit"))
        alert.addButton(withTitle: String(localized: "Cancel"))

        if alert.runModal() == .alertFirstButtonReturn {
            NSApplication.shared.terminate(nil)
        }
    }
}
