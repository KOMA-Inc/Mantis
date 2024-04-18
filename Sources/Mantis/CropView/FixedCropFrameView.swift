import UIKit

public final class FixedCropFrameView: UIView {
    var view: UIView

    let viewModel: CropViewModelProtocol

    var aspectRatioLockEnabled = false

    // Referred to in extension
    let imageContainer: ImageContainerProtocol
    let cropWorkbenchView: CropWorkbenchViewProtocol
    let cropMaskViewManager: CropMaskViewManagerProtocol

    var rotationControlView: RotationControlViewProtocol? {
        didSet {
            if rotationControlView?.isAttachedToCropView == true {
                addSubview(rotationControlView!)
            }
        }
    }

    var isManuallyZoomed = false
    var forceFixedRatio = false
    var checkForForceFixedRatioFlag = false
    let cropViewConfig: CropViewConfig

    private var flipOddTimes = false

    lazy private var activityIndicator: ActivityIndicatorProtocol = {
        let activityIndicator: ActivityIndicatorProtocol
        if let indicator = cropViewConfig.cropActivityIndicator {
            activityIndicator = indicator
        } else {
            let indicator = UIActivityIndicatorView(frame: .zero)
            indicator.color = .white
            indicator.transform = CGAffineTransform(scaleX: 2.0, y: 2.0)
            activityIndicator = indicator
        }

        addSubview(activityIndicator)
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.centerXAnchor.constraint(equalTo: centerXAnchor).isActive = true
        activityIndicator.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
        activityIndicator.widthAnchor.constraint(equalToConstant: cropViewConfig.cropActivityIndicatorSize.width).isActive = true
        activityIndicator.heightAnchor.constraint(equalToConstant: cropViewConfig.cropActivityIndicatorSize.width).isActive = true

        return activityIndicator
    }()

    deinit {
        print("CropView deinit.")
    }

    init(
        view: UIView,
        cropViewConfig: CropViewConfig,
        viewModel: CropViewModelProtocol,
        imageContainer: ImageContainerProtocol,
        cropWorkbenchView: CropWorkbenchViewProtocol,
        cropMaskViewManager: CropMaskViewManagerProtocol
    ) {
        self.view = view
        self.cropViewConfig = cropViewConfig
        self.viewModel = viewModel
        self.imageContainer = imageContainer
        self.cropWorkbenchView = cropWorkbenchView
        self.cropMaskViewManager = cropMaskViewManager

        super.init(frame: .zero)

        (cropWorkbenchView as? CropWorkbenchView)?.isScrollEnabled = false

        if let color = cropViewConfig.backgroundColor {
            self.backgroundColor = color
        }

        viewModel.statusChanged = { [weak self] status in
            self?.render(by: status)
        }

        viewModel.cropBoxFrameChanged = { [weak self] cropBoxFrame in
            self?.handleCropBoxFrameChange(cropBoxFrame)
        }

        viewModel.setInitialStatus()

        isUserInteractionEnabled = false
    }

