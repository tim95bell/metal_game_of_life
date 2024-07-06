import Foundation
import MetalKit

class GameView : MTKView {
    var renderer: MTKViewDelegate!
    
    override var acceptsFirstResponder: Bool { return true }
    
    required init(coder: NSCoder) {
        super.init(coder: coder)
        
        // Select the device to render with.  We choose the default device
        guard let defaultDevice = MTLCreateSystemDefaultDevice() else {
            print("Metal is not supported on this device")
            return
        }

        self.device = defaultDevice

//        guard let newRenderer = GameOfLifeRenderer(metalKitView: mtkView) else {
//            print("Renderer cannot be initialized")
//            return
//        }
        guard let newRenderer = SmoothLifeRenderer(metalKitView: self) else {
            print("Renderer cannot be initialized")
            return
        }
       renderer = newRenderer

        renderer.mtkView(self, drawableSizeWillChange: self.drawableSize)

        self.delegate = renderer
    }
    
    override func keyDown(with event: NSEvent) {
        if (event.keyCode == 49) {
            // space bar
            (delegate as! SmoothLifeRenderer).play_or_pause_update()
        } else if (event.keyCode == 45) {
            // n
            (delegate as! SmoothLifeRenderer).one_update()
        }
    }
}
