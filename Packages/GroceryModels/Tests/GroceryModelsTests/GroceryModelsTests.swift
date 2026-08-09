import Testing
import GroceryDomain
@testable import GroceryModels

struct GroceryModelsTests {
    @Test func localAssistantReturnsAnEvidenceBackedRun() async {
        let catalog = TestCatalog(products: [CatalogProduct(name: "Green lentils", detail: "A pantry staple.")])
        let run = await LocalGroceryAssistant(catalog: catalog).answer(for: GroceryRequest(text: "lentils"))

        #expect(run.answer.text.contains("Green lentils"))
        #expect(run.answer.evidence == ["Green lentils"])
    }

    @Test func localAssistantRecordsSelectedHouseholdAndToolActivity() async {
        let catalog = TestCatalog(products: [CatalogProduct(name: "Green lentils", detail: "A pantry staple.")])
        let household = DemoHousehold(
            id: .lowWasteSoloShopper,
            name: "Low-Waste Solo Shopper",
            members: [],
            weeklySpendingTargetCents: nil,
            restrictions: [.vegetarian],
            priorities: [.usePantryFirst],
            purchaseHistory: [],
            pantry: [],
            cart: []
        )

        let run = await LocalGroceryAssistant(catalog: catalog).answer(
            for: GroceryRequest(text: "lentils"),
            household: household
        )

        #expect(run.trace.householdID == .lowWasteSoloShopper)
        #expect(run.trace.strategy == .localOnly)
        #expect(run.events.map(\.kind) == [.toolCall, .toolOutput, .finalAnswer])
    }

