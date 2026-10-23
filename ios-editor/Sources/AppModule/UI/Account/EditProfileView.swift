import SwiftUI

struct EditProfileView: View {
    @ObservedObject var account: GoogleAccountSession
    @Environment(\.dismiss) private var dismiss

    @State private var isConfirmingDeletion = false
    @State private var deletionError: String?

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    avatar
                    VStack(alignment: .leading, spacing: 4) {
                        Text(account.profile?.displayName ?? "Neonix Account")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(account.email ?? "Neonix account")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 8)
            } header: {
                Text("Account details")
            }

            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Danger Zone", systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.red)
                    Text("Permanently delete your account and associated account data. This action cannot be undone.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 5)

                Button {
                    isConfirmingDeletion = true
                } label: {
                    HStack(spacing: 12) {
                        if account.isLoading {
                            ProgressView()
                                .tint(.red)
                                .frame(width: 24)
                        } else {
                            Image(systemName: "trash")
                                .frame(width: 24)
                        }
                        Text(account.isLoading ? "Deleting account…" : "Delete account")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                    .foregroundStyle(.red)
                    .contentShape(Rectangle())
                }
                .disabled(account.isLoading)
                .accessibilityIdentifier("delete-account-button")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Edit profile")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete your Neonix account?", isPresented: $isConfirmingDeletion, titleVisibility: .visible) {
            Button("Delete account", role: .destructive) {
                Task { await deleteAccount() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes your Neonix account and associated data. You won't be able to recover it.")
        }
        .alert("Couldn't delete account", isPresented: Binding(
            get: { deletionError != nil },
            set: { if !$0 { deletionError = nil } }
        )) {
            Button("OK", role: .cancel) { deletionError = nil }
        } message: {
            Text(deletionError ?? "Please check your connection and try again.")
        }
    }

    @ViewBuilder
    private var avatar: some View {
        if let url = account.profile?.avatarUrl {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                avatarFallback
            }
            .frame(width: 56, height: 56)
            .clipShape(Circle())
        } else {
            avatarFallback
        }
    }

    private var avatarFallback: some View {
        Circle()
            .fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: 56, height: 56)
            .overlay {
                Text("N")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
            }
    }

    @MainActor
    private func deleteAccount() async {
        do {
            try await account.deleteAccount()
            dismiss()
        } catch {
            deletionError = error.localizedDescription
        }
    }
}
