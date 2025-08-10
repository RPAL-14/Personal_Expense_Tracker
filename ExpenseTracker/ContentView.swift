import SwiftUI
import Charts
import UIKit
import LocalAuthentication

// Identifiable wrapper to allow Date in .sheet(item:)
struct IdentifiableDate: Identifiable, Equatable {
    let id: Date
    var date: Date { id }
}



struct ContentView: View {
    // MARK: - Authentication state
    @State private var isUnlocked = false
    @State private var showAuthFailedAlert = false

    // MARK: - App state
    @State private var expenses: [Expense] = []
    @State private var showingAddExpense = false
    @State private var selectedCurrency = "INR"
    @State private var selectedDay: IdentifiableDate? = nil
    @State private var selectedEditExpense: Expense? = nil
    @State private var searchText: String = ""

    // Currency picker options
    let currencies: [Currency] = {
        let locale = NSLocale.current as NSLocale
        return NSLocale.isoCurrencyCodes.compactMap { code in
            if let name = locale.displayName(forKey: .currencyCode, value: code),
               let symbol = locale.displayName(forKey: .currencySymbol, value: code) {
                return Currency(id: code, name: name, symbol: symbol)
            }
            return nil
        }.sorted { $0.name < $1.name }
    }()

    // Filtered expenses by search text
    var filteredExpenses: [Expense] {
        if searchText.isEmpty { return expenses }
        return expenses.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.category.localizedCaseInsensitiveContains(searchText)
        }
    }

    // Group expenses by day, descending
    var expensesByDay: [(date: Date, items: [Expense], total: Double)] {
        let grouped = Dictionary(grouping: filteredExpenses) {
            Calendar.current.startOfDay(for: $0.date)
        }
        return grouped.map { (date, items) in
            (date, items, items.reduce(0) { $0 + $1.amount })
        }.sorted { $0.date > $1.date }
    }

    // Stats
    var totalExpense: Double { filteredExpenses.reduce(0) { $0 + $1.amount } }
    var maxExpense: Double { filteredExpenses.map { $0.amount }.max() ?? 0 }
    var averageDailyExpense: Double {
        let days = Set(filteredExpenses.map { Calendar.current.startOfDay(for: $0.date) }).count
        return days > 0 ? totalExpense / Double(days) : 0
    }

    // For SplitView selection on iPad/Mac: selected day date
    @State private var sidebarSelectedDate: Date? = nil

    var body: some View {
        Group {
            if isUnlocked {
                adaptiveRootView
            } else {
                authenticationView
            }
        }
        .onAppear(perform: authenticate)
        .alert("Authentication Failed", isPresented: $showAuthFailedAlert) {
            Button("Try Again", action: authenticate)
        } message: {
            Text("Please authenticate to use the app.")
        }
    }

    // MARK: - Authentication view shown when locked
    private var authenticationView: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield")
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
                .padding()
            Text("Unlock your expenses")
                .font(.title)
            Button("Authenticate") {
                authenticate()
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }
    }

    // MARK: - Adaptive UI for iPhone / iPad / Mac
    @ViewBuilder
    private var adaptiveRootView: some View {
        if UIDevice.current.userInterfaceIdiom == .pad || UIDevice.current.userInterfaceIdiom == .mac {
            NavigationSplitView {
                sidebarView
            } detail: {
                if let selectedDate = sidebarSelectedDate {
                    DayExpensesDetailView(
                        expenses: expenses.filter { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) },
                        date: selectedDate,
                        currencyCode: selectedCurrency,
                        onClose: { sidebarSelectedDate = nil },
                        onDelete: { exp in
                            expenses.removeAll { $0.id == exp.id }
                            saveExpenses()
                        },
                        onEdit: { exp in
                            selectedEditExpense = exp
                        }
                    )
                } else {
                    Text("Select a day from the sidebar")
                        .foregroundColor(.secondary)
                }
            }
            .navigationSplitViewStyle(.balanced)
            .sheet(item: $selectedEditExpense) { expenseToEdit in
                AddEditExpenseView(initialExpense: expenseToEdit) { editedExpense in
                    if let idx = expenses.firstIndex(where: { $0.id == editedExpense.id }) {
                        expenses[idx] = editedExpense
                        saveExpenses()
                    }
                    selectedEditExpense = nil
                }
            }
            // Add Expense modal is global
            .sheet(isPresented: $showingAddExpense) {
                AddEditExpenseView(initialExpense: nil) { newExpense in
                    expenses.append(newExpense)
                    saveExpenses()
                    showingAddExpense = false
                }
            }
            .onAppear {
                loadExpenses()
                loadPreferredCurrency()
            }
        } else {
            // iPhone fallback - NavigationView with modal sheets
            NavigationView {
                mainListView
                    .navigationTitle("Expenses")
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button { exportExpensesCSV() } label: {
                                Image(systemName: "square.and.arrow.up")
                            }
                        }
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button { showingAddExpense = true } label: {
                                Image(systemName: "plus")
                            }
                        }
                    }
                    .searchable(text: $searchText, prompt: "Search expenses")
                    .sheet(isPresented: $showingAddExpense) {
                        AddEditExpenseView(initialExpense: nil) { newExpense in
                            expenses.append(newExpense)
                            saveExpenses()
                            showingAddExpense = false
                        }
                    }
                    .sheet(item: $selectedDay) { day in
                        DayExpensesDetailView(
                            expenses: expenses.filter { Calendar.current.isDate($0.date, inSameDayAs: day.date) },
                            date: day.date,
                            currencyCode: selectedCurrency,
                            onClose: { selectedDay = nil },
                            onDelete: { exp in
                                expenses.removeAll { $0.id == exp.id }
                                saveExpenses()
                            },
                            onEdit: { exp in
                                selectedEditExpense = exp
                            }
                        )
                    }
                    .sheet(item: $selectedEditExpense) { expenseToEdit in
                        AddEditExpenseView(initialExpense: expenseToEdit) { editedExpense in
                            if let idx = expenses.firstIndex(where: { $0.id == editedExpense.id }) {
                                expenses[idx] = editedExpense
                                saveExpenses()
                            }
                            selectedEditExpense = nil
                        }
                    }
                    .onAppear {
                        loadExpenses()
                        loadPreferredCurrency()
                    }
                    .onChange(of: selectedCurrency) { _ in savePreferredCurrency() }
            }
        }
    }

    // The sidebar for iPad / Mac Catalyst
    private var sidebarView: some View {
        List(selection: $sidebarSelectedDate) {
            Section {
                Picker("Currency", selection: $selectedCurrency) {
                    ForEach(currencies) { c in
                        Text("\(c.symbol) \(c.id)").tag(c.id)
                    }
                }
                .pickerStyle(MenuPickerStyle())
            }
            if !filteredExpenses.isEmpty {
                Section(header: Text("Summary & Statistics")) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Total Spent: \(formattedAmount(totalExpense, currencyCode: selectedCurrency))")
                        Text("Highest Expense: \(formattedAmount(maxExpense, currencyCode: selectedCurrency))")
                        Text("Average Daily: \(formattedAmount(averageDailyExpense, currencyCode: selectedCurrency))")
                    }
                    .padding(.vertical, 4)

                    if #available(iOS 16.0, *) {
                        Chart {
                            ForEach(expensesByDay, id: \.date) { group in
                                BarMark(
                                    x: .value("Day", formattedDay(group.date)),
                                    y: .value("Amount", group.total)
                                )
                                .foregroundStyle(Color.accentColor.gradient)
                            }
                        }
                        .frame(height: 200)
                    } else {
                        Text("Charts available on iOS 16+").foregroundColor(.secondary)
                    }
                }
            }
            Section(header: Text("Daily Expense Summary")) {
                if expensesByDay.isEmpty {
                    Text("No expenses yet.").foregroundColor(.secondary)
                } else {
                    ForEach(expensesByDay, id: \.date) { group in
                        Text(formattedDay(group.date))
                            .tag(group.date as Date?)
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search expenses")
        .listStyle(SidebarListStyle())
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button { showingAddExpense = true } label: {
                    Image(systemName: "plus")
                }
                Button { exportExpensesCSV() } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
    }

    // This is used for iPhone main view
    private var mainListView: some View {
        List {
            Section {
                Picker("Currency", selection: $selectedCurrency) {
                    ForEach(currencies) { c in
                        Text("\(c.symbol) \(c.id)").tag(c.id)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .frame(maxWidth: 180)
            }
            if !filteredExpenses.isEmpty {
                Section(header: Text("Summary & Statistics")) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Total Spent: \(formattedAmount(totalExpense, currencyCode: selectedCurrency))")
                        Text("Highest Expense: \(formattedAmount(maxExpense, currencyCode: selectedCurrency))")
                        Text("Average Daily: \(formattedAmount(averageDailyExpense, currencyCode: selectedCurrency))")
                    }
                    .padding(.vertical, 4)
                    if #available(iOS 16.0, *) {
                        Chart {
                            ForEach(expensesByDay, id: \.date) { group in
                                BarMark(
                                    x: .value("Day", formattedDay(group.date)),
                                    y: .value("Amount", group.total)
                                )
                                .foregroundStyle(Color.accentColor.gradient)
                            }
                        }
                        .frame(height: 200)
                    } else {
                        Text("Charts available on iOS 16+").foregroundColor(.secondary)
                    }
                }
            }
            Section(header: Text("Daily Expense Summary")) {
                if expensesByDay.isEmpty {
                    Text("No expenses yet.").foregroundColor(.secondary)
                } else {
                    ForEach(expensesByDay, id: \.date) { group in
                        Button {
                            selectedDay = IdentifiableDate(id: group.date)
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(formattedDay(group.date)).font(.headline)
                                    Text("\(group.items.count) expense\(group.items.count == 1 ? "" : "s")")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Text(formattedAmount(group.total, currencyCode: selectedCurrency)).bold()
                            }
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
    }

    // MARK: - Authentication function
    func authenticate() {
        let context = LAContext()
        var error: NSError?

        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            let reason = "Unlock your expense tracker"

            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, authError in
                DispatchQueue.main.async {
                    if success {
                        isUnlocked = true
                    } else {
                        showAuthFailedAlert = true
                    }
                }
            }
        } else {
            // No biometrics/passcode - allow unlock
            isUnlocked = true
        }
    }

    // MARK: - CSV Export function
    func exportExpensesCSV() {
        let header = "Name,Amount,Date,Category\n"
        let rows = expenses.map { e in
            let dateString = DateFormatter.localizedString(from: e.date, dateStyle: .short, timeStyle: .none)
            return "\(e.name),\(e.amount),\(dateString),\(e.category)"
        }.joined(separator: "\n")
        let csvData = header + rows
        showShareSheet(items: [csvData])
    }

    // MARK: - Helper: Show share sheet
    func showShareSheet(items: [Any]) {
        let avc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = scene.windows.first?.rootViewController {
            rootVC.present(avc, animated: true)
        }
    }

    // MARK: - Formatting
    func formattedAmount(_ amount: Double, currencyCode: String) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currencyCode
        f.locale = Locale(identifier: "en_IN")
        return f.string(from: NSNumber(value: amount)) ?? "\(amount)"
    }
    func formattedDay(_ date: Date) -> String {
        let df = DateFormatter()
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        df.dateStyle = .medium
        return df.string(from: date)
    }

    // MARK: - Persistence
    func saveExpenses() {
        if let encoded = try? JSONEncoder().encode(expenses) {
            UserDefaults.standard.set(encoded, forKey: "expenses")
        }
    }
    func loadExpenses() {
        if let saved = UserDefaults.standard.data(forKey: "expenses"),
           let decoded = try? JSONDecoder().decode([Expense].self, from: saved) {
            expenses = decoded
        }
    }
    func savePreferredCurrency() {
        UserDefaults.standard.set(selectedCurrency, forKey: "preferredCurrency")
    }
    func loadPreferredCurrency() {
        if let saved = UserDefaults.standard.string(forKey: "preferredCurrency") {
            selectedCurrency = saved
        }
    }

    struct Currency: Identifiable {
        let id: String
        let name: String
        let symbol: String
    }
}

// MARK: - Day Detail View with PDF Export
extension ContentView {
    struct DayExpensesDetailView: View {
        let expenses: [Expense]
        let date: Date
        let currencyCode: String
        let onClose: () -> Void
        let onDelete: (Expense) -> Void
        let onEdit: (Expense) -> Void

        @State private var pdfURL: URL?
        @State private var showShare = false

        var body: some View {
            NavigationView {
                List {
                    ForEach(expenses) { e in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(e.name).font(.headline)
                                Text(e.category).font(.subheadline).foregroundColor(.secondary)
                            }
                            Spacer()
                            Text(formattedAmount(e.amount))
                                .font(.system(size: 18, weight: .bold))
                            Button { onEdit(e) } label: {
                                Image(systemName: "pencil.circle").foregroundColor(.blue)
                            }
                            .buttonStyle(BorderlessButtonStyle())
                            .padding(.leading, 8)
                            Button { onDelete(e) } label: {
                                Image(systemName: "minus.circle").foregroundColor(.red)
                            }
                            .buttonStyle(BorderlessButtonStyle())
                            .padding(.leading, 4)
                        }
                        .padding(.vertical, 6)
                    }
                }
                .navigationTitle(formattedDay(date))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close", action: onClose)
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            if let url = generatePDF() {
                                pdfURL = url
                                showShare = true
                            }
                        } label: {
                            Image(systemName: "doc.fill")
                        }
                        .accessibilityLabel("Export PDF")
                    }
                }
                .sheet(isPresented: $showShare, onDismiss: { pdfURL = nil }) {
                    if let url = pdfURL { ShareSheet(activityItems: [url]) }
                }
            }
        }

        func formattedAmount(_ amount: Double) -> String {
            let f = NumberFormatter()
            f.numberStyle = .currency
            f.currencyCode = currencyCode
            f.locale = Locale(identifier: "en_IN")
            return f.string(from: NSNumber(value: amount)) ?? "\(amount)"
        }

        func formattedDay(_ date: Date) -> String {
            let df = DateFormatter()
            if Calendar.current.isDateInToday(date) { return "Today" }
            if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
            df.dateStyle = .medium
            return df.string(from: date)
        }

        // PDF generator
        func generatePDF() -> URL? {
            let meta = [
                kCGPDFContextCreator: "Expense Tracker",
                kCGPDFContextTitle: "Expenses for \(formattedDay(date))"
            ]
            let format = UIGraphicsPDFRendererFormat()
            format.documentInfo = meta as [String: Any]
            let pageWidth = 8.5 * 72.0
            let pageHeight = 11 * 72.0
            let bounds = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
            let renderer = UIGraphicsPDFRenderer(bounds: bounds, format: format)

            let data = renderer.pdfData { ctx in
                ctx.beginPage()
                let title = "Expense Report - \(formattedDay(date))"
                title.draw(at: CGPoint(x: 20, y: 20),
                           withAttributes: [.font: UIFont.boldSystemFont(ofSize: 20)])
                var y: CGFloat = 60
                for e in expenses {
                    let line = "\(e.name) - \(formattedAmount(e.amount)) - \(e.category)"
                    line.draw(at: CGPoint(x: 20, y: y),
                              withAttributes: [.font: UIFont.systemFont(ofSize: 14)])
                    y += 20
                }
                let total = "Total: \(formattedAmount(expenses.reduce(0) { $0 + $1.amount }))"
                total.draw(at: CGPoint(x: 20, y: y + 20),
                           withAttributes: [.font: UIFont.boldSystemFont(ofSize: 16)])
            }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("DayExpenses-\(UUID().uuidString).pdf")
            do {
                try data.write(to: url)
                return url
            } catch {
                print("PDF write error: \(error)")
                return nil
            }
        }
    }
}

