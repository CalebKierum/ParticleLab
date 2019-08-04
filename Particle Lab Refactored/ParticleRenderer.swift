//
//  Renderer.swift
//  Particle Lab Refactored
//
//  Created by Caleb on 12/29/17.
//  Copyright © 2017 Caleb. All rights reserved.
//

import Metal
import MetalKit
import simd
import MetalPerformanceShaders

let level:Float = 0.5

class ParticleRenderer: NSObject, MTKViewDelegate {
    var device:MTLDevice
    var computePipeline:MTLComputePipelineState!
    var addPipeline:MTLComputePipelineState!
    var queue:MTLCommandQueue
    
    var width:Int
    var height:Int
    var fwidth:float_t
    var fheight:float_t
    
    var particleColor = ParticleColor(R: 1, G: 0.8, B: 0.4, A: 1)
    
    var gravityWells = Particle(A: float4(x: 0, y: 0, z: 0, w: 0),
                                       B: float4(x: 0, y: 0, z: 0, w: 0),
                                       C: float4(x: 0, y: 0, z: 0, w: 0),
                                       D: float4(x: 0, y: 0, z: 0, w: 0))
    
    let vc:GameViewController!
    
    var bytesPerRow:Int!
    var threadgroupsPerGrid:MTLSize!
    var threadgroupsPerThreadgroup:MTLSize!
    
    var particleBuffer:MTLBuffer?
    var data:UnsafeMutablePointer<Particle>?
    
    let tex1:MTLTexture
    let tex2:MTLTexture
    let blankTex:MTLTexture
    
    let blur:MPSImageGaussianBlur
    let erode:MPSImageAreaMin
    
    
    var blurThing = BlurCompositon(data: [CompositionPart(weight: 1.0, instruction: [5], level: level),
                                          CompositionPart(weight: 1.0, instruction: [11], level: level),
                                          CompositionPart(weight: 1.0, instruction: [21], level: level),
                                          CompositionPart(weight: 1.0, instruction: [41], level: level)])
    
    init?(view: MTKView, viewController:GameViewController) {
        device = view.device!
        if let temp = device.makeCommandQueue() {
            queue = temp
        } else {fatalError("Couldnt create a command queue")}
        let factor:CGFloat = UIScreen.main.scale
        width = Int(CGFloat(view.frame.size.width) * factor)
        height = Int(CGFloat(view.frame.size.height) * factor)
        fwidth = float_t(width); fheight = float_t(height)
        vc = viewController
        let usage:MTLTextureUsage = [MTLTextureUsage.shaderRead, MTLTextureUsage.shaderWrite, MTLTextureUsage.renderTarget]
        tex1 = Builder.Textures.scaleOfResolution(scale: 1.0, view: view, device: device, usage: usage, descrip: "Draw On")!
        tex2 = Builder.Textures.scaleOfResolution(scale: 1.0, view: view, device: device, usage: usage, descrip: "Blur Tex")!
        blankTex = Builder.Textures.scaleOfResolution(scale: 1.0, view: view, device: device, usage: usage, descrip: "Blank")!
        blur = MPSImageGaussianBlur(device: device, sigma: 3)
        erode = MPSImageAreaMin(device: device, kernelWidth: 5, kernelHeight: 5)
        super.init()
        computePipeline = createComputePipeline()
        addPipeline = createAddPipeline()
        calculateComputeSettings()
        initiailzeParticles()
        resetParticles()
        
        print("Scale factor \(view.contentScaleFactor)")
        blurThing.prepare(device: device, width: width, height: height, scaleFactor: Float(view.contentScaleFactor))
    }
    func calculateComputeSettings() {
        let threadExecutionWidth = computePipeline.threadExecutionWidth
        bytesPerRow = 4 * width
        threadgroupsPerGrid = MTLSize(width: (Settings.particleCount / 4) / threadExecutionWidth, height: 1, depth: 1)
        threadgroupsPerThreadgroup = MTLSize(width: threadExecutionWidth, height: 1, depth: 1)
    }
    func createComputePipeline() -> MTLComputePipelineState {
        if let library = device.makeDefaultLibrary() {
            let kernelFunction = library.makeFunction(name: "particleRendererShader")!
            
            do {
                return try device.makeComputePipelineState(function: kernelFunction)
            } catch {
                fatalError("Couldnt create the compute pipeline")
            }
        } else {
            fatalError("Could not create default library")
        }
    }
    func createAddPipeline() -> MTLComputePipelineState {
        if let library = device.makeDefaultLibrary() {
            let kernelFunction = library.makeFunction(name: "addKernel")!
            
            do {
                return try device.makeComputePipelineState(function: kernelFunction)
            } catch {
                fatalError("Couldnt create the compute pipeline")
            }
        } else {
            fatalError("Could not create default library")
        }
    }
    