    public var ratio: CGFloat {
        cropWorkbenchView.bounds.width / cropWorkbenchView.bounds.height
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func handleCropBoxFrameChange(_ cropBoxFrame: CGRect) {
        cropMaskViewManager.adaptMaskTo(match: cropBoxFrame, cropRatio: 1)
    }

    private func initialRender() {
        setupCropWorkbenchView()
    }

    private func render(by viewStatus: CropViewStatus) {
        switch viewStatus {
        case .initial:
            initialRender()
        case .rotating:
            rotateCropWorkbenchView()
        case .degree90Rotating:
            cropMaskViewManager.showVisualEffectBackground(animated: true)
            toggleRotationControlViewIsNeeded(isHidden: true)
        case .touchImage:
            cropMaskViewManager.showDimmingBackground(animated: true)
        case .touchCropboxHandle:
            toggleRotationControlViewIsNeeded(isHidden: true)
            cropMaskViewManager.showDimmingBackground(animated: true)
        case .touchRotationBoard:
            cropMaskViewManager.showDimmingBackground(animated: true)
        case .betweenOperation:
            toggleRotationControlViewIsNeeded(isHidden: false)
            adaptRotationControlViewToCropBoxIfNeeded()
            cropMaskViewManager.showVisualEffectBackground(animated: true)
        }
    }

    private func toggleRotationControlViewIsNeeded(isHidden: Bool) {
        if rotationControlView?.isAttachedToCropView == true {
            rotationControlView?.isHidden = isHidden
        }
    }

    private func imageStatusChanged() -> Bool {
        if viewModel.getTotalRadians() != 0 {
            return true
        }

        if forceFixedRatio {
            if checkForForceFixedRatioFlag {
                checkForForceFixedRatioFlag = false
                return cropWorkbenchView.zoomScale != 1
            }
        }

        if !isTheSamePoint(point1: getImageLeftTopAnchorPoint(), point2: .zero) {
            return true
        }

        if !isTheSamePoint(point1: getImageRightBottomAnchorPoint(), point2: CGPoint(x: 1, y: 1)) {
            return true
        }

        return false
    }

    public func resetComponents() {
        cropMaskViewManager.setup(in: self, cropRatio: CGFloat(getImageHorizontalToVerticalRatio()))

        viewModel.resetCropFrame(by: getInitialCropBoxRect())
        cropWorkbenchView.resetImageContent(by: viewModel.cropBoxFrame)

        setupRotationDialIfNeeded()

        if aspectRatioLockEnabled {
            setFixedRatioCropBox()
        }
    }

    public func resetAspectRatioLockEnabled(by presetFixedRatioType: PresetFixedRatioType) {
        switch presetFixedRatioType {
        case .alwaysUsingOnePresetFixedRatio:
            aspectRatioLockEnabled = true
        case .canUseMultiplePresetFixedRatio:
            aspectRatioLockEnabled = false
        case .canUseMultiplePresetRatio:
            aspectRatioLockEnabled = false
        }
    }

    private func setupCropWorkbenchView() {
        cropWorkbenchView.touchesBegan = { [weak self] in
            self?.viewModel.setTouchImageStatus()
        }

        cropWorkbenchView.touchesEnded = { [weak self] in
            self?.viewModel.setBetweenOperationStatus()
        }

        addSubview(cropWorkbenchView)

        if cropViewConfig.minimumZoomScale > 1 {
            cropWorkbenchView.zoomScale = cropViewConfig.minimumZoomScale
        }
    }

    /** This function is for correct flips. If rotating angle is exact ±45 degrees,
     the flip behaviour will be incorrect. So we need to limit the rotating angle. */
    private func clampAngle(_ angle: Angle) -> Angle {
        let errorMargin = 1e-10
        let rotationLimit = Constants.rotationDegreeLimit

        return angle.degrees > 0
        ? min(angle, Angle(degrees: rotationLimit - errorMargin))
        : max(angle, Angle(degrees: -rotationLimit + errorMargin))
    }

    private func setupRotationDialIfNeeded() {
        guard let rotationControlView = rotationControlView else {
            return
        }

        rotationControlView.reset()
        rotationControlView.isUserInteractionEnabled = true

        rotationControlView.didUpdateRotationValue = { [unowned self] angle in
            self.viewModel.setTouchRotationBoardStatus()
            self.viewModel.setRotatingStatus(by: clampAngle(angle))
        }

        rotationControlView.didFinishRotation = { [unowned self] in
            self.viewModel.setBetweenOperationStatus()
        }

        if rotationControlView.isAttachedToCropView {
            let boardLength = min(bounds.width, bounds.height) * rotationControlView.getLengthRatio()
            let dialFrame = CGRect(x: 0,
                                   y: 0,
                                   width: boardLength,
                                   height: cropViewConfig.rotationControlViewHeight)

            rotationControlView.setupUI(withAllowableFrame: dialFrame)
        }

        rotationControlView.updateRotationValue(by: Angle(radians: viewModel.radians))
        viewModel.setBetweenOperationStatus()

        adaptRotationControlViewToCropBoxIfNeeded()
        rotationControlView.bringSelfToFront()
    }

    private func adaptRotationControlViewToCropBoxIfNeeded() {
        guard let rotationControlView = rotationControlView,
              rotationControlView.isAttachedToCropView else { return }

        if Orientation.treatAsPortrait {
            rotationControlView.transform = CGAffineTransform(rotationAngle: 0)
        } else if Orientation.isLandscapeLeft {
            rotationControlView.transform = CGAffineTransform(rotationAngle: -CGFloat.pi / 2)
        } else if Orientation.isLandscapeRight {
            rotationControlView.transform = CGAffineTransform(rotationAngle: CGFloat.pi / 2)
        }

        rotationControlView.handleDeviceRotation()
    }

    private func confineTouchPoint(_ touchPoint: CGPoint, in rect: CGRect) -> CGPoint {
        var confinedPoint = touchPoint

        // Get the frame dimensions
        let rectWidth = rect.size.width
        let rectHeight = rect.size.height

        // Check if the touch point is outside the frame
        if touchPoint.x < rect.origin.x {
            confinedPoint.x = rect.origin.x
        } else if touchPoint.x > (rect.origin.x + rectWidth) {
            confinedPoint.x = rect.origin.x + rectWidth
        }

        if touchPoint.y < rect.origin.y {
            confinedPoint.y = rect.origin.y
        } else if touchPoint.y > (rect.origin.y + rectHeight) {
            confinedPoint.y = rect.origin.y + rectHeight
        }

        return confinedPoint
    }

    func updateCropBoxFrame(withTouchPoint touchPoint: CGPoint) {
        let imageContainerRect = imageContainer.convert(imageContainer.bounds, to: self)
        let imageFrame = CGRect(x: cropWorkbenchView.frame.origin.x - cropWorkbenchView.contentOffset.x,
                                y: cropWorkbenchView.frame.origin.y - cropWorkbenchView.contentOffset.y,
                                width: imageContainerRect.size.width,
                                height: imageContainerRect.size.height)

        let touchPoint = confineTouchPoint(touchPoint, in: imageFrame)
        let contentBounds = getContentBounds()
        let cropViewMinimumBoxSize = cropViewConfig.minimumCropBoxSize
        let newCropBoxFrame = viewModel.getNewCropBoxFrame(withTouchPoint: touchPoint,
                                                           andContentFrame: contentBounds,
                                                           aspectRatioLockEnabled: aspectRatioLockEnabled)

        guard newCropBoxFrame.width >= cropViewMinimumBoxSize
                && newCropBoxFrame.height >= cropViewMinimumBoxSize else {
            return
        }

        if imageContainer.contains(rect: newCropBoxFrame, fromView: self, tolerance: 0.5) {
            viewModel.cropBoxFrame = newCropBoxFrame
        } else {
            if aspectRatioLockEnabled {
                return
            }

            let minX = max(viewModel.cropBoxFrame.minX, newCropBoxFrame.minX)
            let minY = max(viewModel.cropBoxFrame.minY, newCropBoxFrame.minY)
            let maxX = min(viewModel.cropBoxFrame.maxX, newCropBoxFrame.maxX)
            let maxY = min(viewModel.cropBoxFrame.maxY, newCropBoxFrame.maxY)

            var rect: CGRect

            rect = CGRect(x: minX, y: minY, width: newCropBoxFrame.width, height: maxY - minY)
            if imageContainer.contains(rect: rect, fromView: self, tolerance: 0.5) {
                viewModel.cropBoxFrame = rect
                return
            }

            rect = CGRect(x: minX, y: minY, width: maxX - minX, height: newCropBoxFrame.height)
            if imageContainer.contains(rect: rect, fromView: self, tolerance: 0.5) {
                viewModel.cropBoxFrame = rect
                return
            }

            rect = CGRect(x: newCropBoxFrame.minX, y: minY, width: newCropBoxFrame.width, height: maxY - minY)
            if imageContainer.contains(rect: rect, fromView: self, tolerance: 0.5) {
                viewModel.cropBoxFrame = rect
                return
            }

            rect = CGRect(x: minX, y: newCropBoxFrame.minY, width: maxX - minX, height: newCropBoxFrame.height)
            if imageContainer.contains(rect: rect, fromView: self, tolerance: 0.5) {
                viewModel.cropBoxFrame = rect
                return
            }

            viewModel.cropBoxFrame = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }
    }
}

// MARK: - Adjust UI
extension FixedCropFrameView {
    private func flipCropWorkbenchViewIfNeeded() {
        if viewModel.horizontallyFlip {
            let scale: CGFloat = viewModel.rotationType.isRotatedByMultiple180 ? -1 : 1
            cropWorkbenchView.transformScaleBy(xScale: scale, yScale: -scale)
        }

        if viewModel.verticallyFlip {
            let scale: CGFloat = viewModel.rotationType.isRotatedByMultiple180 ? 1 : -1
            cropWorkbenchView.transformScaleBy(xScale: scale, yScale: -scale)
        }
    }