    @Test func localPolicySelectsCatalogOnlyProductDiscoveryProfile() async {
        let catalog = TestCatalog(products: [CatalogProduct(name: "Green lentils", detail: "A pantry staple.")])
        let run = await LocalGroceryAssistant(catalog: catalog).answer(
            for: GroceryRequest(text: "Find lentils")
        )

        #expect(run.trace.intentID == "product-discovery")
        #expect(run.trace.tools == ["search-catalog"])
        #expect(run.trace.profileActivations == [
            ModelProfileActivation(
                profile: .localProductDiscovery,
                trigger: "application-state:product-discovery",
                effectiveInstructions: [
                    "Use only bundled catalog evidence and say when no matching product is available."
                ],
                tools: ["search-catalog"],
                selectedModel: "deterministic-test-assistant",
                ownsFinalAnswer: false
            )
        ])
        #expect(run.trace.remoteContextView == nil)
        #expect(run.trace.remoteSessionID == nil)
    }

    @Test func localPolicySelectsHouseholdPlanningProfileForPantryRequest() async {
        let catalog = TestCatalog(products: [CatalogProduct(name: "Green lentils", detail: "A pantry staple.")])
        let household = DemoHousehold(
            id: .lowWasteSoloShopper,
            name: "Low-Waste Solo Shopper",
            members: [],
            weeklySpendingTargetCents: nil,
            restrictions: [.vegetarian],
            priorities: [.usePantryFirst],
            purchaseHistory: [],
            pantry: [PantryItem(productID: ProductID("green-lentils"), quantity: 2)],
            cart: []
        )
        let run = await LocalGroceryAssistant(catalog: catalog).answer(
            for: GroceryRequest(text: "Plan a meal from my pantry"),
            household: household
        )

        #expect(run.trace.intentID == "household-planning")
        #expect(run.trace.activeProfiles == [.localHouseholdPlanning])
        #expect(run.trace.tools == ["household-context", "search-catalog"])
        #expect(run.trace.profileActivations.first?.effectiveInstructions == [
            "Use the selected Demo Household's restrictions, priorities, pantry, and purchase evidence.",
            "Use only bundled catalog evidence for product claims."
        ])
        #expect(run.trace.toolEvents.map(\.label).contains("household-context"))
        #expect(run.trace.remoteContextView == nil)
    }

    @Test func localPolicySelectsNonMutatingCartReviewProfile() async {
        let catalog = TestCatalog(products: [CatalogProduct(name: "Green lentils", detail: "A pantry staple.")])
        let run = await LocalGroceryAssistant(catalog: catalog).answer(
            for: GroceryRequest(text: "Review my cart")
        )

        #expect(run.trace.intentID == "cart-review")
        #expect(run.trace.activeProfiles == [.localCartReview])
        #expect(run.trace.profileActivations.first?.trigger == "application-state:cart-review")
        #expect(run.trace.profileActivations.first?.effectiveInstructions.first ==
            "Call household-context before reviewing the selected Demo Household's cart.")
        #expect(run.trace.profileActivations.first?.tools == ["household-context"])
        #expect(run.trace.toolEvents.map(\.label).contains("household-context"))
        #expect(!run.trace.toolEvents.map(\.label).contains("search-catalog"))
        #expect(run.trace.profileActivations.first?.ownsFinalAnswer == false)
    }

    @Test func hybridAssistantExplainsWhenClaudeIsNotConfigured() async {
        let provider = TestRemoteProvider(state: .notConfigured)
        let assistant = HybridGroceryAssistant(
            localAssistant: TestLocalAssistant(),
            provider: provider
        )

        let run = await assistant.answer(for: GroceryRequest(text: "find lentils"))

        #expect(run.answer.text == "Hybrid assistance is not configured. Add a Claude credential to continue.")
        #expect(run.trace.strategy == .hybrid)
        #expect(run.trace.provider == .claude)
        #expect(run.trace.error == "claude-not-configured")
        #expect(run.events.map(\.kind) == [.error, .finalAnswer])
    }

    @Test func hybridAssistantUsesAConfiguredFakeProviderWithoutCredentials() async {
        let provider = TestRemoteProvider(
            state: .ready,
            response: RemoteProviderResponse(
                answer: GroceryAnswer(text: "Use the lentils already in the pantry.", evidence: ["Green lentils"]),
                events: [ModelRunEvent(kind: .toolOutput, label: "public-catalog", content: "Green lentils")],
                tools: ["public-catalog"]
            )
        )
        let assistant = HybridGroceryAssistant(
            localAssistant: TestLocalAssistant(),
            provider: provider
        )

        let run = await assistant.answer(
            for: GroceryRequest(text: "find lentils"),
            household: DemoHousehold(
                id: .lowWasteSoloShopper,
                name: "Low-Waste Solo Shopper",
                members: [],
                weeklySpendingTargetCents: nil,
                restrictions: [.vegetarian],
                priorities: [.usePantryFirst],
                purchaseHistory: [],
                pantry: [],
                cart: []
            )
        )

        #expect(run.answer.text == "Use the lentils already in the pantry.")
        #expect(run.trace.strategy == .hybrid)
        #expect(run.trace.provider == .claude)
        #expect(run.trace.householdID == .lowWasteSoloShopper)
        #expect(run.trace.remoteContextView?.contains("Pattern: baton-pass") == true)
        #expect(run.events.map(\.kind) == [.toolOutput, .finalAnswer])
    }

    @Test func batonPassSharesObservableLocalHistoryAndRecordsTheRemoteTransition() async {
        let localRun = ModelRun(
            request: GroceryRequest(text: "find lentils"),
            answer: GroceryAnswer(text: "The pantry already has lentils."),
            events: [
                ModelRunEvent(kind: .toolCall, label: "household-context", content: "pantry=green-lentils"),
                ModelRunEvent(kind: .toolOutput, label: "household-context", content: "Green lentils ×2"),
                ModelRunEvent(kind: .finalAnswer, label: "answer", content: "The pantry already has lentils.")
            ],
            trace: ModelTrace(
                strategy: .localOnly,
                provider: .appleOnDevice,
                householdID: .lowWasteSoloShopper,
                intentID: "catalog-and-household",
                tools: ["household-context"],
                toolEvents: [
                    ModelRunEvent(kind: .toolCall, label: "household-context", content: "pantry=green-lentils"),
                    ModelRunEvent(kind: .toolOutput, label: "household-context", content: "Green lentils ×2")
                ]
            )
        )
        let provider = TestRemoteProvider(
            state: .ready,
            response: RemoteProviderResponse(
                answer: GroceryAnswer(text: "Use the lentils already in the pantry."),
                events: [ModelRunEvent(kind: .toolOutput, label: "public-catalog", content: "Green lentils")],
                tools: ["public-catalog"]
            )
        )
        let assistant = HybridGroceryAssistant(
            localAssistant: TestLocalAssistant(run: localRun),
            provider: provider
        )

        let run = await assistant.answer(
            for: GroceryRequest(text: "find lentils"),
            household: DemoHousehold(
                id: .lowWasteSoloShopper,
                name: "Low-Waste Solo Shopper",
                members: [],
                weeklySpendingTargetCents: nil,
                restrictions: [.vegetarian],
                priorities: [.usePantryFirst],
                purchaseHistory: [],
                pantry: [],
                cart: []
            )
        )

        let invocation = await provider.lastInvocation
        #expect(invocation?.contextView.pattern == .batonPass)
        #expect(invocation?.contextView.sharedHistory.contains {
            $0.content == "Green lentils ×2"
        } == true)
        #expect(invocation?.contextView.privacyConcerns.contains {
            $0.contains("App-Owned Context")
        } == true)
        #expect(run.answer.text == "Use the lentils already in the pantry.")
        #expect(run.trace.orchestrationPattern == .batonPass)
        #expect(run.trace.profileTransitions == [
            ModelProfileTransition(from: .localGrocery, to: .claudeGrocery)
        ])
        #expect(run.trace.finalAnswerProfile == .claudeGrocery)
        #expect(run.trace.correlationID == invocation?.correlationID)
        #expect(run.trace.remoteContextID == invocation?.remoteContextID)
        #expect(invocation?.contextView.toolOutputs.map(\.content) == ["Green lentils ×2"])
        #expect(invocation?.contextView.selectedOptions.contains("history=shared") == true)
        #expect(run.trace.remoteContextView == invocation?.contextView.rendered)
        #expect(run.events.map(\.kind) == [.toolCall, .toolOutput, .modelOutput, .toolOutput, .finalAnswer])
        #expect(run.events.last?.label == "claude-answer")
    }

    @Test func batonPassKeepsDisclosureFactsWhenTheRemoteRequestFails() async {
        let localRun = ModelRun(
            request: GroceryRequest(text: "find lentils"),
            answer: GroceryAnswer(text: "The pantry already has lentils."),
            events: [
                ModelRunEvent(kind: .toolOutput, label: "household-context", content: "Green lentils ×2"),
                ModelRunEvent(kind: .finalAnswer, label: "answer", content: "The pantry already has lentils.")
            ],
            trace: ModelTrace(
                strategy: .localOnly,
                provider: .appleOnDevice,
                householdID: .lowWasteSoloShopper,
                intentID: "catalog-and-household",
                tools: ["household-context"],
                toolEvents: [
                    ModelRunEvent(kind: .toolOutput, label: "household-context", content: "Green lentils ×2")
                ]
            )
        )
        let provider = TestRemoteProvider(
            state: .ready,
            failure: .transportFailed
        )
        let assistant = HybridGroceryAssistant(
            localAssistant: TestLocalAssistant(run: localRun),
            provider: provider
        )

        let run = await assistant.answer(for: GroceryRequest(text: "find lentils"))

        #expect(run.trace.error == "claude-request-failed")
        #expect(run.trace.orchestrationPattern == .batonPass)
        #expect(run.trace.remoteContextView?.contains("Green lentils ×2") == true)
        #expect(run.trace.toolEvents.map(\.label) == ["household-context"])
        #expect(run.events.map(\.kind) == [.toolOutput, .modelOutput, .error, .finalAnswer])
    }

    @Test func phoneAFriendUsesAnIsolatedValidatedTaskAndKeepsFinalAnswerWithTheParent() async {
        let localRun = ModelRun(
            request: GroceryRequest(text: "Find a lower-sugar cereal"),
            answer: GroceryAnswer(text: "The household prefers lower sugar."),
            events: [
                ModelRunEvent(kind: .toolCall, label: "search-catalog", content: "Find a lower-sugar cereal"),
                ModelRunEvent(kind: .toolOutput, label: "search-catalog", content: "Plain oats"),
                ModelRunEvent(kind: .toolOutput, label: "household-context", content: "lower-sugar"),
                ModelRunEvent(kind: .finalAnswer, label: "answer", content: "The household prefers lower sugar.")
            ],
            trace: ModelTrace(
                strategy: .localOnly,
                provider: .appleOnDevice,
                householdID: .nutritionFocusedCouple,
                intentID: "catalog-and-household",
                tools: ["search-catalog", "household-context"],
                toolEvents: [
                    ModelRunEvent(kind: .toolCall, label: "search-catalog", content: "Find a lower-sugar cereal"),
                    ModelRunEvent(kind: .toolOutput, label: "search-catalog", content: "Plain oats"),
                    ModelRunEvent(kind: .toolOutput, label: "household-context", content: "lower-sugar")
                ]
            )
        )
        let provider = TestRemoteProvider(
            state: .ready,
            response: RemoteProviderResponse(
                answer: GroceryAnswer(text: "Plain oats are the narrowest public-catalog match."),
                events: [ModelRunEvent(kind: .toolOutput, label: "public-catalog", content: "Plain oats")],
                tools: ["public-catalog"]
            )
        )
        let assistant = HybridGroceryAssistant(
            localAssistant: TestLocalAssistant(run: localRun),
            provider: provider,
            pattern: .phoneAFriend,
            parentAnswerer: TestPhoneParentAnswerer(
                answer: GroceryAnswer(text: "The local parent recommends plain oats while respecting lower-sugar priorities.")
            )
        )

        let run = await assistant.answer(
            for: GroceryRequest(text: "Find a lower-sugar cereal"),
            household: DemoHousehold(
                id: .nutritionFocusedCouple,
                name: "Nutrition-Focused Couple",
                members: [],
                weeklySpendingTargetCents: nil,
                restrictions: [.lactoseIntolerance],
                priorities: [.lowerSugar],
                purchaseHistory: [],
                pantry: [],
                cart: []
            )
        )

        let invocation = await provider.lastInvocation
        #expect(invocation?.contextView.pattern == .phoneAFriend)
        #expect(invocation?.contextView.sessionOwnership == .isolatedChild)
        #expect(invocation?.session.ownership == .isolatedChild)
        #expect(invocation?.sessionID != invocation?.parentSessionID)
        #expect(invocation?.contextView.remoteTask?.instructionText == "Use only public catalog evidence to help the parent answer: Find a lower-sugar cereal")
        #expect(invocation?.contextView.sharedHistory.isEmpty == true)
        #expect(invocation?.contextView.toolOutputs.map(\.content) == ["Plain oats"])
        #expect(invocation?.contextView.toolDefinitions == ["public-catalog"])
        #expect(invocation?.contextView.selectedOptions.contains("history=isolated-child") == true)
        #expect(invocation?.contextView.selectedOptions.contains("final-answer-owner=local-grocery") == true)
        #expect(invocation?.contextView.privacyConcerns.contains {
            $0.contains("Narrower")
        } == true)
        #expect(run.answer.text == "The local parent recommends plain oats while respecting lower-sugar priorities.")
        #expect(run.trace.orchestrationPattern == .phoneAFriend)
        #expect(run.trace.activeProfiles == [.localGrocery, .claudeChildGrocery])
        #expect(run.trace.profileTransitions == [
            ModelProfileTransition(from: .localGrocery, to: .claudeChildGrocery),
            ModelProfileTransition(from: .claudeChildGrocery, to: .localGrocery)
        ])
        #expect(run.trace.finalAnswerProfile == .localGrocery)
        #expect(run.trace.remoteSessionID == invocation?.sessionID)
        #expect(run.trace.parentRemoteSessionID == invocation?.parentSessionID)
        #expect(run.trace.remoteContextView == invocation?.contextView.rendered)
        #expect(run.events.last?.kind == .finalAnswer)
        #expect(run.events.last?.label == "local-parent-answer")
    }

    @Test func phoneAFriendRejectsAnInvalidTaskBeforeCallingTheRemoteProvider() async {
        let provider = TestRemoteProvider(state: .ready)
        let assistant = HybridGroceryAssistant(
            localAssistant: TestLocalAssistant(),
            provider: provider,
            pattern: .phoneAFriend
        )

        let run = await assistant.answer(for: GroceryRequest(text: " \n"))

        #expect(run.trace.error == "phone-friend-task-invalid")
        #expect(run.trace.orchestrationPattern == nil)
        #expect(run.trace.remoteContextView == nil)
        #expect(run.events.map(\.kind) == [.error, .finalAnswer])
        #expect(await provider.lastInvocation == nil)
    }

    @Test func phoneAFriendFailsClosedWhenTheChildReturnsAnUndisclosedTool() async {
        let provider = TestRemoteProvider(
            state: .ready,
            response: RemoteProviderResponse(
                answer: GroceryAnswer(text: "unused"),
                tools: ["private-household"]
            )
        )
        let assistant = HybridGroceryAssistant(
            localAssistant: TestLocalAssistant(),
            provider: provider,
            pattern: .phoneAFriend
        )

        let run = await assistant.answer(for: GroceryRequest(text: "Find cereal"))

        #expect(run.trace.error == "claude-disallowed-tool")
        #expect(run.trace.orchestrationPattern == .phoneAFriend)
        #expect(run.trace.remoteContextView?.contains("Session ownership: isolated-child-session") == true)
        #expect(run.events.last?.kind == .finalAnswer)
    }

    @Test func claudeProviderReportsSetupStateAndPassesCredentialOnlyToItsResponder() async throws {
        let credentials = TestClaudeCredentialStore(apiKey: "configured-key")
        let responder = TestClaudeResponder()
        let provider = ClaudeRemoteProvider(credentialStore: credentials, responder: responder)

        #expect(await provider.availability() == .ready)
        let response = try await provider.respond(
            to: RemoteGroceryInvocation(
                contextView: RemoteContextView(
                    pattern: .batonPass,
                    instructions: "Answer the grocery request.",
                    prompt: "lentils",
                    sharedHistory: [],
                    toolDefinitions: [],
                    privacyConcerns: []
                )
            )
        )

        #expect(response.answer.text == "Remote lentil answer")
        #expect(await responder.lastCredential == "configured-key")
    }

    @Test func liveClaudeResponderMapsSharedDynamicProfileContextAndStreamingText() async throws {
        let toolEvents = [
            ModelRunEvent(kind: .toolCall, label: "public-catalog", content: "lentils"),
            ModelRunEvent(kind: .toolOutput, label: "public-catalog", content: "Green lentils")
        ]
        let sessions = TestClaudeSessionFactory(
            events: [
                .snapshot("Use"),
                .modelRun(toolEvents[0]),
                .modelRun(toolEvents[1]),
                .snapshot("Use lentils")
            ]
        )
        let responder = ClaudeFoundationModelsResponder(sessionFactory: sessions)
        let invocation = RemoteGroceryInvocation(
            contextView: RemoteContextView(
                pattern: .batonPass,
                instructions: "Use only approved grocery evidence.",
                prompt: "What should I cook?",
                sharedHistory: [
                    RemoteHistoryEntry(role: .assistant, label: "local-answer", content: "Start with lentils.")
                ],
                toolDefinitions: ["public-catalog"],
                toolOutputs: [
                    RemoteHistoryEntry(role: .toolOutput, label: "public-catalog", content: "Green lentils")
                ],
                privacyConcerns: []
            )
        )

        let response = try await responder.respond(to: invocation, apiKey: "runtime-key")
        let request = try #require(await sessions.lastRequest)

        #expect(request.kind == .sharedDynamicProfile)
        #expect(request.sessionID == invocation.sessionID)
        #expect(request.instructions == "Use only approved grocery evidence.")
        #expect(request.prompt.contains("What should I cook?"))
        #expect(request.prompt.contains("Start with lentils."))
        #expect(request.prompt.contains("Green lentils"))
        #expect(request.toolNames == ["public-catalog"])
        #expect(await sessions.lastAPIKey == "runtime-key")
        #expect(response.answer.text == "Use lentils")
        #expect(response.events == [
            ModelRunEvent(kind: .modelOutput, label: "claude-stream", content: "Use"),
            toolEvents[0],
            toolEvents[1],
            ModelRunEvent(kind: .modelOutput, label: "claude-stream", content: " lentils")
        ])
    }

    @Test func liveClaudeResponderBuildsIsolatedChildWithoutSharedPrivateHistory() async throws {
        let sessions = TestClaudeSessionFactory(snapshots: ["Choose oats"])
        let responder = ClaudeFoundationModelsResponder(sessionFactory: sessions)
        let task = try RemoteTask(request: GroceryRequest(text: "Find a public cereal alternative"))
        let invocation = RemoteGroceryInvocation(
            contextView: RemoteContextView(
                pattern: .phoneAFriend,
                sessionOwnership: .isolatedChild,
                instructions: "Complete only the validated Remote Task.",
                prompt: "",
                sharedHistory: [
                    RemoteHistoryEntry(role: .toolOutput, label: "household-context", content: "peanut allergy")
                ],
                toolDefinitions: ["public-catalog"],
                toolOutputs: [
                    RemoteHistoryEntry(role: .toolOutput, label: "public-catalog", content: "Plain oats")
                ],
                remoteTask: task,
                privacyConcerns: []
            ),
            session: RemoteSession(
                ownership: .isolatedChild,
                parentID: "parent-session"
            )
        )

        _ = try await responder.respond(to: invocation, apiKey: "runtime-key")
        let request = try #require(await sessions.lastRequest)

        #expect(request.kind == .isolatedChild)
        #expect(request.prompt.contains(task.instructionText))
        #expect(request.prompt.contains("Plain oats"))
        #expect(!request.prompt.contains("peanut allergy"))
        #expect(request.toolNames == ["public-catalog"])
    }

    @Test func liveClaudeResponderPreservesPartialTextWhenTheStreamFails() async throws {
        let sessions = TestClaudeSessionFactory(
            snapshots: ["Partial answer"],
            completion: .failed
        )
        let responder = ClaudeFoundationModelsResponder(sessionFactory: sessions)

        do {
            _ = try await responder.respond(to: testClaudeInvocation(), apiKey: "runtime-key")
            Issue.record("Expected the failed stream to throw")
        } catch let failure as RemoteProviderFailure {
            #expect(failure == .incomplete(events: [
                ModelRunEvent(kind: .modelOutput, label: "claude-stream", content: "Partial answer")
            ]))
        }
    }

    @Test func liveClaudeResponderMapsCancellationWithoutLeakingProviderErrors() async throws {
        let sessions = TestClaudeSessionFactory(
            snapshots: [],
            completion: .cancelled
        )
        let responder = ClaudeFoundationModelsResponder(sessionFactory: sessions)

        do {
            _ = try await responder.respond(to: testClaudeInvocation(), apiKey: "runtime-key")
            Issue.record("Expected cancellation to throw")
        } catch let failure as RemoteProviderFailure {
            #expect(failure == .cancelled(events: []))
        }
    }

    @Test func liveClaudeResponderPreservesToolEventsWhenTheFinalTextIsEmpty() async throws {
        let toolEvent = ModelRunEvent(
            kind: .toolOutput,
            label: "public-catalog",
            content: "Green lentils"
        )
        let sessions = TestClaudeSessionFactory(
            events: [.modelRun(toolEvent), .snapshot("   ")]
        )
        let responder = ClaudeFoundationModelsResponder(sessionFactory: sessions)

        do {
            _ = try await responder.respond(to: testClaudeInvocation(), apiKey: "runtime-key")
            Issue.record("Expected an empty final answer to be incomplete")
        } catch let failure as RemoteProviderFailure {
            #expect(failure == .incomplete(events: [toolEvent, ModelRunEvent(
                kind: .modelOutput,
                label: "claude-stream",
                content: "   "
            )]))
        }
    }

    @Test func hybridAssistantKeepsIncompleteClaudeOutputInTheFailedModelRun() async {
        let partialEvent = ModelRunEvent(kind: .modelOutput, label: "claude-stream", content: "Partial answer")
        let toolEvent = ModelRunEvent(kind: .toolOutput, label: "public-catalog", content: "Green lentils")
        let assistant = HybridGroceryAssistant(
            localAssistant: TestLocalAssistant(),
            provider: FailingRemoteProvider(
                failure: .incomplete(events: [partialEvent, toolEvent])
            )
        )

        let run = await assistant.answer(for: GroceryRequest(text: "Find lentils"))

        #expect(run.trace.error == "claude-request-incomplete")
        #expect(run.events.contains(partialEvent))
        #expect(run.trace.tools.contains("public-catalog"))
        #expect(run.events.last?.kind == .finalAnswer)
    }

    @Test func hybridAssistantRecordsCancellationAsASafeVisibleFailure() async {
        let assistant = HybridGroceryAssistant(
            localAssistant: TestLocalAssistant(),
            provider: FailingRemoteProvider(failure: .cancelled(events: []))
        )

        let run = await assistant.answer(for: GroceryRequest(text: "Find lentils"))

        #expect(run.trace.error == "claude-request-cancelled")
        #expect(run.answer.text == "Hybrid assistance was cancelled.")
        #expect(run.trace.tools.contains("public-catalog"))
        #expect(run.events.map(\.kind).suffix(2) == [.error, .finalAnswer])
    }

    @Test func hybridAssistantKeepsDisclosedToolsOnGenericProviderFailure() async {
        let assistant = HybridGroceryAssistant(
            localAssistant: TestLocalAssistant(),
            provider: FailingRemoteProvider(failure: .failed)
        )

        let run = await assistant.answer(for: GroceryRequest(text: "Find lentils"))

        #expect(run.trace.error == "claude-request-failed")
        #expect(run.trace.tools.contains("public-catalog"))
    }
}