    var frameStart:CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
    var stringDescription:String = ""
    var saveSetting:RenderMode = RenderMode.Regular
    var okToRender:Bool = true
    var pauseFrames:Int = 0
    func draw(in view: MTKView) {
        calculateComputeSettings()
        let newSetting = Settings.render
        if let buffer =  queue.makeCommandBuffer() {
            if (newSetting != saveSetting) {
                print("Clearing for new mode")
                clearImage(tex: tex1, buffer: buffer)
                clearImage(tex: tex2, buffer: buffer)
                if let drawable = view.currentDrawable {
                    clearImage(tex: drawable.texture, buffer: buffer)
                    buffer.present(drawable, afterMinimumDuration: 1 / 60)
                    saveSetting = newSetting
                }
                pauseFrames = 0
                buffer.commit()
            } else if (pauseFrames > 0) {
                pauseFrames -= 1
                if let drawable = view.currentDrawable {
                    clearImage(tex: drawable.texture, buffer: buffer)
                    buffer.present(drawable)
                    buffer.commit()
                }
            } else {
                switch (saveSetting) {
                case .Cloud:
                    drawCloud(buffer: buffer, view: view)
                case .Glow:
                    drawGlow(buffer: buffer, view: view)
                case .Regular:
                    drawRegular(buffer: buffer, view: view)
                }
                
                buffer.addCompletedHandler { (_ commandBuffer)-> Swift.Void in
                    self.calculateFPS()
                }
                
                buffer.commit()
                buffer.waitUntilCompleted()
                vc.update(status: stringDescription)
            }
        }
    }
    func drawGlow(buffer: MTLCommandBuffer, view: MTKView) {
        /*if let drawable = view.currentDrawable {
            clearImage(tex: drawable.texture, buffer: buffer)
            clearImage(tex: tex1, buffer: buffer)
            runParticleSimulationOnTexture(tex: tex1, buffer: buffer)
            blurThing.prepareToDraw(source: tex1, buffer: buffer, device: device)
            blurThing.draw(buffer: buffer, source: tex1, to: drawable.texture)
            buffer.present(drawable)
        }*/
        
        clearImage(tex: tex1, buffer: buffer)
        clearImage(tex: tex2, buffer: buffer)
        runParticleSimulationOnTexture(tex: tex1, buffer: buffer)
        blurThing.draw(device: device, buffer: buffer, source: tex1, to: tex2)
        if let drawable = view.currentDrawable {
            copyTexture(tex: tex2, onto: drawable.texture, buffer: buffer)
            buffer.present(drawable)
        }
    }
    func drawRegular(buffer: MTLCommandBuffer, view: MTKView) {
        if let drawable = view.currentDrawable {
            clearImage(tex: drawable.texture, buffer: buffer)
            clearImage(tex: tex1, buffer: buffer)
            runParticleSimulationOnTexture(tex: drawable.texture, buffer: buffer)
            buffer.present(drawable)
        }
        /*clearImage(tex: tex1, buffer: buffer)
        runParticleSimulationOnTexture(tex: tex1, buffer: buffer)
        if let drawable = view.currentDrawable {
            copyTexture(tex: tex1, onto: drawable.texture, buffer: buffer)
            drawable.present(afterMinimumDuration: 1 / 60.0)
        }*/
    }
    func drawCloud(buffer: MTLCommandBuffer, view: MTKView) {
        /*if let drawable = view.currentDrawable {
            runParticleSimulationOnTexture(tex: drawable.texture, buffer: buffer)
            makeCloudy(tex: drawable.texture, buffer: buffer)
            buffer.present(drawable)
        }*/
        runParticleSimulationOnTexture(tex: tex1, buffer: buffer)
        makeCloudy(tex: tex1, buffer: buffer)
        if let drawable = view.currentDrawable {
            copyTexture(tex: tex1, onto: drawable.texture, buffer: buffer)
            buffer.present(drawable)
        }
        
    }
    var timeBuffer = FloatQueue()
    var block:Bool = true
    var archive = FloatQueue()
    func calculateFPS() {
        let frametime = Float(CFAbsoluteTimeGetCurrent() - frameStart)
        if (!block) {
            timeBuffer.add(frametime)
        }
        block = false
        if (timeBuffer.sum() > 1) {
            archive = timeBuffer
            timeBuffer = FloatQueue()
            let average = 1 / (archive.sum() / Float(archive.count()))
            let std = archive.standardDeviation() * 1000
            stringDescription = "\(cleanAmmount(Settings.particleCount)) particles at \(round(average * 10) / 10) fps (Deviation: \(round(std * 10) / 10) ms)"
            block = true
        }
        frameStart = CFAbsoluteTimeGetCurrent()
        okToRender = true
    }
    func cleanAmmount(_ number: Int) -> String {
        let decimal = Float(number)
        if (number >= 1000000) {
            let num = round((decimal / 1000000) * 10) / 10
            return String(num) + " million"
        } else if (number >= 1000) {
            let num = round((decimal / 1000) * 10) / 10
            return String(num) + " thousand"
        } else if (number >= 100) {
            let num = round((decimal / 100) * 10) / 10
            return String(num) + " hundred"
        } else {
            return String(number)
        }
    }
    func copyTexture(tex: MTLTexture, onto: MTLTexture, buffer: MTLCommandBuffer) {
        if let encoder = buffer.makeBlitCommandEncoder() {
            let origin = MTLOriginMake(0, 0, 0)
            let size = MTLSizeMake(tex.width, tex.height, tex.depth)
            encoder.copy(from: tex, sourceSlice: 0, sourceLevel: 0, sourceOrigin: origin, sourceSize: size, to: onto, destinationSlice: 0, destinationLevel: 0, destinationOrigin: origin)
            encoder.endEncoding()
        } else {
            print("Could not preform the copy")
        }
    }
    
