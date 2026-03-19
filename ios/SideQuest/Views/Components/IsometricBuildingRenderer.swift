import UIKit
import CoreGraphics

enum IsometricBuildingStyle: String {
    case cafe
    case gym
    case park
    case library
    case signpost
    case cabana
    case bookshop
    case museum
    case restaurant
    case dojo
    case communityHall = "community_hall"
    case arena
    case dogPark = "dog_park"
    case market

    init(category: MapQuestCategory) {
        switch category {
        case .cafe: self = .cafe
        case .gym: self = .gym
        case .park, .dogPark: self = category == .dogPark ? .dogPark : .park
        case .library: self = .library
        case .trail, .bikePath: self = .signpost
        case .pool, .beach, .lake: self = .cabana
        case .bookstore: self = .bookshop
        case .museum, .artGallery: self = .museum
        case .restaurant: self = .restaurant
        case .yogaStudio, .danceStudio, .martialArts: self = .dojo
        case .communityCenter, .volunteerCenter, .placeOfWorship: self = .communityHall
        case .basketballCourt, .tennisCourt, .skatePark, .rockClimbingGym, .bowlingAlley: self = .arena
        case .farmersMarket: self = .market
        }
    }

    var assetName: String {
        switch self {
        case .cafe: "01_cafe"
        case .gym: "02_gym"
        case .park: "03_park"
        case .library: "04_library"
        case .signpost: "05_signpost"
        case .cabana: "06_cabana"
        case .bookshop: "07_bookshop"
        case .museum: "08_museum"
        case .restaurant: "09_restaurant"
        case .dojo: "10_dojo"
        case .communityHall: "11_community_hall"
        case .arena: "12_arena"
        case .dogPark: "13_dog_park"
        case .market: "14_market"
        }
    }
}

struct IsometricBuildingRenderer {
    private static var sourceImageCache: [String: UIImage] = [:]
    private static var renderedImageCache: [String: UIImage] = [:]

    static func render(style: IsometricBuildingStyle, color: UIColor, size: CGSize, isVisited: Bool) -> UIImage {
        renderImage(
            cachedImage(for: style.assetName),
            cacheKey: "\(style.assetName)_\(Int(size.width))x\(Int(size.height))_\(isVisited ? "visited" : "live")",
            color: color,
            size: size,
            isVisited: isVisited
        )
    }

    static func render(assetName: String, color: UIColor, size: CGSize, isVisited: Bool) -> UIImage? {
        let image = cachedImage(for: assetName)
        guard image.size.width > 0, image.size.height > 0 else { return nil }
        return renderImage(
            image,
            cacheKey: "\(assetName)_\(Int(size.width))x\(Int(size.height))_\(isVisited ? "visited" : "live")",
            color: color,
            size: size,
            isVisited: isVisited
        )
    }

    private static func renderImage(
        _ image: UIImage,
        cacheKey: String,
        color: UIColor,
        size: CGSize,
        isVisited: Bool
    ) -> UIImage {
        if let cached = renderedImageCache[cacheKey] {
            return cached
        }

        let renderer = UIGraphicsImageRenderer(size: size)
        let result = renderer.image { context in
            let cgContext = context.cgContext
            let imageRect = CGRect(origin: .zero, size: size)

            let shadowRect = CGRect(x: 10, y: size.height - 14, width: size.width - 20, height: 9)
            let shadowPath = UIBezierPath(ovalIn: shadowRect)
            cgContext.setFillColor(UIColor.black.withAlphaComponent(isVisited ? 0.14 : 0.24).cgColor)
            cgContext.addPath(shadowPath.cgPath)
            cgContext.fillPath()

            let glowColor = color.withAlphaComponent(isVisited ? 0.08 : 0.2)
            cgContext.setShadow(offset: CGSize(width: 0, height: 8), blur: isVisited ? 8 : 18, color: glowColor.cgColor)
            image.draw(in: imageRect)
            cgContext.setShadow(offset: .zero, blur: 0, color: nil)

            guard let maskImage = image.cgImage else { return }

            if !isVisited {
                cgContext.saveGState()
                cgContext.clip(to: imageRect, mask: maskImage)

                if let highlightGradient = CGGradient(
                    colorsSpace: CGColorSpaceCreateDeviceRGB(),
                    colors: [
                        UIColor.white.withAlphaComponent(0.26).cgColor,
                        UIColor.clear.cgColor,
                        color.withAlphaComponent(0.14).cgColor
                    ] as CFArray,
                    locations: [0, 0.45, 1]
                ) {
                    cgContext.drawLinearGradient(
                        highlightGradient,
                        start: CGPoint(x: size.width * 0.2, y: size.height * 0.08),
                        end: CGPoint(x: size.width * 0.76, y: size.height * 0.86),
                        options: []
                    )
                }

                cgContext.restoreGState()
            } else {
                cgContext.saveGState()
                cgContext.clip(to: imageRect, mask: maskImage)
                cgContext.setFillColor(UIColor.systemGray2.withAlphaComponent(0.22).cgColor)
                cgContext.fill(imageRect)
                cgContext.restoreGState()
            }
        }

        renderedImageCache[cacheKey] = result
        return result
    }

    private static func cachedImage(for style: IsometricBuildingStyle) -> UIImage {
        cachedImage(for: style.assetName)
    }

    private static func cachedImage(for assetName: String) -> UIImage {
        if let cached = sourceImageCache[assetName] {
            return cached
        }

        let loadedImage: UIImage
        if let url = Bundle.main.url(forResource: assetName, withExtension: "png", subdirectory: "Resources/MapIcons"),
           let image = UIImage(contentsOfFile: url.path) {
            loadedImage = image
        } else if let image = UIImage(named: assetName) {
            loadedImage = image
        } else {
            loadedImage = UIImage()
        }

        sourceImageCache[assetName] = loadedImage
        return loadedImage
    }
}
