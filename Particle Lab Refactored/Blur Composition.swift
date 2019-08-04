//
//  BlurComposition2.swift
//
//
//  Created by Caleb on 1/5/18.
//

import Foundation
import Metal
import simd
import MetalPerformanceShaders

struct CompositionPart:Equatable {
    var weight:Float
    var instruction:[Int] = []
    var level:Float
    
    static func ==(lhs:CompositionPart, rhs:CompositionPart) -> Bool {
        if lhs.instruction.count != rhs.instruction.count {
            return false
        }
        for i in 0..<lhs.instruction.count {
            if (lhs.instruction[i] != rhs.instruction[i]) {
                return false
            }
        }
        return true
    }
}

class BlurCompositon {
    let format = MTLPixelFormat.bgra8Unorm
    var debug = true
    let minTextureArray:Int = 3
    let texUsage:MTLTextureUsage = [MTLTextureUsage.shaderRead, MTLTextureUsage.shaderWrite, MTLTextureUsage.renderTarget]
    let quality:Float = 1.0
    //Resolution scale mode
    let myID:Int
    let setting:ResolutionSetting = .ScaleTex
    
    static var instanceCount:Int = 0
    
    enum ResolutionSetting {
        case ScaleBlur
        case ScaleTex
        case Optimize
    }
    
    private struct textureDebug {
        var tex:MTLTexture
        var descrip:String
        
        init (_ node: DataNode) {
            tex = node.texture!
            descrip = node.debugDescription
        }
        init (tex: MTLTexture, descrip: String) {
            self.tex = tex
            self.descrip = descrip
        }
    }
    private class TreeNode {
        var step:Int
        var children:[TreeNode] = []
        init (step: Int) {
            self.step = step
        }
    }
    
    private class DataNode : TreeNode  {
        var texture:MTLTexture?
        var weight:Float?
        var steps:[Int]
        var id:Int?
        var slice:Int?
        var debugDescription:String
        init (tex: MTLTexture, data: CompositionPart, descrip: String) {
            self.texture = tex
            self.weight = data.weight
            self.debugDescription = descrip
            self.steps = data.instruction
            super.init(step: steps.last!)
        }
    }
    private class LevelData {
        var level:Float
        var textureCount:Int
        var head:TreeNode
        var setting:ResolutionSetting!
        
        init (level: Float, textureCount: Int) {
            self.level = level
            self.textureCount = textureCount
            self.head = TreeNode(step: -1)
        }
        
        
        private var cached:[DataNode]?
        func generateAsArray() -> [DataNode] {
            if cached == nil {
                var build:[DataNode] = []
                explore(node: head, array: &build)
                cached = build
            }
            return cached!
        }
        private func explore(node: TreeNode, array:inout [DataNode]) {
            for child in node.children {
                if let found = child as? DataNode {
                    array.append(found)
                } else {
                    explore(node: child, array: &array)
                }
            }
        }
    }
    private class ArrayLevel : LevelData {
        var compositeTexture:MTLTexture
        var id:Int
        init (level: Float, textureCount: Int, tex: MTLTexture, id: Int) {
            compositeTexture = tex
            self.id = id
            super.init(level: level, textureCount: textureCount)
        }
    }
    private var levels:[Float : LevelData] = [:]
    private var primedData:[Float : [CompositionPart]] = [:]
    private var prepared:Bool = false
    
    private var vertex:MTLFunction!
    private var fragment:MTLFunction!
    private var pipeline:MTLRenderPipelineState!
    private var copyPipeline:MTLRenderPipelineState!
    
    private func Kernel(_ data: Int, _ level : Float) -> Float {
        return Float(data) * level
    }
    
    init(data: [CompositionPart]) {
        myID = BlurCompositon.instanceCount
        BlurCompositon.instanceCount += 1
        
        
        if debug {
            print("Creating a new composition!")
        }
        assert(data.count > 0, "You must have at least one")
        outer: for data in data {
            assert(data.level * quality <= 1.0 || data.level * quality > 0.0, "You must have a level between 0-1")
            assert(data.instruction.count > 0, "You must have at least")
            
            var array = primedData[data.level * quality] ?? [CompositionPart]()
            for i in 0..<array.count {
                if array[i] == data {
                    array[i].weight += data.weight
                    primedData[data.level * quality] = array
                    continue outer
                }
            }
            
            array.append(data)
            primedData[data.level * quality] = array
        }
        
        if debug {
            print("We have \(primedData.keys.count) keys")
        }
    }
    