    func makeCloudy(tex: MTLTexture, buffer: MTLCommandBuffer) {
        let inPlace = UnsafeMutablePointer<MTLTexture>.allocate(capacity: 1)
        inPlace.initialize(to: tex)
        
        blur.encode(commandBuffer: buffer, inPlaceTexture: inPlace, fallbackCopyAllocator: nil)
        erode.encode(commandBuffer: buffer, inPlaceTexture: inPlace, fallbackCopyAllocator: nil)
    }
    func makeGlowy(source: MTLTexture, accessoryTexture: MTLTexture, onto: MTLTexture, buffer: MTLCommandBuffer) {
        let blur = MPSImageGaussianBlur(device: device, sigma: 6)
        
        //5  =
        //10 =
        blur.encode(commandBuffer: buffer, sourceTexture: source, destinationTexture: accessoryTexture)
        
        if let encoder2 = buffer.makeComputeCommandEncoder() {
            encoder2.setComputePipelineState(addPipeline)
            //Primart
            encoder2.setTexture(source, index: 0)
            //Mask
            encoder2.setTexture(accessoryTexture, index: 1)
            //Output
            encoder2.setTexture(onto, index: 2)
            
            
            let threadGroupSize = MTLSize(width: 8, height: 8, depth: 1)
            let numGroups = MTLSize(
                width: width/threadGroupSize.width+1,
                height: height/threadGroupSize.height+1,
                depth: 1)
            encoder2.dispatchThreadgroups(numGroups, threadsPerThreadgroup: threadGroupSize)
            encoder2.endEncoding()
        }
    }
    func runParticleSimulationOnTexture(tex: MTLTexture, buffer: MTLCommandBuffer) {
        if let encoder = buffer.makeComputeCommandEncoder() {
            encoder.setComputePipelineState(computePipeline)
            
            encoder.setBuffer(particleBuffer, offset: 0, index: 0)
            encoder.setBuffer(particleBuffer, offset: 0, index: 1)
            encoder.setBytes(&gravityWells, length: MemoryLayout<Particle>.stride, index: 2)
            encoder.setBytes(&particleColor, length: MemoryLayout<ParticleColor>.stride, index: 3)
            encoder.setBytes(&fwidth, length: MemoryLayout<Float>.stride, index: 4)
            encoder.setBytes(&fheight, length: MemoryLayout<Float>.stride, index: 5)//Likely what goes here but not sure
            encoder.setBytes(&Settings.dragFactor, length: MemoryLayout<Float>.stride, index: 6)
            encoder.setBytes(&Settings.respawnOutOfBoundsParticles, length: MemoryLayout<Bool>.stride, index: 7)
            
            //NOTE: Drawable.texture may not compile if a device is not plugged in
            encoder.setTexture(tex, index: 0)
            encoder.dispatchThreadgroups(threadgroupsPerGrid, threadsPerThreadgroup: threadgroupsPerThreadgroup)
            encoder.endEncoding()
        } else {
            print("Could not complete texture drawaing")
        }
    }
    func clearImage(tex: MTLTexture, buffer: MTLCommandBuffer) {
        copyTexture(tex: blankTex, onto: tex, buffer: buffer)
    }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        let scaleFactor:CGFloat = 1
        width = Int(CGFloat(size.width) * scaleFactor)
        height = Int(CGFloat(size.height) * scaleFactor)
        fwidth = float_t(width); fheight = float_t(height)
        print("View is now \(width) wide x \(height) high")
    }
}

