import SwiftUI

struct CurrencyConverterView: View {
    @Environment(\.presentationMode) var presentationMode

    @State private var fromCurrency = "INR"
    @State private var toCurrency = "USD"
    @State private var amountText = ""
    @State private var convertedAmount: Double?
    @State private var isLoading = false
    @State private var errorMessage: String?

    // Example list of currencies; extend as needed
    let currencies = ["INR", "USD", "EUR", "GBP", "JPY", "AUD", "CAD"]

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Amount")) {
                    TextField("Enter amount", text: $amountText)
                        .keyboardType(.decimalPad)
                }

                Section(header: Text("From Currency")) {
                    Picker("From", selection: $fromCurrency) {
                        ForEach(currencies, id: \.self) { currency in
                            Text(currency)
                        }
                    }
                    .pickerStyle(WheelPickerStyle())
                    .frame(height: 100)
                }

                Section(header: Text("To Currency")) {
                    Picker("To", selection: $toCurrency) {
                        ForEach(currencies, id: \.self) { currency in
                            Text(currency)
                        }
                    }
                    .pickerStyle(WheelPickerStyle())
                    .frame(height: 100)
                }

                Section {
                    Button(action: convertCurrency) {
                        if isLoading {
                            ProgressView()
                        } else {
                            Text("Convert")
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                    .disabled(isLoading)
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                    }
                }

                if let result = convertedAmount {
                    Section(header: Text("Converted Amount")) {
                        Text(String(format: "%.2f %@", result, toCurrency))
                            .font(.title2)
                            .foregroundColor(.green)
                            .padding()
                    }
                }
            }
            .navigationBarTitle("Currency Converter", displayMode: .inline)
            .navigationBarItems(trailing: Button("Done") {
                presentationMode.wrappedValue.dismiss()
            })
        }
    }

    func convertCurrency() {
        guard let amount = Double(amountText), amount > 0 else {
            errorMessage = "Please enter a valid amount"
            convertedAmount = nil
            return
        }

        errorMessage = nil
        isLoading = true

        fetchExchangeRate(from: fromCurrency, to: toCurrency, amount: amount) { result in
            DispatchQueue.main.async {
                isLoading = false
                if let converted = result {
                    convertedAmount = converted
                } else {
                    errorMessage = "Conversion failed. Please try again."
                }
            }
        }
    }
}

// Network fetch function outside the struct
func fetchExchangeRate(from: String, to: String, amount: Double, completion: @escaping (Double?) -> Void) {
    let urlStr = "https://api.exchangerate.host/convert?from=\(from)&to=\(to)&amount=\(amount)"
    guard let url = URL(string: urlStr) else {
        completion(nil)
        return
    }

    URLSession.shared.dataTask(with: url) { data, _, error in
        guard let data = data, error == nil else {
            completion(nil)
            return
        }

        if let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
            print("DEBUG: API response:", json) // Debug line for troubleshooting
            if let result = json["result"] as? Double {
                completion(result)
            } else {
                completion(nil)
            }
        } else {
            completion(nil)
        }
    }.resume()
}
