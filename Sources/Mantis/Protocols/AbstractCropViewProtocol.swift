import Foundation
import UIKit



protocol AbstractCropViewProtocol: UIView {
    var view: UIView { get set }
    var aspectRatioLockEnabled: Bool { get set }
    var delegate: CropViewDelegate? { get set }
    
    func initialSetup(delegate: CropViewDelegate, presetFixedRatioType: PresetFixedRatioType)
    func setViewDefaultProperties()
    func getRatioType(byImageIsOriginalHorizontal isHorizontal: Bool) -> RatioType
    func getImageHorizontalToVerticalRatio() -> Double
    func resetComponents()
    func resetAspectRatioLockEnabled(by presetFixedRatioType: PresetFixedRatioType)
    func prepareForViewWillTransition()
    func handleViewWillTransition()
    func setFixedRatio(_ ratio: Double, zoom: Bool, presetFixedRatioType: PresetFixedRatioType)
    func rotateBy90(withRotateType rotateType: RotateBy90DegreeType, completion: @escaping () -> Void)
    func handleAlterCropper90Degree()
    func handlePresetFixedRatio(_ ratio: Double, transformation: Transformation)
    
    func transform(byTransformInfo transformation: Transformation, isUpdateRotationControlView: Bool)
    func getTransformInfo(byTransformInfo transformInfo: Transformation) -> Transformation
    func getTransformInfo(byNormalizedInfo normalizedInfo: CGRect) -> Transformation
    func processPresetTransformation(completion: (Transformation?) -> Void)
    
    func setFreeCrop()
    func reset()
    
    func getCropInfo() -> CropInfo
}

extension AbstractCropViewProtocol {
    func setViewDefaultProperties() {
        clipsToBounds = true
        translatesAutoresizingMaskIntoConstraints = false
    }

    func rotate(by angle: Angle) {}
}
