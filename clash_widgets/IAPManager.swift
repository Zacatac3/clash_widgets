import Foundation
import Combine
import StoreKit

@MainActor
final class IAPManager: ObservableObject {
	static let shared = IAPManager()

	@Published private(set) var isAdsRemoved: Bool
	@Published private(set) var products: [Product] = []
	@Published private(set) var isLoadingProducts: Bool = false
	@Published private(set) var productsError: String?

	private let productID = "com.zach.clashwidgets.removeads"
	private let adsRemovedKey = "adsRemoved"

	private init() {
		self.isAdsRemoved = UserDefaults.standard.bool(forKey: adsRemovedKey)
		Task {
			await loadProducts()
			await refreshPurchasedStatus()
			await observeTransactions()
		}
	}

	func loadProducts() async {
		isLoadingProducts = true
		productsError = nil
		do {
			let loaded = try await Product.products(for: [productID])
			products = loaded
			if loaded.isEmpty {
				productsError = "No products returned from the App Store."
			}
		} catch {
			products = []
			productsError = error.localizedDescription
			NSLog("🚀 [IAP] Failed to load products: \(error.localizedDescription)")
		}
		isLoadingProducts = false
	}

	func purchase() async throws -> Bool {
		if products.isEmpty {
			await loadProducts()
		}
		guard let product = products.first else { return false }
		let result = try await product.purchase()

		switch result {
		case .success(let verification):
			if case .verified(let transaction) = verification {
				await handlePurchaseSuccess(transaction)
				return true
			}
			return false
		case .userCancelled, .pending:
			return false
		@unknown default:
			return false
		}
	}

	func restorePurchases() async {
		_ = await restorePurchasesAndReturnSuccess()
	}

	/// Restore purchases and return true if the entitlements indicate the ads-removed
	/// product is now owned. This is helpful for UI flows that need a success flag.
	func restorePurchasesAndReturnSuccess() async -> Bool {
		do {
			NSLog("🚀 [IAP] Starting restore (AppStore.sync)")
			try await AppStore.sync()
			await refreshPurchasedStatus()
			NSLog("🚀 [IAP] Restore completed; adsRemoved=\(isAdsRemoved)")
			return isAdsRemoved
		} catch {
			productsError = error.localizedDescription
			NSLog("🚀 [IAP] Restore failed: \(error.localizedDescription)")
			return false
		}
	}

	private func observeTransactions() async {
		for await result in Transaction.updates {
			if case .verified(let transaction) = result, transaction.productID == productID {
				await handlePurchaseSuccess(transaction)
			}
		}
	}

	private func refreshPurchasedStatus() async {
		var purchased = false
		for await result in Transaction.currentEntitlements {
			if case .verified(let transaction) = result, transaction.productID == productID {
				purchased = true
				break
			}
		}
		setAdsRemoved(purchased)
	}

	private func handlePurchaseSuccess(_ transaction: Transaction) async {
		setAdsRemoved(true)
		await transaction.finish()
	}

	private func setAdsRemoved(_ value: Bool) {
		isAdsRemoved = value
		UserDefaults.standard.set(value, forKey: adsRemovedKey)
	}
}
