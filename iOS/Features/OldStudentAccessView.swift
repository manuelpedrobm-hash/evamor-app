import CryptoKit
import SwiftUI

enum OldStudentAccess {
    static let grantedKey = "oldStudentAccessGranted"
    private static let userHash = "082e47439852a9531b45bbfb7600ce7747fb74bb17f4dfd7ff66cbde614382e2"
    private static let passwordHash = "dd7c68a829f421eb1168b74bd02ca680ba5a6a06a8f8e8bd212b2085bfd344c1"

    static func verify(username: String, password: String) -> Bool {
        digest(username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) == userHash &&
        digest(password) == passwordHash
    }

    private static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

struct OldStudentAccessView: View {
    @State private var username = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?
    let grantAccess: () -> Void

    private enum Field { case username, password }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Palette.stone, Palette.limestone.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            ScrollView {
                VStack(spacing: 24) {
                    Spacer(minLength: 52)
                    Image("CompletionArtwork")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 126, height: 126)
                        .accessibilityHidden(true)
                    VStack(spacing: 8) {
                        Text("Acceso para antiguos alumnos")
                            .font(.system(.title2, design: .rounded, weight: .semibold))
                            .multilineTextAlignment(.center)
                        Text("Introduce las credenciales de antiguo alumno para acceder a las sesiones y los audios.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    VStack(spacing: 14) {
                        TextField("Usuario", text: $username)
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.next)
                            .focused($focusedField, equals: .username)
                            .onSubmit { focusedField = .password }
                            .accessibilityIdentifier("oldStudentUsername")
                        SecureField("Contraseña", text: $password)
                            .textContentType(.password)
                            .submitLabel(.go)
                            .focused($focusedField, equals: .password)
                            .onSubmit(authenticate)
                            .accessibilityIdentifier("oldStudentPassword")
                        Label("Recordar acceso en este iPhone", systemImage: "checkmark.circle.fill")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Palette.green)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("oldStudentRememberAccess")
                        if let errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.circle")
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Button(action: authenticate) {
                            Text("Entrar")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 7)
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                        .accessibilityIdentifier("oldStudentLogin")
                    }
                    .textFieldStyle(.roundedBorder)
                    .padding(20)
                    .background(.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    Text("La validación se realiza en este iPhone. Ecuanimidad recuerda que el acceso fue concedido, pero no guarda ni envía la contraseña. Puedes cerrarlo desde Ajustes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Spacer(minLength: 30)
                }
                .padding(.horizontal, 24)
            }
        }
        .tint(Palette.green)
        .onAppear { focusedField = .username }
    }

    private func authenticate() {
        guard OldStudentAccess.verify(username: username, password: password) else {
            password = ""
            errorMessage = "Usuario o contraseña incorrectos."
            focusedField = .password
            return
        }
        errorMessage = nil
        grantAccess()
    }
}
