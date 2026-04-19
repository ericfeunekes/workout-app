// FirstRunView.swift
//
// The root view for the first-run flow. Switches on `FirstRunViewModel.state`
// and renders the appropriate internal card. Copy stays lowercase imperative
// per `docs/design/RULES.md` § "Copywriting rules" — this screen is the
// user's very first impression so consistency with the rest of the app
// matters.
//
// Dark-only (per the app shell's `.preferredColorScheme(.dark)`), tokens
// from DesignSystem throughout.

import SwiftUI
import DesignSystem
import Persistence
import Sync

public struct FirstRunView: View {
    @State private var viewModel: FirstRunViewModel
    @State private var showingQRStub = false

    public init(viewModel: FirstRunViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        ZStack {
            DSColors.background
                .ignoresSafeArea()

            switch viewModel.state {
            case .welcome:
                WelcomeCard(
                    viewModel: viewModel,
                    failure: nil,
                    showingQRStub: $showingQRStub
                )
            case .failed(let reason):
                // Same welcome card — errors render inline under the
                // primary button and never navigate away.
                WelcomeCard(
                    viewModel: viewModel,
                    failure: reason,
                    showingQRStub: $showingQRStub
                )
            case .connecting:
                ConnectingCard()
            case .complete:
                // Transient — the shell should swap us out on `onComplete`.
                // Render nothing rather than a flash of the welcome card.
                // The shell's BootstrapLoadingView ("Syncing…") renders
                // next; see `FirstRunViewModel.connect()` for why the
                // first `/api/sync/pull` lives in AppBootstrap, not here.
                Color.clear
            }
        }
        .sheet(isPresented: $showingQRStub) {
            QRStubSheet()
        }
    }
}

// MARK: - Welcome card

struct WelcomeCard: View {
    @Bindable var viewModel: FirstRunViewModel
    let failure: FirstRunViewModel.FailureReason?
    @Binding var showingQRStub: Bool

