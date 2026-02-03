import Foundation
import SwiftUI

#if canImport(UIKit)
import UIKit

func clipboardTextFromPasteboard() -> String? {
    let pasteboard = UIPasteboard.general
    let candidates: [(String, [String.Encoding])] = [
        ("public.utf8-plain-text", [.utf8]),
        ("public.utf16-plain-text", [.utf16, .utf16LittleEndian, .utf16BigEndian]),
        ("public.utf32-plain-text", [.utf32, .utf32LittleEndian, .utf32BigEndian]),
        ("public.text", [.utf8, .utf16, .utf16LittleEndian, .utf16BigEndian])
    ]

    for (type, encodings) in candidates {
        if let data = pasteboard.data(forPasteboardType: type) {
            for encoding in encodings {
                if let decoded = String(data: data, encoding: encoding), !decoded.isEmpty {
                    return decoded
                }
            }
        }
    }

    return pasteboard.string
}

extension UIColor {
    func adjustedSaturation(by multiplier: CGFloat) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return UIColor(hue: h, saturation: min(s * multiplier, 1.0), brightness: b, alpha: a)
    }

    func adjustedBrightness(by offset: CGFloat) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return UIColor(hue: h, saturation: s, brightness: max(min(b + offset, 1.0), 0.0), alpha: a)
    }

    var averageColor: UIColor? {
        guard let inputImage = CIImage(image: self.toImage()) else { return nil }
        let extentVector = CIVector(x: inputImage.extent.origin.x, y: inputImage.extent.origin.y, z: inputImage.extent.size.width, w: inputImage.extent.size.height)
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: inputImage, kCIInputExtentKey: extentVector]) else { return nil }
        guard let outputImage = filter.outputImage else { return nil }
        var bitmap = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: kCFNull as Any])
        context.render(outputImage, toBitmap: &bitmap, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        return UIColor(red: CGFloat(bitmap[0]) / 255, green: CGFloat(bitmap[1]) / 255, blue: CGFloat(bitmap[2]) / 255, alpha: CGFloat(bitmap[3]) / 255)
    }

    private func toImage() -> UIImage {
        let rect = CGRect(x: 0, y: 0, width: 1, height: 1)
        UIGraphicsBeginImageContext(rect.size)
        let context = UIGraphicsGetCurrentContext()
        context?.setFillColor(self.cgColor)
        context?.fill(rect)
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image ?? UIImage()
    }
}

extension UIImage {
    var averageColor: UIColor? {
        guard let inputImage = CIImage(image: self) else { return nil }
        let extentVector = CIVector(x: inputImage.extent.origin.x, y: inputImage.extent.origin.y, z: inputImage.extent.size.width, w: inputImage.extent.size.height)
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: inputImage, kCIInputExtentKey: extentVector]) else { return nil }
        guard let outputImage = filter.outputImage else { return nil }
        var bitmap = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: kCFNull as Any])
        context.render(outputImage, toBitmap: &bitmap, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        return UIColor(red: CGFloat(bitmap[0]) / 255, green: CGFloat(bitmap[1]) / 255, blue: CGFloat(bitmap[2]) / 255, alpha: CGFloat(bitmap[3]) / 255)
    }
}
#endif

// NOTE: WhatsNewItem and WhatsNewSection are defined in DataService.swift

func defaultWhatsNewItems() -> [WhatsNewItem] {
    loadWhatsNewItems()
}

func loadWhatsNewItems() -> [WhatsNewItem] {
    if let url = Bundle.main.url(forResource: "features", withExtension: "txt"),
       let data = try? Data(contentsOf: url),
       let text = String(data: data, encoding: .utf8) {
        return parseFeaturesText(text)
    }

    let fallback = """
    Features of the app:
    - Upgrade tracking via JSON export, done with one button press
    - Home Screen Widgets for builders, Lab/pets, and builder base as well as helpers cooldowns
    - Multiple profile support
    - Notification Support (Profile specific)
    - API Sync for enhanced profile information
    - Rich equipment tracking with upgrade costs and totals to max, adapts to custom filters
    - Gold Pass Support, as well as monthly reminder to set gold pass boost
    - customizability, rearrange the home tab to your needs
    - Feedback form for reporting bugs and glitches, as well as for requesting features
    """

    return parseFeaturesText(fallback)
}

