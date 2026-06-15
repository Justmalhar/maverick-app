// client/Sources/Features/Pairing/PairingView.swift
import SwiftUI

/// The full QR-pairing flow UI: scan/paste a `maverick://pair/v1?...` code,
/// watch the Noise handshake, verify the safety number out-of-band, then adopt
/// the encrypted socket. Styled to match `ConnectionView` (Liquid Glass / Theme).
struct PairingView: View {
    @Environment(ConnectionManager.self) private var connection
    @Environment(\.dismiss) private var dismiss

    @State private var controller: PairingController?
    @State private var showScanner = false
    @State private var showManualEntry = false
    @State private var manualURL = ""

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()
            RadialGradient(
                colors: [Theme.accent.opacity(0.18), .clear],
                center: .topLeading, startRadius: 20, endRadius: 380
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            ScrollView {
                VStack(spacing: 24) {
                    hero
                    content
                    Spacer(minLength: 30)
                }
                .padding(.horizontal, 22)
                .padding(.top, 48)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if controller == nil {
                controller = PairingController(connection: connection)
            }
        }
        .onChange(of: controller?.state) { _, newValue in
            // Dismiss once the encrypted session is live (ContentView swaps to
            // the connected UI when ConnectionManager flips to `.connected`).
            if case .connected = newValue { dismiss() }
        }
        .sheet(isPresented: $showScanner) {
            scannerSheet
        }
        .sheet(isPresented: $showManualEntry) {
            manualEntrySheet
        }
    }

    // MARK: - Pieces

    private var hero: some View {
        VStack(spacing: 12) {
            Image(systemName: "qrcode.viewfinder")
                .font(.system(size: 54, weight: .regular))
                .foregroundStyle(Theme.textPrimary)
                .padding(.bottom, 4)
            Text("Pair with QR")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
            Text("Scan the code shown by `maverick-hostd --pair` on your Mac to connect over an encrypted channel.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch controller?.state ?? .idle {
        case .idle, .scanning:
            actionCard
        case .handshaking:
            handshakingCard
        case let .confirm(safetyNumber, _):
            confirmCard(safetyNumber: safetyNumber)
        case .connected:
            handshakingCard  // transient; view dismisses via onChange
        case let .failed(message):
            failedCard(message: message)
        }
    }

    private var actionCard: some View {
        VStack(spacing: 12) {
            Button {
                controller?.beginScanning()
                showScanner = true
            } label: {
                pairingButtonLabel(title: "Scan QR Code", icon: "camera.viewfinder")
            }
            .connectButtonStyle()
            .ifNot26 {
                $0.foregroundStyle(.black)
                    .background(Capsule().fill(Theme.accentGradient))
                    .shadow(color: Theme.accent.opacity(0.4), radius: 14, x: 0, y: 6)
            }

            Button {
                manualURL = ""
                showManualEntry = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "keyboard")
                    Text("Enter pairing URL manually")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .foregroundStyle(Theme.textPrimary)
            }
            .buttonStyle(.plain)
            .liquidGlassSurface(cornerRadius: 14, elevation: 0.6)
        }
    }

    private var handshakingCard: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
                .tint(Theme.accent)
            Text("Establishing secure channel…")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .liquidGlassSurface(cornerRadius: 18, elevation: 0.8)
    }

    private func confirmCard(safetyNumber: String) -> some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(Theme.success)
                Text("Verify Safety Number")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text("Confirm this matches the number shown on your Mac.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Text(safetyNumber)
                .font(.system(size: 22, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.vertical, 14)
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Theme.stroke, lineWidth: 1)
                )

            HStack(spacing: 12) {
                Button {
                    controller?.cancel()
                } label: {
                    Text("Cancel")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .foregroundStyle(Theme.textPrimary)
                }
                .buttonStyle(.plain)
                .liquidGlassSurface(cornerRadius: 14, elevation: 0.6)

                Button {
                    controller?.confirm()
                } label: {
                    Text("Confirm")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .ifNot26 {
                            $0.foregroundStyle(.black)
                                .background(Capsule().fill(Theme.accentGradient))
                        }
                }
                .connectButtonStyle()
            }
        }
        .padding(20)
        .liquidGlassSurface(cornerRadius: 18, elevation: 0.8)
    }

    private func failedCard(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 30))
                .foregroundStyle(Theme.danger)
            Text(message)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
            Button {
                controller?.reset()
            } label: {
                Text("Try Again")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .foregroundStyle(Theme.textPrimary)
            }
            .buttonStyle(.plain)
            .liquidGlassSurface(cornerRadius: 14, elevation: 0.6)
        }
        .padding(20)
        .liquidGlassSurface(cornerRadius: 18, elevation: 0.8)
    }

    private func pairingButtonLabel(title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
            Text(title)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 52)
    }

    // MARK: - Scanner sheet

    private var scannerSheet: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            QRScannerView(
                onScan: { raw in
                    showScanner = false
                    Task { await controller?.handleScanned(raw) }
                },
                onError: { _ in
                    // No camera (simulator) or permission denied → fall back to
                    // manual entry so the flow stays testable / usable.
                    showScanner = false
                    showManualEntry = true
                }
            )
            .ignoresSafeArea()

            VStack {
                HStack {
                    Spacer()
                    Button { showScanner = false } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .glassCircleButtonStyle()
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Text("Point the camera at the pairing QR")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.bottom, 40)
            }
            .padding(20)
        }
    }

    // MARK: - Manual-entry sheet

    private var manualEntrySheet: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()
            VStack(spacing: 18) {
                Text("Enter Pairing URL")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text("Paste the `maverick://pair/v1?...` URL printed by your Mac.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)

                TextField("maverick://pair/v1?...", text: $manualURL, axis: .vertical)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.textPrimary)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .lineLimit(3...6)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Theme.stroke, lineWidth: 1)
                    )

                Button {
                    let raw = manualURL.trimmingCharacters(in: .whitespacesAndNewlines)
                    showManualEntry = false
                    Task { await controller?.handleScanned(raw) }
                } label: {
                    Text("Pair")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .ifNot26 {
                            $0.foregroundStyle(.black)
                                .background(Capsule().fill(Theme.accentGradient))
                        }
                }
                .connectButtonStyle()
                .disabled(manualURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(manualURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.6 : 1)

                Spacer()
            }
            .padding(24)
            .padding(.top, 20)
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium])
    }
}
