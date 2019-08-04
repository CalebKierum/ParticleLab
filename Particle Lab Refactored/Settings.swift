//
//  Settings.swift
//  ParticleLab
//
//  Created by Caleb on 12/26/17.
//  Copyright © 2017 Caleb. All rights reserved.
//

import Foundation
import UIKit

class Settings {
    //Switches between the various demos in the app
    static var demoMode:DemoModes = DemoModes.multiTouch
    
    //Sets the ammount of particles
    static var particleCount:Int = 130000 / 4
    
    //The factor that slows down the particles
    static var dragFactor:Float = 0.5
    
    //Whether to respawn particles that go out of bounds
    static var respawnOutOfBoundsParticles = false
    
    static var render:RenderMode = RenderMode.Cloud
}

