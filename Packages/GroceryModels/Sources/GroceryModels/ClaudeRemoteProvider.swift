import GroceryDomain

public protocol ClaudeResponder: Sendable {
    func availability() async -> RemoteProviderState
    func respond(
        to invocation: RemoteGroceryInvocation,
        apiKey: String
    ) async throws -> RemoteProviderResponse
}

public enum ClaudeProviderError: Error, Sendable, Equatable {
    case notConfigured
    case sharedBatonPassUnavailable
}

public struct UnavailableClaudeResponder: ClaudeResponder, Sendable {
    public init() {}

    public func availability() async -> RemoteProviderState { .unavailable }

    public func respond(
        to invocation: RemoteGroceryInvocation,
        apiKey: String
    ) async throws -> RemoteProviderResponse {
        throw ClaudeProviderError.notConfigured
    }
}

/// Authentication-aware seam for the Claude Foundation Models adapter.
///
/// The responder is deliberately injected. The app can use a real Claude
/// session adapter when the beta package is available, while tests use a fake
/// responder and never need a credential or network request.
public struct ClaudeRemoteProvider: SharedBatonPassRemoteProvider, Sendable {
    public let provider: ModelProvider = .claude

    private let credentialStore: any ClaudeCredentialStore
    private let responder: any ClaudeResponder

    public init(
        credentialStore: any ClaudeCredentialStore,
        responder: any ClaudeResponder
    ) {
        self.credentialStore = credentialStore
        self.responder = responder
    }

    public func availability() async -> RemoteProviderState {
        guard await credentialStore.hasCredential() else { return .notConfigured }
        return await responder.availability()
    }

    public func respond(
        to invocation: RemoteGroceryInvocation
    ) async throws -> RemoteProviderResponse {
        guard let apiKey = await credentialStore.credential() else {
            throw ClaudeProviderError.notConfigured
        }
        return try await responder.respond(to: invocation, apiKey: apiKey)
    }

    public func respondWithSharedBatonPass(
        for request: GroceryRequest,
        household: DemoHousehold?
    ) async throws -> SharedBatonPassResponse {
        guard let apiKey = await credentialStore.credential() else {
            throw ClaudeProviderError.notConfigured
        }
        guard let responder = responder as? any ClaudeSharedBatonPassResponder else {
            throw ClaudeProviderError.sharedBatonPassUnavailable
        }
        return try await responder.respondWithSharedBatonPass(
            for: request,
            household: household,
            apiKey: apiKey
        )
    }
}