    private func rotateCropWorkbenchView() {
        let totalRadians = viewModel.getTotalRadians()
        cropWorkbenchView.transform = CGAffineTransform(rotationAngle: totalRadians)
        flipCropWorkbenchViewIfNeeded()
        adjustWorkbenchView(by: totalRadians)
    }

    private func getInitialCropBoxRect() -> CGRect {
        guard view.bounds.size.width > 0 && view.bounds.size.height > 0 else {
            return .zero
        }

        let outsideRect = getContentBounds()
        let insideRect: CGRect

        if viewModel.isUpOrUpsideDown() {
            insideRect = CGRect(x: 0, y: 0, width: view.bounds.size.width, height: view.bounds.size.height)
        } else {
            insideRect = CGRect(x: 0, y: 0, width: view.bounds.size.height, height: view.bounds.size.width)
        }

        return GeometryHelper.getInscribeRect(fromOutsideRect: outsideRect, andInsideRect: insideRect)
    }

    func getContentBounds() -> CGRect {
        let cropViewPadding = cropViewConfig.padding

        let rect = self.bounds
        var contentRect = CGRect.zero

        var rotationControlViewHeight: CGFloat = 0

        if cropViewConfig.showAttachedRotationControlView && rotationControlView?.isAttachedToCropView == true {
            rotationControlViewHeight = cropViewConfig.rotationControlViewHeight
        }

        if Orientation.treatAsPortrait {
            contentRect.origin.x = rect.origin.x + cropViewPadding
            contentRect.origin.y = rect.origin.y + cropViewPadding

            contentRect.size.width = rect.width - 2 * cropViewPadding
            contentRect.size.height = rect.height - 2 * cropViewPadding - rotationControlViewHeight
        } else if Orientation.isLandscape {
            contentRect.size.width = rect.width - 2 * cropViewPadding - rotationControlViewHeight
            contentRect.size.height = rect.height - 2 * cropViewPadding

            contentRect.origin.y = rect.origin.y + cropViewPadding
            if Orientation.isLandscapeLeft {
                contentRect.origin.x = rect.origin.x + cropViewPadding
            } else {
                contentRect.origin.x = rect.origin.x + cropViewPadding + rotationControlViewHeight
            }
        }

        return contentRect
    }

