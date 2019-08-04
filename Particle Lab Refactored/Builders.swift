//
//  Builders.swift
//  TrippleBufferIntegration
//
//  Created by Caleb on 12/24/17.
//  Copyright © 2017 Caleb. All rights reserved.
//

import Foundation
import Metal
import MetalKit

class Builder {
    class Textures {
        static func scaleOfResolution(scale: Float, view: UIView, device: MTLDevice, usage: MTLTextureUsage, descrip: String = "") -> MTLTexture? {
            let frame = view.frame.size
            let frameScale = view.contentScaleFactor * CGFloat(scale)
            return ofResolution(width: Int(frame.width * frameScale) , height: Int(frame.height * frameScale), device: device, usage: usage, descrip: descrip)
        }
        static func ofResolution(width: Int, height: Int, device: MTLDevice, usage: MTLTextureUsage, descrip: String = "") -> MTLTexture? {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: MTLPixelFormat.bgra8Unorm, width: width, height: height, mipmapped: false)
            descriptor.usage = usage
            let tex = device.makeTexture(descriptor: descriptor)
            if (tex == nil) {
                fatalError("Couldnt create texture \(width)x\(height)")
            }
            return tex
        }
    }
}

