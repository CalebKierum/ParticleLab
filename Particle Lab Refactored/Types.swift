//
//  Types.swift
//  ParticleLab
//
//  Created by Caleb on 12/26/17.
//  Copyright © 2017 Caleb. All rights reserved.
//

import Foundation
import simd

//These are each of the modes supported by the simulation
enum DemoModes: String
{
    case cloudChamber = "Cloud Chamber"
    case orbits = "Orbits"
    case multiTouch = "Multiple Touch"
}


//There are 4 gravity wells and this notifies which one is which
enum GravityWell
{
    case One
    case Two
    case Three
    case Four
}

enum RenderMode {
    case Regular
    case Glow
    case Cloud
}
 
//  Paticles are split into three classes. The supplied particle color defines one
//  third of the rendererd particles, the other two thirds use the supplied particle
//  color components but shifted to BRG and GBR
struct ParticleColor
{
    var R: Float = 0
    var G: Float = 0
    var B: Float = 0
    var A: Float = 1
}

struct Particle // Matrix4x4
{
    var A: float4 = float4(x: 0, y: 0, z: 0, w: 0)
    var B: float4 = float4(x: 0, y: 0, z: 0, w: 0)
    var C: float4 = float4(x: 0, y: 0, z: 0, w: 0)
    var D: float4 = float4(x: 0, y: 0, z: 0, w: 0)
}