    var body: some View {
        VStack(spacing: DSSpacing.xl) {
            Spacer(minLength: 0)

            // Title block — "workoutdb" + subtitle, centered.
            VStack(spacing: DSSpacing.md) {
                Text("workoutdb")
                    .font(DSTypography.display)
                    .foregroundStyle(DSColors.foreground)
                Text("point at your server to begin.")
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColors.foregroundMuted)
                    .multilineTextAlignment(.center)
            }

            // Input stack.
            VStack(spacing: DSSpacing.md) {
                DSInputField(
                    placeholder: "https://server.tailnet-name.ts.net",
                    text: $viewModel.url,
                    isSecure: false
                )
                .textContentType(.URL)
                #if os(iOS)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                #endif

                DSInputField(
                    placeholder: "bearer token",
                    text: $viewModel.token,
                    isSecure: true
                )
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                #endif
            }

            // Primary + ghost buttons stacked. The primary button is
            // disabled while a connect pipeline is in flight — backstops
            // the view-model's re-entrancy guard so double-tapping cannot
            // enqueue two concurrent connect() Tasks.
            VStack(spacing: DSSpacing.md) {
                DSButton(
                    title: "connect",
                    style: .primary,
                    disabled: viewModel.isConnectInFlight,
                    action: { Task { await viewModel.connect() } }
                )
                DSButton(
                    title: "scan qr",
                    style: .ghost,
                    action: { showingQRStub = true }
                )
            }

            // Inline failure banner — only present on `.failed`.
            if let failure {
                FailureBanner(reason: failure)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, DSSpacing.xl)
        .padding(.vertical, DSSpacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Connecting card

struct ConnectingCard: View {
    var body: some View {
        VStack(spacing: DSSpacing.xl) {
            Spacer()
            Text("connecting…")
                .font(DSTypography.title)
                .foregroundStyle(DSColors.foreground)
            ProgressView()
                .progressViewStyle(.circular)
                .tint(DSColors.accent)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, DSSpacing.xl)
    }
}

// MARK: - Failure banner

struct FailureBanner: View {
    let reason: FirstRunViewModel.FailureReason

    var body: some View {
        DSCard {
            HStack(alignment: .top, spacing: DSSpacing.md) {
                Text(message)
                    .font(DSTypography.body)
                    .foregroundStyle(DSColors.warn)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Copy mirrors the brief. Kept lowercase imperative.
    private var message: String {
        switch reason {
        case .tokenRejected:
            return "token rejected — check the token you pasted."
        case .unreachable:
            return "couldn't reach the server. check the url and try again."
        case .decode:
            return "server responded but the shape didn't match — is this the right server?"
        case .invalidURL:
            return "that doesn't look like a valid url. try https://host.ts.net."
        }
    }
}

// MARK: - QR stub

struct QRStubSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            DSColors.background.ignoresSafeArea()
            VStack(spacing: DSSpacing.xl) {
                Spacer()
                Text("qr scan coming in v1.1")
                    .font(DSTypography.title)
                    .foregroundStyle(DSColors.foreground)
                Text("paste the url + token in the meantime.")
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColors.foregroundMuted)
                    .multilineTextAlignment(.center)
                DSButton(
                    title: "got it",
                    style: .primary,
                    action: { dismiss() }
                )
                .padding(.horizontal, DSSpacing.xl)
                Spacer()
            }
            .padding(.horizontal, DSSpacing.xl)
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Shared input field

/// A DesignSystem-styled text / secure field. The design system doesn't
/// ship a primitive for this yet (no other screen needs typed input),
/// so it lives here as an internal helper. If a second consumer appears,
/// promote to `DesignSystem/Primitives/DSInputField.swift` in one move.
struct DSInputField: View {
    let placeholder: String
    @Binding var text: String
    let isSecure: Bool

    var body: some View {
        Group {
            if isSecure {
                SecureField("", text: $text, prompt: promptText)
            } else {
                TextField("", text: $text, prompt: promptText)
            }
        }
        .font(DSTypography.mono)
        .foregroundStyle(DSColors.foreground)
        // Pin the field to the container's full width so a long paste
        // (64+ char bearer token) can't blow out the enclosing card
        // horizontally — qa-023. `lineLimit(1)` + `truncationMode(.middle)`
        // keep the displayed text inside the clip shape; the underlying
        // value is untouched, and SecureField already renders as dots.
        .lineLimit(1)
        .truncationMode(.middle)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DSSpacing.lg)
        .padding(.vertical, DSSpacing.lg)
        .background(DSColors.surfaceElevated)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(DSColors.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var promptText: Text {
        Text(placeholder).foregroundStyle(DSColors.foregroundFaint)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Welcome") {
    FirstRunView(viewModel: FirstRunViewModel(
        tokenStore: PreviewTokenStore(),
        transportBuilder: { _ in PreviewTransport() },
        onComplete: {}
    ))
    .preferredColorScheme(.dark)
}

#Preview("Connecting") {
    let vm = FirstRunViewModel(
        tokenStore: PreviewTokenStore(),
        transportBuilder: { _ in PreviewTransport() },
        onComplete: {}
    )
    vm.state = .connecting
    return FirstRunView(viewModel: vm).preferredColorScheme(.dark)
}

#Preview("Failed — token rejected") {
    let vm = FirstRunViewModel(
        tokenStore: PreviewTokenStore(),
        transportBuilder: { _ in PreviewTransport() },
        onComplete: {}
    )
    vm.url = "https://host.ts.net"
    vm.token = "bad"
    vm.state = .failed(reason: .tokenRejected)
    return FirstRunView(viewModel: vm).preferredColorScheme(.dark)
}

/// Visual regression check for qa-023: long bearer token must not blow
/// out the input field horizontally. Token is 64 chars of hex.
#Preview("Welcome — 64-char token pasted") {
    let vm = FirstRunViewModel(
        tokenStore: PreviewTokenStore(),
        transportBuilder: { _ in PreviewTransport() },
        onComplete: {}
    )
    vm.url = "https://very-long-tailnet-name.example.ts.net"
    vm.token = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
    return FirstRunView(viewModel: vm).preferredColorScheme(.dark)
}

private struct PreviewTokenStore: TokenStore {
    func saveConnection(url: URL, token: String) throws {}
    func loadConnection() throws -> (url: URL, token: String)? { nil }
    func clear() throws {}
}

private struct PreviewTransport: HTTPTransport {
    func get(path: String, query: [(String, String)], bearerToken: String) async throws -> HTTPResponse {
        HTTPResponse(status: 200, body: Data())
    }
    func post(path: String, body: Data, bearerToken: String) async throws -> HTTPResponse {
        HTTPResponse(status: 200, body: Data())
    }
}

#endif