private func testClaudeInvocation() -> RemoteGroceryInvocation {
    RemoteGroceryInvocation(
        contextView: RemoteContextView(
            pattern: .batonPass,
            instructions: "Answer from public evidence.",
            prompt: "lentils",
            sharedHistory: [],
            toolDefinitions: ["public-catalog"],
            privacyConcerns: []
        )
    )
}

private actor TestRemoteProvider: RemoteGroceryProvider {
    let state: RemoteProviderState
    let response: RemoteProviderResponse
    let failure: TestRemoteProviderError?
    private(set) var lastInvocation: RemoteGroceryInvocation?

    init(
        state: RemoteProviderState,
        response: RemoteProviderResponse? = nil,
        failure: TestRemoteProviderError? = nil
    ) {
        self.state = state
        self.response = response ?? RemoteProviderResponse(answer: GroceryAnswer(text: "unused"))
        self.failure = failure
    }

    nonisolated var provider: ModelProvider { .claude }

    func availability() async -> RemoteProviderState { state }

    func respond(
        to invocation: RemoteGroceryInvocation
    ) async throws -> RemoteProviderResponse {
        lastInvocation = invocation
        if let failure {
            throw failure
        }
        return response
    }
}

private enum TestRemoteProviderError: Error, Sendable {
    case transportFailed
}