    var scaleFactor:Float = 1.0
    private var idTicker:Int = 1
    func prepare(device: MTLDevice, width: Int, height: Int, scaleFactor:Float) {
        if (!prepared && debug) {print("Cant prepare twice!")}
        let descriptor = MTLTextureDescriptor()
        descriptor.usage = texUsage
        descriptor.pixelFormat = format
        descriptor.mipmapLevelCount = 1
        
        self.scaleFactor = scaleFactor
        
        prepareCopyPipeline(device: device)
        
        
        for level in primedData.keys {
            descriptor.width = Int(Float(width) * level)
            descriptor.height = Int(Float(height) * level)
            
            var sug:ResolutionSetting = setting
            if setting == .Optimize {
                if (level * (scaleFactor / 2) > 1.0) {
                    sug = .ScaleBlur
                } else {
                    sug = .ScaleTex
                }
                
            }
            
            if sug == .ScaleTex {
                descriptor.width = Int(Float(descriptor.width) * (scaleFactor / 2))
                descriptor.height = Int(Float(descriptor.height) * (scaleFactor / 2))
            }
            
            let array = primedData[level]!
            
            if (array.count >= minTextureArray) {
                descriptor.arrayLength = array.count
                descriptor.textureType = .type2DArray
                let tex = device.makeTexture(descriptor: descriptor)
                
                if (tex == nil && debug) {print("We couldnt allocate this texture"); return}
                
                let levelData = ArrayLevel(level: level, textureCount: array.count, tex: tex!, id: idTicker)
                idTicker += 1
                
                for i in 0..<array.count {
                    let descrip = "Level \(level)'s \(i) texture [\(idTicker-1)-\(i)]"
                    //Mipmap level
                    let levelRange:Range<Int> = 0..<1
                    //Array level
                    let slicesRange:Range<Int> = i..<i+1
                    
                    let slice = tex!.makeTextureView(pixelFormat: format, textureType: .type2D, levels: levelRange, slices: slicesRange)
                    let node = DataNode(tex: slice!, data: array[i], descrip: descrip)
                    node.slice = i
                    levelData.head = buildTree(node: levelData.head, put: node, level: 0)
                }
                levelData.setting = sug
                levels[level] = levelData
            } else {
                let levelData = LevelData(level: level, textureCount: array.count)
                for i in 0..<array.count {
                    descriptor.textureType = .type2D
                    let tex = device.makeTexture(descriptor: descriptor)
                    
                    if (tex == nil && debug) {print("We couldnt allocate this texture"); return}
                    
                    let node = DataNode(tex: tex!, data: array[i], descrip: "The \(i)th texture [\(idTicker)]")
                    node.id = idTicker
                    idTicker += 1
                    levelData.head = buildTree(node: levelData.head, put: node, level: 0)
                }
                levelData.setting = sug
                levels[level] = levelData
            }
        }
        
        if debug {
            for key in levels.keys {
                printNode(level: key)
            }
            print(getShaderString())
        }
        getShaders(device: device)
        createPipeline(device: device)
        prepared = true
    }
    func createPipeline(device: MTLDevice) {
        let descrip = MTLRenderPipelineDescriptor()
        descrip.vertexFunction = vertex
        descrip.fragmentFunction = fragment
        descrip.colorAttachments[0].pixelFormat = format
        do {
            pipeline = try device.makeRenderPipelineState(descriptor: descrip)
        } catch {
        }
    }
    private func buildTree(node: TreeNode, put: DataNode, level: Int) -> TreeNode {
        let root = node
        
        if (level < put.steps.count) {
            let instruction = put.steps[level]
            let existing = node.children
            var found:Int?
            
            for i in 0..<existing.count {
                if existing[i].step == instruction {
                    found = i
                }
            }
            
            if let index = found {
                root.children[index] = buildTree(node: root.children[index], put: put, level: level + 1)
            } else {
                var newChild = TreeNode(step: instruction)
                newChild = buildTree(node: newChild, put: put, level: level + 1)
                root.children.append(newChild)
            }
        } else {
            return put
        }
        return root
    }
    