extension ParticleRenderer {
    func initiailzeParticles() {
        let idealOffset = 16
        let count = 16_000_000 / 4
        let defSize = MemoryLayout<Particle>.size * count
        let byteAllignedSize = (((defSize) + (idealOffset - 1)) / (idealOffset)) * (idealOffset)
        particleBuffer = device.makeBuffer(length: byteAllignedSize, options: [])!
        data = UnsafeMutableRawPointer(particleBuffer!.contents()).bindMemory(to:Particle.self, capacity:count)
    }
    
    func resetParticles(start: Int, end: Int) {
        func rand() -> Float32
        {
            return Float(drand48() - 0.5) * 0.005
        }
        let mode = arc4random_uniform(3)
        
        var velocity:Float = 1
        var squareUp = false
        if (mode == 0) {
            squareUp = true
            velocity = 10
        } else if (mode == 2) {
            velocity = 50
        } else {
            velocity = 1
        }
        
        let floatWidth = Float(width)
        let floatHeight = Float(height)
        
        for index in start..<end {
            
            if (mode == 2) {
                let variance = Int(arc4random_uniform(3)) - 1
                velocity += Float(variance) * 0.1
            }
            
            var positionAX = Float(drand48()) * floatWidth
            var positionAY = Float(drand48()) * floatHeight
            
            var positionBX = Float(drand48()) * floatWidth
            var positionBY = Float(drand48()) * floatHeight
            
            var positionCX = Float(drand48()) * floatWidth
            var positionCY = Float(drand48()) * floatHeight
            
            var positionDX = Float(drand48()) * floatWidth
            var positionDY = Float(drand48()) * floatHeight
            
            if squareUp
            {
                let positionRule = Int(arc4random() % 4)
                
                let padding:Float = 100
                if positionRule == 0
                {
                    positionAX = 0
                    positionBX = 0
                    positionCX = 0
                    positionDX = 0
                }
                else if positionRule == 1
                {
                    positionAX = floatWidth
                    positionBX = floatWidth
                    positionCX = floatWidth
                    positionDX = floatWidth
                }
                else if positionRule == 2
                {
                    positionAY = 0
                    positionBY = 0
                    positionCY = 0
                    positionDY = 0
                }
                else
                {
                    positionAY = floatHeight
                    positionBY = floatHeight
                    positionCY = floatHeight
                    positionDY = floatHeight
                }
                if (positionBY < floatHeight / 2) {
                    positionBY += padding
                } else {
                    positionBY -= padding
                }
                if (positionAY < floatHeight / 2) {
                    positionAY += padding
                } else {
                    positionAY -= padding
                }
                if (positionCY < floatHeight / 2) {
                    positionCY += padding
                } else {
                    positionCY -= padding
                }
                if (positionDY < floatHeight / 2) {
                    positionDY += padding
                } else {
                    positionDY -= padding
                }
                
                if (positionAX < floatWidth / 2) {
                    positionAX += padding
                } else {
                    positionAX -= padding
                }
                if (positionBX < floatWidth / 2) {
                    positionBX += padding
                } else {
                    positionBX -= padding
                }
                if (positionCX < floatWidth / 2) {
                    positionCX += padding
                } else {
                    positionCX -= padding
                }
                if (positionDX < floatWidth / 2) {
                    positionDX += padding
                } else {
                    positionDX -= padding
                }
                
            }
            
            let arr:[Float] = [1.3, 1.1, 0.7]
            let i1 = arr[index % 3]
            let particle = Particle(A: velocityTowordsCenter(x: positionAX, y: positionAY, vel: velocity * i1),
                                    B: velocityTowordsCenter(x: positionBX, y: positionBY, vel: velocity * i1),
                                    C: velocityTowordsCenter(x: positionCX, y: positionCY, vel: velocity * i1),
                                    D: velocityTowordsCenter(x: positionDX, y: positionDY, vel: velocity * i1))
            
            data![index] = particle
        }
    }
    func resetParticles() {
        resetParticles(start: 0, end: Settings.particleCount / 4)
    }
    func velocityTowordsCenter(x: Float, y: Float, vel: Float) -> float4 {
        let dx = x - (fwidth / 2)
        let dy = y - (fheight / 2)
        let angle:Float = atan2(dy, dx)
        let mag:Float = -vel
        return float4(x: x, y: y, z: mag * cos(angle), w: mag * sin(angle))
    }
    func resetGravityWells() {
        setGravityWellProperties(gravityWell: .One, normalisedPositionX: 0.5, normalisedPositionY: 0.5, mass: 0, spin: 0)
        setGravityWellProperties(gravityWell: .Two, normalisedPositionX: 0.5, normalisedPositionY: 0.5, mass: 0, spin: 0)
        setGravityWellProperties(gravityWell: .Three, normalisedPositionX: 0.5, normalisedPositionY: 0.5, mass: 0, spin: 0)
        setGravityWellProperties(gravityWell: .Four, normalisedPositionX: 0.5, normalisedPositionY: 0.5, mass: 0, spin: 0)
    }
    func getGravityWellNormalisedPosition(gravityWell: GravityWell) -> (x: Float, y: Float)
    {
        let returnPoint: (x: Float, y: Float)
        
        let imageWidthFloat = Float(width)
        let imageHeightFloat = Float(height)
        
        switch gravityWell
        {
        case .One:
            returnPoint = (x: gravityWells.A.x / imageWidthFloat, y: gravityWells.A.y / imageHeightFloat)
        case .Two:
            returnPoint = (x: gravityWells.B.x / imageWidthFloat, y: gravityWells.B.y / imageHeightFloat)
        case .Three:
            returnPoint = (x: gravityWells.C.x / imageWidthFloat, y: gravityWells.C.y / imageHeightFloat)
        case .Four:
            returnPoint = (x: gravityWells.D.x / imageWidthFloat, y: gravityWells.D.y / imageHeightFloat)
        }
        return returnPoint
    }
    func setGravityWellProperties(gravityWellIndex: Int, normalisedPositionX: Float, normalisedPositionY: Float, mass: Float, spin: Float)
    {
        switch gravityWellIndex
        {
        case 1:
            setGravityWellProperties(gravityWell: .Two, normalisedPositionX: normalisedPositionX, normalisedPositionY: normalisedPositionY, mass: mass, spin: spin)
        case 2:
            setGravityWellProperties(gravityWell: .Three, normalisedPositionX: normalisedPositionX, normalisedPositionY: normalisedPositionY, mass: mass, spin: spin)
        case 3:
            setGravityWellProperties(gravityWell: .Four, normalisedPositionX: normalisedPositionX, normalisedPositionY: normalisedPositionY, mass: mass, spin: spin)
        default:
            setGravityWellProperties(gravityWell: .One, normalisedPositionX: normalisedPositionX, normalisedPositionY: normalisedPositionY, mass: mass, spin: spin)
        }
    }
    func setGravityWellProperties(gravityWell: GravityWell, normalisedPositionX: Float, normalisedPositionY: Float, mass: Float, spin: Float)
    {
        let imageWidthFloat = Float(width)
        let imageHeightFloat = Float(height)
        
        switch gravityWell
        {
        case .One:
            gravityWells.A.x = imageWidthFloat * normalisedPositionX
            gravityWells.A.y = imageHeightFloat * normalisedPositionY
            gravityWells.A.z = mass
            gravityWells.A.w = spin
        case .Two:
            gravityWells.B.x = imageWidthFloat * normalisedPositionX
            gravityWells.B.y = imageHeightFloat * normalisedPositionY
            gravityWells.B.z = mass
            gravityWells.B.w = spin
        case .Three:
            gravityWells.C.x = imageWidthFloat * normalisedPositionX
            gravityWells.C.y = imageHeightFloat * normalisedPositionY
            gravityWells.C.z = mass
            gravityWells.C.w = spin
        case .Four:
            gravityWells.D.x = imageWidthFloat * normalisedPositionX
            gravityWells.D.y = imageHeightFloat * normalisedPositionY
            gravityWells.D.z = mass
            gravityWells.D.w = spin
        }
    }
}