private struct FailingRemoteProvider: RemoteGroceryProvider {
    let failure: RemoteProviderFailure
    var provider: ModelProvider { .claude }

    func availability() async -> RemoteProviderState { .ready }

    func respond(to invocation: RemoteGroceryInvocation) async throws -> RemoteProviderResponse {
        throw failure
    }
}

private struct TestLocalAssistant: GroceryAssistant {
    let run: ModelRun

    init(run: ModelRun? = nil) {
        self.run = run ?? ModelRun(
            request: GroceryRequest(text: "local request"),
            answer: GroceryAnswer(text: "local answer")
        )
    }

    func answer(for request: GroceryRequest, household: DemoHousehold?) async -> ModelRun {
        return run
    }
}

private struct TestPhoneParentAnswerer: PhoneAFriendParentAnswerer {
    let answer: GroceryAnswer

    func answer(
        for request: GroceryRequest,
        childAnswer: GroceryAnswer,
        household: DemoHousehold?
    ) async -> GroceryAnswer {
        answer
    }
}

private actor TestClaudeCredentialStore: ClaudeCredentialStore {
    let apiKey: String?

    init(apiKey: String?) {
        self.apiKey = apiKey
    }

    func hasCredential() async -> Bool { apiKey != nil }

    func credential() async -> String? { apiKey }

    func save(apiKey: String) async throws {}

    func remove() async throws {}
}

