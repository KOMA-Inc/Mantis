import UIKit

final class ViewContainer: UIView {

    init(view: UIView) {
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension ViewContainer: ImageContainerProtocol {
    func contains(rect: CGRect, fromView view: UIView, tolerance: CGFloat = 0.5) -> Bool {
        let newRect = view.convert(rect, to: self)

        let point1 = newRect.origin
        let point2 = CGPoint(x: newRect.maxX, y: newRect.maxY)

        let refBounds = bounds.insetBy(dx: -tolerance, dy: -tolerance)

        return refBounds.contains(point1) && refBounds.contains(point2)
    }

    func getCropRegion(withCropBoxFrame cropBoxFrame: CGRect, cropView: UIView) -> CropRegion {
        var topLeft = cropView.convert(CGPoint(x: cropBoxFrame.minX, y: cropBoxFrame.minY), to: self)
        var topRight = cropView.convert(CGPoint(x: cropBoxFrame.maxX, y: cropBoxFrame.minY), to: self)
        var bottomLeft = cropView.convert(CGPoint(x: cropBoxFrame.minX, y: cropBoxFrame.maxY), to: self)
        var bottomRight = cropView.convert(CGPoint(x: cropBoxFrame.maxX, y: cropBoxFrame.maxY), to: self)

        topLeft = CGPoint(x: topLeft.x / bounds.width, y: topLeft.y / bounds.height)
        topRight = CGPoint(x: topRight.x / bounds.width, y: topRight.y / bounds.height)
        bottomLeft = CGPoint(x: bottomLeft.x / bounds.width, y: bottomLeft.y / bounds.height)
        bottomRight = CGPoint(x: bottomRight.x / bounds.width, y: bottomRight.y / bounds.height)

        return CropRegion(
            topLeft: topLeft,
            topRight: topRight,
            bottomLeft: bottomLeft,
            bottomRight: bottomRight
        )
    }
}
