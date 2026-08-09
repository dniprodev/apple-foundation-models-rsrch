import Foundation
import GroceryDomain
import SwiftUI

struct ReferenceAppView: View {
    @ObservedObject var model: ReferenceAppViewModel

    var body: some View {
        NavigationStack {
            Group {
                if model.isLoaded {
                    List {
                        householdSection
                        strategySection
                        manualDemoScenariosSection
                        catalogSection
                        assistantSection
                        cartProposalSection
                        resetSection
                    }
                    .listStyle(.insetGrouped)
                } else {
                    ProgressView("Loading demo data…")
                }
            }
            .navigationTitle("Reference App")
        }
        .task { await model.load() }
        .onChange(of: model.catalogQuery) { _, query in
            model.searchCatalog(query)
        }
    }

    private var householdSection: some View {
        Section("Demo Household") {
            Picker("Household", selection: householdSelection) {
                ForEach(model.households) { household in
                    Text(household.name).tag(household.id)
                }
            }

            if let household = model.selectedHousehold {
                LabeledContent("Members", value: memberSummary(for: household))
                if let target = household.weeklySpendingTargetCents {
                    LabeledContent("Weekly target", value: formattedCents(target))
                }
                LabeledContent("Restrictions", value: labels(household.restrictions.map(\.rawValue)))
                LabeledContent("Priorities", value: labels(household.priorities.map(\.rawValue)))

                contextList(title: "Pantry", items: household.pantry) { item in
                    "\(model.productName(for: item.productID)) ×\(item.quantity)"
                }
                contextList(title: "Cart", items: household.cart) { item in
                    "\(model.productName(for: item.productID)) ×\(item.quantity)"
                }
                contextList(title: "Purchase history", items: household.purchaseHistory) { item in
                    "\(item.sequence). \(model.productName(for: item.productID)) ×\(item.quantity)"
                }
            }
        }
    }

