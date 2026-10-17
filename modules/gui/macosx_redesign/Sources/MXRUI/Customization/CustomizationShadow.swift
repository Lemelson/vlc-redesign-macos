import MXRDesign
import SwiftUI

extension View {
    /// S66/S68 set `showShadowBehindNode: false`: translucent fills retain their
    /// token alpha while the drop shadow is drawn only outside the rounded surface.
    func customizationShadow(_ shadow: Theme.Shadow, cornerRadius: CGFloat) -> some View {
        background {
            let shape = RoundedRectangle(cornerRadius: cornerRadius)
            shape.fill(shadow.color.color)
                .blur(radius: shadow.radius)
                .offset(x: shadow.x, y: shadow.y)
                .mask {
                    Rectangle()
                        .padding(-(shadow.blur + max(abs(shadow.x), abs(shadow.y))))
                        .overlay { shape.fill(.black).blendMode(.destinationOut) }
                        .compositingGroup()
                }
        }
    }
}