// MARK: - Add/Edit Expense View
extension ContentView {
    struct AddEditExpenseView: View {
        @Environment(\.presentationMode) var presentationMode
        var initialExpense: Expense?
        @State private var name = ""
        @State private var amount = ""
        @State private var category = ""
        @State private var date = Date()
        var onSave: (Expense) -> Void

        var body: some View {
            NavigationView {
                Form {
                    TextField("Name", text: $name)
                    TextField("Amount", text: $amount).keyboardType(.decimalPad)
                    TextField("Category", text: $category)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }
                .navigationTitle(initialExpense == nil ? "Add Expense" : "Edit Expense")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            guard let amt = Double(amount),
                                  !name.trimmingCharacters(in: .whitespaces).isEmpty,
                                  !category.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                            let exp = Expense(id: initialExpense?.id ?? UUID(),
                                              name: name, amount: amt, date: date, category: category)
                            onSave(exp)
                            presentationMode.wrappedValue.dismiss()
                        }
                    }
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { presentationMode.wrappedValue.dismiss() }
                    }
                }
                .onAppear {
                    if let e = initialExpense {
                        name = e.name
                        amount = String(e.amount)
                        category = e.category
                        date = e.date
                    }
                }
            }
        }
    }
}

// UIKit share sheet wrapper for SwiftUI
struct ShareSheet: UIViewControllerRepresentable {
    var activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
