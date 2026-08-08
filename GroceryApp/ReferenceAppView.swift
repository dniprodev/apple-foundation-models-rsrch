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
                        catalogSection
                        assistantSection
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
                        Button("Add to demo cart") {
                            Task { await model.addToSelectedHouseholdCart(product.id) }
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                }
            }
        }
    }

    private var assistantSection: some View {
        Section("Local Assistant") {
            TextField("Ask about a product", text: $model.requestText)
                .submitLabel(.search)
                .onSubmit { submit() }

            Button("Ask the local assistant", action: submit)
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