    private func getImageLeftTopAnchorPoint() -> CGPoint {
        if imageContainer.bounds.size == .zero {
            return viewModel.cropLeftTopOnImage
        }

        return .zero
    }

    private func getImageRightBottomAnchorPoint() -> CGPoint {
        if imageContainer.bounds.size == .zero {
            return viewModel.cropRightBottomOnImage
        }

        return .zero
    }

    private func saveAnchorPoints() {
        viewModel.cropLeftTopOnImage = getImageLeftTopAnchorPoint()
        viewModel.cropRightBottomOnImage = getImageRightBottomAnchorPoint()
    }

    func adjustUIForNewCrop(
        contentRect: CGRect,
        animation: Bool = true,
        zoom: Bool = true,
        completion: @escaping () -> Void
    ) {

        guard viewModel.cropBoxFrame.size.width > 0 && viewModel.cropBoxFrame.size.height > 0 else {
            return
        }

        let scaleX = contentRect.width / viewModel.cropBoxFrame.size.width
        let scaleY = contentRect.height / viewModel.cropBoxFrame.size.height

        let scale = min(scaleX, scaleY)

        let newCropBounds = CGRect(x: 0, y: 0, width: viewModel.cropBoxFrame.width * scale, height: viewModel.cropBoxFrame.height * scale)

        let radians = viewModel.getTotalRadians()

        // calculate the new bounds of scroll view
        let newBoundWidth = abs(cos(radians)) * newCropBounds.size.width + abs(sin(radians)) * newCropBounds.size.height
        let newBoundHeight = abs(sin(radians)) * newCropBounds.size.width + abs(cos(radians)) * newCropBounds.size.height

        guard newBoundWidth > 0 && newBoundWidth != .infinity
                && newBoundHeight > 0 && newBoundHeight != .infinity else {
            return
        }

        // calculate the zoom area of scroll view
        var scaleFrame = viewModel.cropBoxFrame

        let refContentWidth = abs(cos(radians)) * cropWorkbenchView.contentSize.width + abs(sin(radians)) * cropWorkbenchView.contentSize.height
        let refContentHeight = abs(sin(radians)) * cropWorkbenchView.contentSize.width + abs(cos(radians)) * cropWorkbenchView.contentSize.height

        if scaleFrame.width >= refContentWidth {
            scaleFrame.size.width = refContentWidth
        }

        if scaleFrame.height >= refContentHeight {
            scaleFrame.size.height = refContentHeight
        }

        let contentOffset = cropWorkbenchView.contentOffset
        let contentOffsetCenter = CGPoint(x: (contentOffset.x + cropWorkbenchView.bounds.width / 2),
                                          y: (contentOffset.y + cropWorkbenchView.bounds.height / 2))

        cropWorkbenchView.bounds = CGRect(x: 0, y: 0, width: newBoundWidth, height: newBoundHeight)

        let newContentOffset = CGPoint(x: (contentOffsetCenter.x - newBoundWidth / 2),
                                       y: (contentOffsetCenter.y - newBoundHeight / 2))
        cropWorkbenchView.contentOffset = newContentOffset

        let newCropBoxFrame = GeometryHelper.getInscribeRect(fromOutsideRect: contentRect, andInsideRect: viewModel.cropBoxFrame)

        func updateUI(by newCropBoxFrame: CGRect, and scaleFrame: CGRect) {
            viewModel.cropBoxFrame = newCropBoxFrame

            if zoom {
                let zoomRect = convert(scaleFrame,
                                       to: cropWorkbenchView.imageContainer)
                cropWorkbenchView.zoom(to: zoomRect, animated: false)
            }
            cropWorkbenchView.updateContentOffset()
        }

        if animation {
            UIView.animate(withDuration: 0.25, animations: {
                updateUI(by: newCropBoxFrame, and: scaleFrame)
            }, completion: {_ in
                completion()
            })
        } else {
            updateUI(by: newCropBoxFrame, and: scaleFrame)
            completion()
        }

        isManuallyZoomed = true
    }

