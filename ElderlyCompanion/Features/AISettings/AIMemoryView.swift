import SwiftUI

struct AIMemoryView: View {
    @State private var showDeleteConfirmation = false
    @State private var showExportConfirmation = false

    var body: some View {
        ScrollView {
            VStack(spacing: CompanionTheme.Spacing.lg) {
                // Memory info
                CalmCard {
                    VStack(alignment: .leading, spacing: CompanionTheme.Spacing.md) {
                        CalmCardHeader("Memory & Context", icon: "brain.fill")

                        Text("Noah remembers your conversations to provide continuity and personalized support. You have full control over what is stored.")
                            .font(.companionBodySecondary)
                            .foregroundStyle(Color.companionTextSecondary)
                    }
                }

                // Actions
                VStack(spacing: CompanionTheme.Spacing.md) {
                    LargeButton("Download Conversation History", icon: "arrow.down.doc.fill", style: .outline) {
                        showExportConfirmation = true
                    }

                    LargeButton("Clear All Memory", icon: "trash.fill", style: .danger) {
                        showDeleteConfirmation = true
                    }
                }

                // Privacy note
                CalmCard {
                    HStack(spacing: CompanionTheme.Spacing.md) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(Color.companionInfo)

                        Text("Clearing memory will reset Noah's knowledge about you. This cannot be undone.")
                            .font(.companionCaption)
                            .foregroundStyle(Color.companionTextSecondary)
                    }
                }
            }
            .padding(CompanionTheme.Spacing.lg)
        }
        .background(Color.companionBackground)
        .navigationTitle("AI Memory")
        .navigationBarTitleDisplayMode(.large)
        .alert("Clear All Memory?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear Memory", role: .destructive) {
                // TODO: Clear memory via API
            }
        } message: {
            Text("This will permanently erase everything Noah knows about you. This action cannot be undone.")
        }
        .alert("Export Data", isPresented: $showExportConfirmation) {
            Button("OK") {}
        } message: {
            Text("Your conversation history will be prepared for download. You'll receive a notification when it's ready.")
        }
    }
}
