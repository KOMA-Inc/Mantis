import Foundation
import UIKit

extension AbstractCropView: UIScrollViewDelegate {

    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        viewModel.setTouchImageStatus()
    }

    public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        viewModel.setBetweenOperationStatus()
    }


    public func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            viewModel.setBetweenOperationStatus()
        }
    }
}
