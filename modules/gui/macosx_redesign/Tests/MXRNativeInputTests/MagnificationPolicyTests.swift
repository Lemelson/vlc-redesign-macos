import Foundation

@main
struct MagnificationPolicyTests {
    static func main() {
        var gesture = MXRFullscreenMagnification()
        precondition(gesture.consume(0.15) == nil)
        precondition(gesture.consume(0.14) == nil)
        precondition(gesture.consume(0.02) == true, "Outward pinch requests fullscreen")
        precondition(gesture.consume(-1) == nil, "A gesture issues only one request")
        gesture.begin()
        precondition(gesture.consume(-0.31) == false, "Inward pinch requests windowed mode")
        gesture.begin()
        precondition(gesture.consume(0.2) == nil)
        precondition(gesture.consume(-0.2) == nil, "Reversals cancel accumulated movement")
        precondition(gesture.consume(0.1) == nil)
        print("PASS: magnification accumulation, direction, one action per gesture, reset")
    }
}