    private var transientBuffer:MTLCommandBuffer?
    private var transientDevice:MTLDevice?
    func draw(device: MTLDevice, buffer: MTLCommandBuffer, source: MTLTexture, to: MTLTexture) {
        transientBuffer = buffer
        transientDevice = device
        
        if (!prepared && debug) {print("We arent ready to draw")}
        
        if debug {print("Rendering procedure!")}
        for level in levels.keys {
            let data = levels[level]!
            if debug {print("Rendering level \(level)")}
            //Get a gaussian thing
            let leftmost = findLeftmost(node: data.head)
            
            
            if debug {print("Copying source onto sized \(leftmost.descrip)")}
            let descriptor = MTLRenderPassDescriptor()
            descriptor.colorAttachments[0].texture = leftmost.tex
            descriptor.colorAttachments[0].loadAction = .clear
            descriptor.colorAttachments[0].storeAction = .store
            descriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
            if let encoder = buffer.makeRenderCommandEncoder(descriptor: descriptor) {
                encoder.setRenderPipelineState(copyPipeline)
                encoder.setFragmentTexture(source, index: 0)
                encoder.drawPrimitives(type: MTLPrimitiveType.triangle, vertexStart: 0, vertexCount: 6)
                encoder.endEncoding()
                
            }
            
            renderHelper(node: data.head, blurredSource: leftmost, level: level, setting: data.setting)
        }
        
        
        debug = false
        
        //return
        let descrip = MTLRenderPassDescriptor()
        descrip.colorAttachments[0].texture = to
        descrip.colorAttachments[0].loadAction = .clear
        descrip.colorAttachments[0].storeAction = .store
        descrip.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
        
        if let encoder = buffer.makeRenderCommandEncoder(descriptor: descrip) {
            encoder.setRenderPipelineState(pipeline)
            
            encoder.setFragmentTexture(source, index: 0)
            for key in levels.keys {
                let data = levels[key]!
                
                if let arrayTex = data as? ArrayLevel {
                    encoder.setFragmentTexture(arrayTex.compositeTexture, index: arrayTex.id)
                } else {
                    for texture in data.generateAsArray() {
                        encoder.setFragmentTexture(texture.texture!, index: texture.id!)
                    }
                }
                

            }
            encoder.drawPrimitives(type: MTLPrimitiveType.triangle, vertexStart: 0, vertexCount: 6)
            encoder.endEncoding()
        }
    }
    private func renderHelper(node: TreeNode, blurredSource: textureDebug, level: Float, setting: ResolutionSetting) {
        //Node is above all and source is its blurred texture
        if (node.children.count > 1) {
            for i in (1..<node.children.count).reversed() {
                renderProcessWithNode(node: node.children[i], blurredSource: blurredSource, level: level, setting: setting)
            }
        }
        if let first = node.children.first {
            renderProcessWithNode(node: first, blurredSource: blurredSource, level: level, setting: setting)
        }
    }
    private func renderProcessWithNode(node: TreeNode, blurredSource: textureDebug, level: Float, setting: ResolutionSetting) {
        var source = findLeftmost(node: node)
        let kernel = Kernel(node.step, level)
        
        //resolution 2pt needs to blur 12 by 12
        //resolution 1pt needs to blur 12 by 6
        var glow = kernel
        if setting == .ScaleBlur {
            glow = glow * (level / 2)
        }
        
        let gauss = MPSImageGaussianBlur(device: transientDevice!, sigma: glow)
        if blurredSource.descrip == source.descrip {
            gauss.encode(commandBuffer: transientBuffer!, inPlaceTexture: &source.tex, fallbackCopyAllocator: nil)
        } else {
            gauss.encode(commandBuffer: transientBuffer!, sourceTexture: blurredSource.tex, destinationTexture: source.tex)
        }
        if debug { print("Blurring \(blurredSource.descrip) to \(source.descrip) with kernel \(kernel)") }
        renderHelper(node: node, blurredSource: source, level: level, setting: setting)
    }
    
    private func findLeftmost(node: TreeNode) -> textureDebug {
        if (node.children.count > 0) {
            return findLeftmost(node: node.children.first!)
        } else {
            return textureDebug((node as! DataNode))
        }
    }
    private func prepareCopyPipeline(device: MTLDevice) {
        let library = device.makeDefaultLibrary()!
        var vertex:MTLFunction?
        var fragment:MTLFunction?
        vertex = library.makeFunction(name: "vertex_copy")
        fragment = library.makeFunction(name: "fragment_copy")
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex!
        descriptor.fragmentFunction = fragment!
        descriptor.colorAttachments[0].pixelFormat = format
        do {
            copyPipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            
        }
    }
}

