import SwiftUI

struct ContentView: View {
    @ObservedObject var model: GroceryAppModel

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("Grocery Assistant")
                    .font(.largeTitle.bold())
                Text("Ask about a product in the bundled catalog.")
                    .foregroundStyle(.secondary)

                TextField("Try: lentils", text: $model.requestText)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.search)
                    .onSubmit { submit() }

                Button("Ask the local assistant", action: submit)
                    .buttonStyle(.borderedProminent)

                if let run = model.modelRun {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(run.answer.text)
                            .font(.title3.weight(.semibold))
                        if !run.answer.evidence.isEmpty {
                            Text("Evidence: \(run.answer.evidence.joined(separator: ", "))")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Reference App")
        }
    }

    private func submit() {
        Task { await model.submit(model.requestText) }
    }
}