    private func adjustWorkbenchView(by radians: CGFloat) {
        if !isManuallyZoomed || cropWorkbenchView.shouldScale() {
            cropWorkbenchView.zoomScaleToBound(animated: false)
            isManuallyZoomed = false
        } else {
            cropWorkbenchView.updateMinZoomScale()
        }

        cropWorkbenchView.updateContentOffset()
    }

    func updatePositionFor90Rotation(by radians: CGFloat) {

    }
}

// MARK: - internal API
extension FixedCropFrameView {

    func getTotalRadians() -> CGFloat {
        return viewModel.getTotalRadians()
    }

    func setFixedRatioCropBox(zoom: Bool = true, cropBox: CGRect? = nil) {
        let refCropBox = cropBox ?? getInitialCropBoxRect()
        let imageHorizontalToVerticalRatio = ImageHorizontalToVerticalRatio(ratio: getImageHorizontalToVerticalRatio())

        viewModel.setCropBoxFrame(by: refCropBox, for: imageHorizontalToVerticalRatio)

        let contentRect = getContentBounds()
        adjustUIForNewCrop(contentRect: contentRect, animation: false, zoom: zoom) { [weak self] in
            guard let self = self else { return }
            if self.forceFixedRatio {
                self.checkForForceFixedRatioFlag = true
            }
            self.viewModel.setBetweenOperationStatus()
        }

        adaptRotationControlViewToCropBoxIfNeeded()
        cropWorkbenchView.updateMinZoomScale()
    }
}

extension FixedCropFrameView {