private actor TestClaudeResponder: ClaudeResponder {
    private(set) var lastCredential: String?

    func availability() async -> RemoteProviderState { .ready }

    func respond(
        to invocation: RemoteGroceryInvocation,
        apiKey: String
    ) async throws -> RemoteProviderResponse {
        lastCredential = apiKey
        return RemoteProviderResponse(answer: GroceryAnswer(text: "Remote lentil answer"))
    }
}

private actor TestClaudeSessionFactory: ClaudeFoundationModelsSessionFactory {
    let events: [ClaudeSessionEvent]
    let completion: ClaudeSessionCompletion
    private(set) var lastRequest: ClaudeSessionRequest?
    private(set) var lastAPIKey: String?

    init(
        snapshots: [String] = [],
        toolEvents: [ModelRunEvent] = [],
        events: [ClaudeSessionEvent]? = nil,
        completion: ClaudeSessionCompletion = .finished
    ) {
        self.events = events
            ?? snapshots.map(ClaudeSessionEvent.snapshot)
            + toolEvents.map(ClaudeSessionEvent.modelRun)
        self.completion = completion
    }

    func response(
        for request: ClaudeSessionRequest,
        apiKey: String
    ) -> ClaudeSessionOutput {
        lastRequest = request
        lastAPIKey = apiKey
        return ClaudeSessionOutput(
            events: events,
            completion: completion
        )
    }
}

private struct TestCatalog: ProductCatalog, Sendable {
    let products: [CatalogProduct]

    func search(matching text: String) -> [CatalogProduct] {
        let query = text.lowercased()
        return products.filter { $0.name.lowercased().contains(query) }
    }

    func product(for id: ProductID) -> CatalogProduct? {
        products.first { $0.id == id }
    }
}
