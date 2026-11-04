import SwiftUI
import HustlerCore

/// The launch gate. The Keychain decides first: no stored session shows the
/// sign-in screen and nothing else, while a stored session opens the app at
/// once, with or without a network. The refresh runs behind the open app, so
/// local data never waits on it.
@MainActor
final class SessionGateModel: ObservableObject {
    enum Phase: Equatable { case signIn, app }

    @Published private(set) var phase: Phase
    @Published var email = ""
    @Published var password = ""
    @Published private(set) var message: String?
    @Published private(set) var busy = false

    let account: SupabaseAccount
    private var started = false

    init(storage: SessionStorage = KeychainSessionStorage()) {
        account = SupabaseAccount(storage: storage)
        phase = SessionGate.atLaunch(session: account.storedSession) == .app ? .app : .signIn
    }

    /// Once per launch, after the first frame: refresh behind the app and send
    /// the phone back to the gate only if the server refused the session.
    func start() async {
        guard !started, phase == .app else { return }
        started = true
        phase = SessionGate.after(await account.refreshSessionIfNeeded()) == .app ? .app : .signIn
    }

    /// Sign in only: there is no sign-up here, and the password stays in the
    /// field, never saved, logged or put in a URL.
    func signIn() async {
        let address = email.trimmingCharacters(in: .whitespaces)
        guard !busy, !address.isEmpty, !password.isEmpty else { return }
        let secret = password
        busy = true
        message = nil
        do {
            try await account.signIn(email: address, password: secret)
            password = ""
            phase = .app
        } catch {
            message = error.localizedDescription
        }
        busy = false
    }

    /// Signing out clears this device's session only: the log, the archive and
    /// the settings stay where they are.
    func signOut() {
        account.signOut()
        email = ""
        password = ""
        message = nil
        phase = .signIn
    }
}

struct SessionGateView: View {
    @StateObject private var model = SessionGateModel()

    var body: some View {
        switch model.phase {
        case .signIn:
            SignInView(model: model)
        case .app:
            RootView(onSignedOut: { model.signOut() })
                .task { await model.start() }
        }
    }
}

/// Email, password, Sign in and the reason the last try failed. No sign-up.
private struct SignInView: View {
    @ObservedObject var model: SessionGateModel
    @FocusState private var focused: Field?

    private enum Field { case email, password }

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 6) {
                Text("Hustler").font(.largeTitle.bold())
                Text("Sign in to continue").font(.subheadline).foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                TextField("Email", text: $model.email)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focused, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { focused = .password }
                SecureField("Password", text: $model.password)
                    .textContentType(.password)
                    .focused($focused, equals: .password)
                    .submitLabel(.go)
                    .onSubmit { Task { await model.signIn() } }
            }
            .textFieldStyle(.roundedBorder)

            Button {
                Task { await model.signIn() }
            } label: {
                if model.busy {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Text("Sign in").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.busy || model.email.isEmpty || model.password.isEmpty)

            if let message = model.message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .padding(24)
        .onAppear { focused = .email }
    }
}