internal func defaultWhatsNewSections() -> [WhatsNewSection] {
    return [
        WhatsNewSection(dateLabel: "2/3/2026 - Major Quality of Life Update", bullets: [
            "New Home Modules: Added Current War tracker and Boosts menu (Helpers, Potions, Snacks)",
            "Customization: You can now hide individual sections and re-order profile cards",
            "Enhanced Notifications: Pre-notify, setting to open Clash when tapping a notification, and auto-switching to the correct profile on tap",
            "Lock Screen Widgets: Track your upgrades directly from your lock screen",
            "Improved Importing: Fixed Town Hall level sync issues and added visual import confirmation",
            "Cleaned up Profile: Added Clan stats and helper gem costs; removed Achievements section, gradients adjusted for some town halls"
        ]),
        WhatsNewSection(dateLabel: "1/27/2026 - Critical Widget Fix", bullets: ["Widgets fixed: Widgets should now work on all iOS/iPadOS versions and devices", "Added EU consent form", "fixed league icons naming error", "fixed hero levels in the profile tab not being relevant to current town hall", "wall costs now display billions properly", "wall costs now scale with gold pass"]),
        WhatsNewSection(dateLabel: "1/27/2026 - Post Release Bug Fixes and Tweaks", bullets: ["New Walls Section on the home screen","Widgets can now be set to a certain profile (press and hold on the widget, and press 'edit widget')","Streamlined Onboarding - Now contains instructions & Split into two pages, and For simplicity, swapped places of import button and profile switcher", "fixed too many ads showing up when asking app not to track", "added changelog to what's new", "Added notifications for helpers", "many other various fixes and improvements"]),
        WhatsNewSection(dateLabel: "1/25/26 - Hot Fix", bullets: ["Imporved new user experience"," fixed ads showing up after purchasing ad-free", "pop-ups no longer show up when not supposed to", "fixed various minor bugs"]),
        WhatsNewSection(dateLabel: "1/23/26 - Initial Version", bullets: ["Initial version with core features"," Broken Onboarding and helper timers", "other known issues"])
    ]
}

func parseFeaturesText(_ text: String) -> [WhatsNewItem] {
    var items: [WhatsNewItem] = []
    let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
    for line in lines {
        guard line.hasPrefix("-") else { continue }
        let entry = line.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = entry.lowercased()
        let item: WhatsNewItem
        if lower.contains("upgrade") {
            item = .init(title: "1/25/26 - Hotfix & Improvements", detail: "")
        } else if lower.contains("widget") || lower.contains("home screen") {
            item = .init(title: "Home Screen Widgets", detail: "Widgets for builders, lab/pets, builder base, and helper cooldowns keep info at a glance.")
        } else if lower.contains("multiple profile") || lower.contains("profiles") {
            item = .init(title: "Multiple Profiles", detail: "Manage and switch between multiple player profiles effortlessly.")
        } else if lower.contains("notification") {
            item = .init(title: "Profile Notifications", detail: "Profile-specific notifications let you know when upgrades complete.")
        } else if lower.contains("api sync") || lower.contains("api") {
            item = .init(title: "API Sync", detail: "Sync with the API for richer, up-to-date profile data.")
        } else if lower.contains("equipment") {
            item = .init(title: "Equipment Tracking", detail: "Track equipment upgrades, costs, and totals, adapted to your filters.")
        } else if lower.contains("gold pass") {
            item = .init(title: "Gold Pass Support", detail: "Set Gold Pass boosts per profile and receive monthly reminders.")
        } else if lower.contains("customiz") || lower.contains("rearrange") {
            item = .init(title: "Customizable Home", detail: "Rearrange the home tab to match your workflow and preferences.")
        } else if lower.contains("feedback") || lower.contains("fedeback") {
            item = .init(title: "Feedback", detail: "Send bug reports or feature requests through the in-app feedback form.")
        } else {
            item = .init(title: String(entry.prefix(40)), detail: entry)
        }
        items.append(item)
    }
    return items
}

internal func goldPassBoostToSliderValue(_ boost: Int) -> Double {
    switch boost {
    case 0: return 0
    case 10: return 1
    case 15: return 2
    case 20: return 3
    default: return 0
    }
}

internal func sliderValueToGoldPassBoost(_ value: Double) -> Int {
    switch Int(value.rounded()) {
    case 0: return 0
    case 1: return 10
    case 2: return 15
    case 3: return 20
    default: return 0
    }
}

func formattedCompact(_ value: Int) -> String {
    let num = Double(value)
    if num >= 1_000_000_000 {
        return String(format: "%.1fB", num / 1_000_000_000)
    } else if num >= 1_000_000 {
        return String(format: "%.1fM", num / 1_000_000)
    } else if num >= 1_000 {
        return String(format: "%.1fK", num / 1_000)
    } else {
        return "\(value)"
    }
}
