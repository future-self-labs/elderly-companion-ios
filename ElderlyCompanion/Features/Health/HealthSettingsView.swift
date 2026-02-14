import SwiftUI

struct HealthSettingsView: View {
    @State private var healthService = HealthKitService.shared
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var shareWithFamily = UserDefaults.standard.bool(forKey: "healthShareWithFamily")
    @State private var shareWithNoah = UserDefaults.standard.bool(forKey: "healthShareWithNoah")

    var body: some View {
        ScrollView {
            VStack(spacing: CompanionTheme.Spacing.lg) {
                // Header
                CalmCard {
                    VStack(spacing: CompanionTheme.Spacing.md) {
                        Image(systemName: "heart.text.clipboard.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(Color.companionDanger)

                        Text("Health & Peripherals")
                            .font(.companionHeadline)
                            .foregroundStyle(Color.companionTextPrimary)

                        Text("Connect Apple Health to let Noah monitor your wellbeing and share key stats with family.")
                            .font(.companionBodySecondary)
                            .foregroundStyle(Color.companionTextSecondary)
                            .multilineTextAlignment(.center)
                    }
                }

                // Connection status
                CalmCard {
                    VStack(alignment: .leading, spacing: CompanionTheme.Spacing.md) {
                        CalmCardHeader("Apple Health", icon: "heart.fill")

                        if !healthService.isAvailable {
                            HStack(spacing: CompanionTheme.Spacing.sm) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(Color.companionDanger)
                                Text("HealthKit not available on this device")
                                    .font(.companionBodySecondary)
                                    .foregroundStyle(Color.companionTextSecondary)
                            }
                        } else if healthService.isAuthorized {
                            HStack(spacing: CompanionTheme.Spacing.sm) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.companionSuccess)
                                Text("Connected")
                                    .font(.companionBody)
                                    .foregroundStyle(Color.companionSuccess)
                            }

                            Text("Noah reads: steps, heart rate, blood oxygen, blood pressure, sleep")
                                .font(.companionCaption)
                                .foregroundStyle(Color.companionTextSecondary)
                        } else {
                            LargeButton(
                                isLoading ? "Connecting..." : "Connect Apple Health",
                                icon: "heart.fill"
                            ) {
                                connectHealth()
                            }
                            .disabled(isLoading)
                        }
                    }
                }

                // Live stats (only if authorized)
                if healthService.isAuthorized {
                    CalmCard {
                        VStack(alignment: .leading, spacing: CompanionTheme.Spacing.md) {
                            HStack {
                                CalmCardHeader("Today's Stats", icon: "chart.bar.fill")
                                Spacer()
                                Button {
                                    refreshStats()
                                } label: {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 14))
                                        .foregroundStyle(Color.companionPrimary)
                                }
                            }

                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: CompanionTheme.Spacing.md) {
                                HealthStatTile(
                                    icon: "figure.walk",
                                    label: "Steps",
                                    value: "\(healthService.stepCount)",
                                    color: .companionPrimary
                                )
                                HealthStatTile(
                                    icon: "heart.fill",
                                    label: "Heart Rate",
                                    value: healthService.heartRate > 0 ? "\(Int(healthService.heartRate)) bpm" : "—",
                                    color: .companionDanger
                                )
                                HealthStatTile(
                                    icon: "lungs.fill",
                                    label: "Blood O₂",
                                    value: healthService.bloodOxygen > 0 ? "\(Int(healthService.bloodOxygen))%" : "—",
                                    color: .companionInfo
                                )
                                HealthStatTile(
                                    icon: "bed.double.fill",
                                    label: "Sleep",
                                    value: healthService.sleepHours > 0 ? String(format: "%.1fh", healthService.sleepHours) : "—",
                                    color: .companionSecondary
                                )
                            }

                            if healthService.bloodPressureSystolic > 0 {
                                HStack(spacing: CompanionTheme.Spacing.sm) {
                                    Image(systemName: "waveform.path.ecg")
                                        .foregroundStyle(Color.companionWarning)
                                    Text("Blood Pressure: \(Int(healthService.bloodPressureSystolic))/\(Int(healthService.bloodPressureDiastolic)) mmHg")
                                        .font(.companionBodySecondary)
                                        .foregroundStyle(Color.companionTextPrimary)
                                }
                            }
                        }
                    }

                    // Sharing settings
                    CalmCard {
                        VStack(alignment: .leading, spacing: CompanionTheme.Spacing.md) {
                            CalmCardHeader("Sharing", icon: "square.and.arrow.up.fill")

                            Toggle(isOn: $shareWithNoah) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Share with Noah")
                                        .font(.companionBody)
                                        .foregroundStyle(Color.companionTextPrimary)
                                    Text("Noah can discuss your health during conversations")
                                        .font(.companionCaption)
                                        .foregroundStyle(Color.companionTextSecondary)
                                }
                            }
                            .tint(Color.companionPrimary)
                            .onChange(of: shareWithNoah) { _, val in
                                UserDefaults.standard.set(val, forKey: "healthShareWithNoah")
                            }

                            Divider()

                            Toggle(isOn: $shareWithFamily) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Share with Family")
                                        .font(.companionBody)
                                        .foregroundStyle(Color.companionTextPrimary)
                                    Text("Include health stats in daily WhatsApp update")
                                        .font(.companionCaption)
                                        .foregroundStyle(Color.companionTextSecondary)
                                }
                            }
                            .tint(Color.companionPrimary)
                            .onChange(of: shareWithFamily) { _, val in
                                UserDefaults.standard.set(val, forKey: "healthShareWithFamily")
                            }
                        }
                    }

                    // Peripherals info
                    CalmCard {
                        VStack(alignment: .leading, spacing: CompanionTheme.Spacing.md) {
                            CalmCardHeader("Compatible Peripherals", icon: "applewatch")

                            VStack(alignment: .leading, spacing: CompanionTheme.Spacing.sm) {
                                PeripheralRow(name: "Apple Watch", icon: "applewatch", detail: "Heart rate, steps, sleep, blood oxygen")
                                PeripheralRow(name: "Blood Pressure Monitor", icon: "waveform.path.ecg", detail: "Withings, Omron (via Apple Health)")
                                PeripheralRow(name: "Smart Scale", icon: "scalemass.fill", detail: "Withings, Eufy (via Apple Health)")
                                PeripheralRow(name: "Pulse Oximeter", icon: "lungs.fill", detail: "Any Apple Health compatible device")
                            }

                            Text("Connect peripherals through their own apps — data flows into Apple Health, and Noah reads it automatically.")
                                .font(.companionCaption)
                                .foregroundStyle(Color.companionTextTertiary)
                                .padding(.top, CompanionTheme.Spacing.xs)
                        }
                    }
                }
            }
            .padding(CompanionTheme.Spacing.lg)
        }
        .background(Color.companionBackground)
        .navigationTitle("Health")
        .navigationBarTitleDisplayMode(.large)
        .alert("Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            healthService.checkAuthorization()
            if healthService.isAuthorized {
                refreshStats()
            }
        }
    }

    private func connectHealth() {
        isLoading = true
        Task {
            do {
                try await healthService.requestAuthorization()
                await MainActor.run {
                    isLoading = false
                    shareWithNoah = true
                    shareWithFamily = true
                    UserDefaults.standard.set(true, forKey: "healthShareWithNoah")
                    UserDefaults.standard.set(true, forKey: "healthShareWithFamily")
                }
                refreshStats()
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = "Could not connect to Apple Health: \(error.localizedDescription)"
                    showError = true
                }
            }
        }
    }

    private func refreshStats() {
        Task {
            await healthService.fetchTodayStats()
            // Sync to server
            await syncHealthToServer()
        }
    }

    private func syncHealthToServer() async {
        guard let userId = UserDefaults.standard.string(forKey: "userId") else { return }
        do {
            try await APIClient.shared.sendHealthSnapshot(.init(
                userId: userId,
                stepCount: healthService.stepCount,
                heartRate: Int(healthService.heartRate),
                bloodOxygen: Int(healthService.bloodOxygen),
                bloodPressureSystolic: Int(healthService.bloodPressureSystolic),
                bloodPressureDiastolic: Int(healthService.bloodPressureDiastolic),
                sleepHours: String(format: "%.1f", healthService.sleepHours)
            ))
            print("[Health] Synced snapshot to server")
        } catch {
            print("[Health] Failed to sync: \(error)")
        }
    }
}

// MARK: - Health Stat Tile

struct HealthStatTile: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: CompanionTheme.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(color)

            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(Color.companionTextPrimary)

            Text(label)
                .font(.companionCaption)
                .foregroundStyle(Color.companionTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, CompanionTheme.Spacing.md)
        .background(Color.companionSurfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: CompanionTheme.Radius.md))
    }
}

// MARK: - Peripheral Row

struct PeripheralRow: View {
    let name: String
    let icon: String
    let detail: String

    var body: some View {
        HStack(spacing: CompanionTheme.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Color.companionPrimary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.companionBodySecondary)
                    .foregroundStyle(Color.companionTextPrimary)
                Text(detail)
                    .font(.companionCaption)
                    .foregroundStyle(Color.companionTextTertiary)
            }
        }
    }
}