    private func setViewDefaultProperties() {
        clipsToBounds = true
        translatesAutoresizingMaskIntoConstraints = false
    }

    private func setForceFixedRatio(by presetFixedRatioType: PresetFixedRatioType) {
        switch presetFixedRatioType {
        case .alwaysUsingOnePresetFixedRatio:
            forceFixedRatio = true
        case .canUseMultiplePresetFixedRatio(let defaultRatio):
            forceFixedRatio = defaultRatio > 0
        case .canUseMultiplePresetRatio:
            forceFixedRatio = true
        }
    }

    public func setPresetFixedRatioType(_ presetFixedRatioType: PresetFixedRatioType) {
        setViewDefaultProperties()
        aspectRatioLockEnabled = true

        let ratio = switch presetFixedRatioType {
        case .alwaysUsingOnePresetFixedRatio(let ratio),
             .canUseMultiplePresetFixedRatio(let ratio),
             .canUseMultiplePresetRatio(let ratio):
            ratio
        }

        if viewModel.fixedImageRatio != CGFloat(ratio) {
            viewModel.fixedImageRatio = CGFloat(ratio)

            setForceFixedRatio(by: presetFixedRatioType)

            if forceFixedRatio {
                setFixedRatioCropBox(zoom: true)
            } else {
                UIView.animate(withDuration: 0.5) {
                    self.setFixedRatioCropBox(zoom: true)
                }
            }
        }
    }

    private func getImageHorizontalToVerticalRatio() -> Double {
        if viewModel.rotationType.isRotatedByMultiple180 {
            return Double(view.horizontalToVerticalRatio())
        } else {
            return Double(1 / view.horizontalToVerticalRatio())
        }
    }

    public func setFixedRatio(
        _ ratio: Double,
        zoom: Bool = true,
        presetFixedRatioType: PresetFixedRatioType
    ) {
        aspectRatioLockEnabled = true
        if viewModel.fixedImageRatio != CGFloat(ratio) {
            viewModel.fixedImageRatio = CGFloat(ratio)

            setForceFixedRatio(by: presetFixedRatioType)

            if forceFixedRatio {
                setFixedRatioCropBox(zoom: zoom)
            } else {
                UIView.animate(withDuration: 0.5) {
                    self.setFixedRatioCropBox(zoom: zoom)
                }
            }
        }
    }

    func getCropInfo() -> CropInfo {
        var scaleX = cropWorkbenchView.zoomScale
        var scaleY = cropWorkbenchView.zoomScale

        if viewModel.horizontallyFlip {
            if viewModel.rotationType.isRotatedByMultiple180 {
                scaleX = -scaleX
            } else {
                scaleY = -scaleY
            }
        }

        if viewModel.verticallyFlip {
            if viewModel.rotationType.isRotatedByMultiple180 {
                scaleY = -scaleY
            } else {
                scaleX = -scaleX
            }
        }

        let totalRadians = getTotalRadians()
        let cropRegion = imageContainer.getCropRegion(withCropBoxFrame: viewModel.cropBoxFrame,
                                                      cropView: self)

        return CropInfo(
            translation: .zero,
            rotation: totalRadians,
            scaleX: scaleX,
            scaleY: scaleY,
            cropSize: .zero,
            imageViewSize: imageContainer.bounds.size,
            cropRegion: cropRegion
        )
    }
}
