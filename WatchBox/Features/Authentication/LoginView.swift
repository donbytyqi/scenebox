//
//  LoginView.swift
//  SceneBox
//
//  Created by SpontaneousArray on 01.08.26.
//

import SwiftUI

struct LoginView: View {
    var isSheet = false
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var isCreating = false
    @State private var config = FirebaseConfigStore.shared

    private var canSubmit: Bool {
        !auth.isWorking && !email.isEmpty && password.count >= 6
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            if config.isConfigured {
                signInForm
            } else {
                setupGuide
            }

            if isSheet {
                VStack {
                    HStack {
                        Spacer()
                        Button("Cancel") { dismiss() }
                            .foregroundStyle(.white)
                            .padding()
                    }
                    Spacer()
                }
            }
        }
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.15), value: isCreating)
        .alert(isCreating ? "Couldn't create account" : "Couldn't sign in",
               isPresented: showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(auth.errorMessage ?? "")
        }
    }

    private var signInForm: some View {
        VStack(spacing: 18) {
            header
            fields
            submitButton
            switchModeButton
            if !isSheet {
                guestButton
            }
        }
        .frame(maxWidth: 460)
        .padding(.horizontal, 24)
    }

    /// Without a Firebase project there is nothing to sign in to, so this screen
    /// becomes the guide for supplying one — with guest mode still reachable.
    private var setupGuide: some View {
        VStack(spacing: 0) {
            FirebaseSetupView()
            if !isSheet {
                guestButton
                    .padding(.bottom, 24)
            }
        }
    }

    private var showError: Binding<Bool> {
        Binding(get: { auth.errorMessage != nil },
                set: { if !$0 { auth.clearError() } })
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 8) {
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 88, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            Text("SceneBox")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(.white)
            Text(isCreating ? "Create your account" : "Sign in to continue")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 12)
    }

    private var fields: some View {
        VStack(spacing: 12) {
            TextField("Email", text: $email)
                .textContentType(.emailAddress)
                #if os(iOS)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
                .modifier(FieldStyle())

            SecureField("Password", text: $password)
                .textContentType(isCreating ? .newPassword : .password)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .modifier(FieldStyle())
                .onSubmit(submit)
        }
    }

    private var submitButton: some View {
        Button(action: submit) {
            ZStack {
                if auth.isWorking {
                    ProgressView().tint(Theme.onAccent)
                } else {
                    Text(isCreating ? "Create account" : "Sign in").fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.accent)
        .foregroundStyle(Theme.onAccent)
        .disabled(!canSubmit)
    }

    private var guestButton: some View {
        Button {
            auth.continueAsGuest()
        } label: {
            Text("Continue as guest")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.8))
        }
        .buttonStyle(.plain)
        .padding(.top, 12)
    }

    private var switchModeButton: some View {
        Button {
            isCreating.toggle()
            auth.clearError()
        } label: {
            Text(isCreating ? "Already have an account? Sign in"
                            : "New here? Create an account")
                .font(.footnote)
                .foregroundStyle(Theme.accent)
        }
        .buttonStyle(.plain)
    }

    private func submit() {
        guard canSubmit else { return }
        Task {
            if isCreating {
                await auth.createAccount(email: email, password: password)
            } else {
                await auth.signIn(email: email, password: password)
            }
        }
    }
}

private struct FieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .foregroundStyle(.white)
            .tint(.white)
            .padding()
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
