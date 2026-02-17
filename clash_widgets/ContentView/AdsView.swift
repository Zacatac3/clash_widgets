import SwiftUI
import GoogleMobileAds
import Combine
#if canImport(UIKit)
import UIKit
#endif

struct BannerAdView: UIViewRepresentable {
    var adUnitID: String = "ca-app-pub-4499177240533852/7133262169"
    var adWidth: CGFloat
    @AppStorage("hasCompletedInitialSetup") private var hasCompletedInitialSetup = false

    static func adaptiveAdSize(for width: CGFloat) -> AdSize {
        let resolvedWidth = max(1, width)
        return currentOrientationAnchoredAdaptiveBanner(width: resolvedWidth)
    }

    static func adaptiveHeight(for width: CGFloat) -> CGFloat {
        adaptiveAdSize(for: width).size.height
    }

    func makeUIView(context: Context) -> BannerView {
        let adSize = Self.adaptiveAdSize(for: adWidth)
        let banner = BannerView(adSize: adSize)
        banner.adUnitID = adUnitID
        banner.delegate = context.coordinator
        let rootVC = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?.rootViewController
        banner.rootViewController = rootVC
        if hasCompletedInitialSetup {
            banner.load(Request())
        } else {
            NSLog("📵 [ADMOB_DEBUG] Skipping banner load until onboarding complete")
        }

        return banner
    }

    func updateUIView(_ uiView: BannerView, context: Context) {
        let newSize = Self.adaptiveAdSize(for: adWidth)
        if uiView.adSize.size != newSize.size {
            uiView.adSize = newSize
            if hasCompletedInitialSetup {
                uiView.load(Request())
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, BannerViewDelegate {
        func bannerViewDidReceiveAd(_ bannerView: BannerView) {
            NSLog("🚀 [ADMOB_DEBUG] Banner Loaded Successfully ✅")
        }

        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
            NSLog("🚀 [ADMOB_DEBUG] Banner Failed: \(error.localizedDescription) ❌")
        }
    }
}

final class InterstitialAdManager: NSObject, ObservableObject {
    private var interstitial: InterstitialAd?
    @Published var isReady = false
    private var onDismiss: (() -> Void)?

    func load(adUnitID: String? = nil) {
        let chosenID = adUnitID ?? "ca-app-pub-4499177240533852/2764621791"

        let request = Request()
        InterstitialAd.load(with: chosenID, request: request, completionHandler: { [weak self] ad, error in
            if let ad = ad {
                NSLog("🚀 [ADMOB_DEBUG] Interstitial Loaded Successfully ✅")
                self?.interstitial = ad
                self?.isReady = true
            } else {
                NSLog("🚀 [ADMOB_DEBUG] Interstitial Failed: \(error?.localizedDescription ?? "Unknown error") ❌")
                self?.isReady = false
            }
        })
    }

    func present(from root: UIViewController, onDismiss: @escaping () -> Void) {
        guard let interstitial = interstitial else {
            onDismiss()
            return
        }
        self.onDismiss = onDismiss
        interstitial.fullScreenContentDelegate = self
        interstitial.present(from: root)
    }

    func clearLoadedAd() {
        interstitial = nil
        isReady = false
        onDismiss = nil
    }
}

extension InterstitialAdManager: FullScreenContentDelegate {
    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        onDismiss?()
        isReady = false
        interstitial = nil
    }

    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        onDismiss?()
        isReady = false
        interstitial = nil
    }
}

struct BannerAdPlaceholder: View {
    @EnvironmentObject var iapManager: IAPManager
    @AppStorage("hasCompletedInitialSetup") private var hasCompletedInitialSetup = false
    @State private var currentWidth: CGFloat = UIScreen.main.bounds.width

    var body: some View {
        if !iapManager.isAdsRemoved && hasCompletedInitialSetup {
            GeometryReader { geometry in
                let availableWidth = max(geometry.size.width, 1)
                BannerAdView(adWidth: availableWidth)
                    .frame(width: availableWidth, height: BannerAdView.adaptiveHeight(for: availableWidth))
                    .onAppear {
                        currentWidth = availableWidth
                    }
                    .onChangeCompat(of: availableWidth) { newWidth in
                        currentWidth = newWidth
                    }
            }
            .frame(height: BannerAdView.adaptiveHeight(for: currentWidth))
        }
    }
}
