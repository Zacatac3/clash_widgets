//
//  ImageTrimmer.swift
//  clash_widgets
//
//  Utility for trimming transparent whitespace from PNG images
//

import Foundation
import UIKit

struct ImageTrimmer {
    /// Trims transparent whitespace from the edges of an image by analyzing pixel alpha values
    /// - Parameter image: The UIImage to trim
    /// - Returns: A new UIImage with transparent edges removed
    static func trimTransparentEdges(from image: UIImage) -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        
        let width = cgImage.width
        let height = cgImage.height
        
        guard let dataProvider = cgImage.dataProvider,
              let data = dataProvider.data as Data? else {
            return image
        }
        
        let bytesPerPixel = 4
        let pixelData = [UInt8](data)
        
        // Find bounding box of non-transparent pixels
        var minX = width
        var maxX = -1
        var minY = height
        var maxY = -1
        
        for y in 0..<height {
            for x in 0..<width {
                let pixelIndex = (y * width + x) * bytesPerPixel
                guard pixelIndex + 3 < pixelData.count else { continue }
                
                let alpha = pixelData[pixelIndex + 3]
                if alpha > 5 { // Threshold to ignore nearly-transparent pixels
                    minX = min(minX, x)
                    maxX = max(maxX, x)
                    minY = min(minY, y)
                    maxY = max(maxY, y)
                }
            }
        }
        
        // If all transparent, return original
        guard minX <= maxX && minY <= maxY && minX < width && minY < height else {
            return image
        }
        
        let trimRect = CGRect(
            x: CGFloat(minX),
            y: CGFloat(minY),
            width: CGFloat(maxX - minX + 1),
            height: CGFloat(maxY - minY + 1)
        )
        
        guard let croppedCG = cgImage.cropping(to: trimRect) else {
            return image
        }
        
        return UIImage(cgImage: croppedCG, scale: image.scale, orientation: image.imageOrientation)
    }
    
    /// Trims transparent whitespace from multiple PNG images and saves them back to disk
    /// - Parameters:
    ///   - pngPaths: Array of file paths to PNG images
    ///   - completion: Callback with array of (path, success) tuples
    static func trimPNGFiles(at pngPaths: [String], completion: @escaping ([(String, Bool)]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let results = pngPaths.map { path -> (String, Bool) in
                guard FileManager.default.fileExists(atPath: path),
                      let imageData = try? Data(contentsOf: URL(fileURLWithPath: path)),
                      let image = UIImage(data: imageData) else {
                    return (path, false)
                }
                
                let trimmedImage = trimTransparentEdges(from: image)
                
                guard let pngData = trimmedImage.pngData() else {
                    return (path, false)
                }
                
                do {
                    try pngData.write(to: URL(fileURLWithPath: path))
                    NSLog("✅ Trimmed image: \(path)")
                    return (path, true)
                } catch {
                    NSLog("❌ Failed to write trimmed image to \(path): \(error)")
                    return (path, false)
                }
            }
            
            DispatchQueue.main.async {
                completion(results)
            }
        }
    }
}