    private var catalogSection: some View {
        Section("Bundled Catalog") {
            TextField("Search products or details", text: $model.catalogQuery)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            if model.catalogQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Search the offline product catalog.")
                    .foregroundStyle(.secondary)
            } else if model.catalogResults.isEmpty {
                Text("No bundled products match this search.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.catalogResults, id: \.id) { product in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(product.name)
                            .font(.headline)
                        Text(product.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button("Propose adding to cart") {
                            Task { await model.proposeAddingToSelectedHouseholdCart(product.id) }
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                }
            }
        }
    }

    private var strategySection: some View {
        Section("Model Strategy") {
            Picker("Strategy", selection: $model.selectedStrategy) {
                Text("Local-only").tag(ModelStrategy.localOnly)
                Text("Hybrid").tag(ModelStrategy.hybrid)
            }

            if model.selectedStrategy == .hybrid {
                Picker("Orchestration", selection: $model.selectedOrchestrationPattern) {
                    Text("Baton-pass").tag(OrchestrationPattern.batonPass)
                    Text("Phone-a-friend").tag(OrchestrationPattern.phoneAFriend)
                }

                Text(
                    model.selectedOrchestrationPattern == .phoneAFriend
                        ? "A bounded task goes to an isolated Claude child; the local parent owns the final answer."
                        : "The local and Claude profiles share session history; Claude owns the final answer."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)

                Text(
                    model.claudeCredentialConfigured
                        ? "Claude credential is stored in Keychain."
                        : "Hybrid assistance needs a Claude credential."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)

                SecureField("Claude API key", text: $model.claudeCredentialInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                HStack {
                    Button("Save credential") {
                        Task { await model.saveClaudeCredential() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.claudeCredentialInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if model.claudeCredentialConfigured {
                        Button("Remove", role: .destructive) {
                            Task { await model.removeClaudeCredential() }
                        }
                        .buttonStyle(.bordered)
                    }
                }

                if let error = model.claudeCredentialError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private var manualDemoScenariosSection: some View {
        Section("Manual Demo Scenarios") {
            Text("Run a repeatable milestone-one path, then inspect the Model Run and Model Trace below.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            ForEach(ManualDemoScenario.allCases) { scenario in
                Button {
                    Task { await model.runScenario(scenario) }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(scenario.title)
                                .font(.headline)
                            Spacer()
                            if model.selectedScenario == scenario {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.tint)
                            }
                        }
                        Text(scenario.description)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }

            if let scenario = model.selectedScenario {
                Text("Selected: \(scenario.title). Expand Model Trace after the run; no quality score or exact generated wording is required.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var assistantSection: some View {
        Section("Grocery Assistant") {
            TextField("Ask about a product", text: $model.requestText)
                .submitLabel(.search)
                .onSubmit { submit() }

            Button("Ask the assistant", action: submit)
                .buttonStyle(.borderedProminent)

            if let run = model.modelRun {
                VStack(alignment: .leading, spacing: 8) {
                    Text(run.answer.text)
                        .font(.headline)
                    if !run.answer.evidence.isEmpty {
                        Text("Evidence: \(run.answer.evidence.joined(separator: ", "))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    DisclosureGroup("Model Run") {
                        Text("Request: \(run.request.text)")
                            .font(.footnote)
                        ForEach(Array(run.events.enumerated()), id: \.offset) { _, event in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.label)
                                    .font(.caption.weight(.semibold))
                                Text(event.content)
                                    .font(.footnote)
                            }
                            .padding(.vertical, 2)
                        }
                    }

                    DisclosureGroup("Model Trace") {
                        LabeledContent("Strategy", value: run.trace.strategy.rawValue)
                        LabeledContent("Provider", value: run.trace.provider.rawValue)
                        LabeledContent("Intent", value: run.trace.intentID)
                        LabeledContent("Tools", value: run.trace.tools.joined(separator: ", "))
                        if let pattern = run.trace.orchestrationPattern {
                            LabeledContent("Orchestration", value: pattern.rawValue)
                        }
                        if let sessionID = run.trace.remoteSessionID {
                            LabeledContent("Remote session", value: sessionID)
                        }
                        if let parentSessionID = run.trace.parentRemoteSessionID {
                            LabeledContent("Parent session", value: parentSessionID)
                        }
                        if !run.trace.activeProfiles.isEmpty {
                            LabeledContent(
                                "Profiles",
                                value: run.trace.activeProfiles.map(\.rawValue).joined(separator: " → ")
                            )
                        }
                        ForEach(Array(run.trace.profileTransitions.enumerated()), id: \.offset) { _, transition in
                            Text("Profile transition: \(transition.from.rawValue) → \(transition.to.rawValue)")
                                .font(.footnote)
                        }
                        ForEach(Array(run.trace.profileActivations.enumerated()), id: \.offset) { _, activation in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Active profile: \(activation.profile.rawValue)")
                                    .font(.caption.weight(.semibold))
                                Text("Trigger: \(activation.trigger)")
                                Text("Selected model: \(activation.selectedModel)")
                                Text("Available tools: \(activation.tools.joined(separator: ", "))")
                                Text(
                                    "Final-answer responsibility: "
                                        + (activation.ownsFinalAnswer ? activation.profile.rawValue : "app")
                                )
                                ForEach(activation.effectiveInstructions, id: \.self) { instruction in
                                    Text("Instruction: \(instruction)")
                                }
                            }
                            .font(.footnote)
                        }
                        if let finalAnswerProfile = run.trace.finalAnswerProfile {
                            LabeledContent("Final answer owner", value: finalAnswerProfile.rawValue)
                        }
                        ForEach(Array(run.trace.toolEvents.enumerated()), id: \.offset) { _, event in
                            Text("\(event.label): \(event.content)")
                                .font(.footnote)
                        }
                        if let householdID = run.trace.householdID {
                            LabeledContent("Household", value: householdID.rawValue)
                        }
                        if let duration = run.trace.durationMilliseconds {
                            LabeledContent("Duration", value: "\(duration) ms")
                        }
                        if let error = run.trace.error {
                            LabeledContent("Error", value: error)
                        }
                        ForEach(run.trace.privacyConcerns, id: \.self) { concern in
                            Text("Privacy concern: \(concern)")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                        }
                        if let remoteContextView = run.trace.remoteContextView {
                            Text("Remote Context View")
                                .font(.caption.weight(.semibold))
                            Text(remoteContextView)
                                .font(.footnote)
                        } else if run.trace.strategy == .localOnly {
                            Text("Local-only run: no remote context view or remote transport was created.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var resetSection: some View {
        Section("Local State") {
            Button("Reset selected household") {
                Task { await model.resetSelectedHousehold() }
            }

            Button("Reset all demo households", role: .destructive) {
                Task { await model.resetAllHouseholds() }
            }

            Text("Resets fictional pantry, cart, and purchase history state to the deterministic demo data.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var cartProposalSection: some View {
        if let proposal = model.cartProposal {
            Section("Cart Proposal") {
                Text(proposal.reason)
                    .font(.headline)

                Text("Nothing changes until you approve this proposal.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if let error = model.cartProposalError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                contextList(title: "Proposed cart", items: proposal.proposedCart) { item in
                    "\(model.productName(for: item.productID)) ×\(item.quantity)"
                }

                HStack {
                    Button("Decline") {
                        Task { await model.declineCartProposal() }
                    }
                    .buttonStyle(.bordered)

                    Button("Approve cart changes") {
                        Task { await model.approveCartProposal() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        } else if let error = model.cartProposalError {
            Section("Cart Proposal") {
                Text(error)
                    .foregroundStyle(.red)
            }
        }
    }

    private var householdSelection: Binding<DemoHouseholdID> {
        Binding(
            get: { model.selectedHouseholdID },
            set: { model.selectHousehold($0) }
        )
    }

    private func contextList<Item>(
        title: String,
        items: [Item],
        label: @escaping (Item) -> String
    ) -> some View {
        DisclosureGroup(title) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                Text(label(item))
            }
        }
    }

    private func memberSummary(for household: DemoHousehold) -> String {
        household.members.map { "\($0.name) (\($0.role.rawValue))" }.joined(separator: ", ")
    }

    private func labels(_ values: [String]) -> String {
        values.map { $0.replacingOccurrences(of: "-", with: " ").capitalized }.joined(separator: ", ")
    }

    private func formattedCents(_ cents: Int) -> String {
        String(format: "$%.2f", Double(cents) / 100)
    }

    private func submit() {
        Task { await model.submit(model.requestText) }
    }
}