extension BlurCompositon {
    private func getShaders(device: MTLDevice) {
        do {
            let library = try device.makeLibrary(source: getShaderString(), options: nil)
            vertex = library.makeFunction(name: "gaussianComp\(myID)_vertex")!
            fragment = library.makeFunction(name: "gaussianComp\(myID)_fragment")!
        } catch {
            print("Couldnt compile procedural shader for the glow rendering")
        }
    }
    private func getShaderString() -> String {
        return getHeader() + "\n\n" + getStruct() + "\n\n" + vertexShader() + "\n\n" + fragmentShader()
    }
    private func getHeader() -> String {
        return "using namespace metal;\n#include <metal_stdlib>"
    }
    private func vertexShader() -> String {
        return "vertex ColorInOut gaussianComp\(myID)_vertex(uint vid [[vertex_id]]) {\n\tconst float2 coords[] = {float2(-1.0, -1.0), float2(1.0, -1.0), float2(-1.0, 1.0), float2(1.0, 1.0)};\n\tconst float2 texc[] = {float2(0.0, 1.0), float2(1.0, 1.0), float2(0.0, 0.0), float2(1.0, 0.0)};\n\tconst int lu[] = {0, 1, 2, 2, 1, 3};\n\n\tColorInOut out;\n\tout.texCoord = texc[lu[vid]];\n\tout.position = float4(coords[lu[vid]], 0.0, 1.0);\n\treturn out;\n}"
    }
     private func fragmentShader() -> String {
        var top:String = "fragment float4 gaussianComp\(myID)_fragment(ColorInOut texCoord [[stage_in]]"
        var predicate:String = "\tconstexpr sampler colorSampler(mip_filter::linear, mag_filter::linear, min_filter::linear);\n\n\treturn "
        
        top += ",\n\t\t\ttexture2d<float> texture\(0) [[texture(\(0))]]"
        predicate += "\t\t"
        predicate += "texture\(0).sample(colorSampler, texCoord.texCoord) * \(1.0)"
        
        for key in levels.keys {
            let data = levels[key]!

            if let arrayTex = data as? ArrayLevel {
                top += ",\n\t\t\ttexture2d_array<float> texture\(arrayTex.id) [[texture(\(arrayTex.id))]]"
                
                for i in 0..<arrayTex.textureCount {
                    let data = arrayTex.generateAsArray()[i]
                    
                    predicate += "\n\t\t\t + "
                    
                    predicate += "texture\(arrayTex.id).sample(colorSampler, texCoord.texCoord, \(data.slice!)) * \(data.weight!)"
                }
            } else {
                for texture in data.generateAsArray() {
                    top += ",\n\t\t\ttexture2d<float> texture\(texture.id!) [[texture(\(texture.id!))]]"
                    
                    predicate += "\n\t\t\t + "
                    
                    predicate += "texture\(texture.id!).sample(colorSampler, texCoord.texCoord) * \(texture.weight!)"
                }
            }
        }
        return top + ") {\n\n\t" + predicate + ";\n}"
    }
    private func getStruct() -> String {
        return "typedef struct\n{\n\tfloat4 position [[position]];\n\tfloat2 texCoord;\n} ColorInOut;"
    }
    
}

extension BlurCompositon {
    private func printNode(level: Float) {
        print("-------------\(level)----------")
        var lines:[String] = []
        printNodeHelper(node: levels[level]!.head, lines: &lines, offset: 0)
        for line in lines {
            print(line)
        }
        print("-------------------------------")
    }
    private func printNodeHelper(node: TreeNode, lines: inout [String], offset: Int) {
        for child in node.children {
            var off = offset
            var message = repeatSpaces(offset) + String(child.step) + "|"
            off += 3
            
            if let data = child as? DataNode {
                message += " -> " + data.debugDescription + " weight: \(data.weight!)"
            }
            
            lines.append(message)
            printNodeHelper(node: child, lines: &lines, offset: off)
        }
    }
    private func repeatSpaces(_ count: Int) -> String {
        var build = ""
        for _ in 0..<count {
            build += " "
        }
        return build
    }
}


