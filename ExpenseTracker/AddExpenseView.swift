import SwiftUI

struct AddExpenseView: View {
    @Environment(\.presentationMode) var presentationMode

    @State private var name = ""
    @State private var amount = ""
    @State private var category = ""
    @State private var date = Date()

    var onSave: (Expense) -> Void

    var body: some View {
        NavigationView {
            Form {
                TextField("Name", text: $name)
                TextField("Amount", text: $amount)
                    .keyboardType(.decimalPad)
                TextField("Category", text: $category)
                DatePicker("Date", selection: $date, displayedComponents: .date)
            }
            .navigationTitle("Add Expense")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let actualAmount = Double(amount),
                              !name.trimmingCharacters(in: .whitespaces).isEmpty,
                              !category.trimmingCharacters(in: .whitespaces).isEmpty else {
                            return
                        }
                        let expense = Expense(name: name, amount: actualAmount, date: date, category: category)
                        onSave(expense)
                        presentationMode.wrappedValue.dismiss()
                    }
                }

                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
}
