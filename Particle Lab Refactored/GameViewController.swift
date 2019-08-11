//
//  GameViewController.swift
//  Particle Lab Refactored
//
//  Created by Caleb on 12/29/17.
//  Copyright © 2017 Caleb. All rights reserved.
//

import UIKit
import MetalKit

// This class controls the simulation as well as the UI to configure it
class GameViewController: UIViewController {

    //Basic UI For the app to change modes
    let menuButton = UIButton()
    let statusLabel = UILabel()
    let segmentedLabel = UISegmentedControl(items: ["None", "Glow", "Cloud"])
    let button = UIButton()
    let slider = UISlider()
    let label = UILabel()
    
    //The parts of the simulation
    var renderer: ParticleRenderer!
    var mtkView: MTKView!
    
    let floatPi = Float(Double.pi)
    
    //Moves the wells
    var gravityWellAngle:Float = 0
    
    //All of the touches
    var currentTouches = Set<UITouch>()
    
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        //let dev = MTLCreateSystemDefaultDevice()!
        /*let tex = Builder.Textures.ofResolution(width: 99, height: 99, device: dev, usage: .renderTarget)!
        let gauss = BlurCompositon(data: [CompositionPart(weight: 1.0, instruction: [1], level: 0.4)])
        gauss.prepare(device: dev, width: 900, height: 900)
        gauss.prepareToDraw(source: tex)
        let gauss2 = BlurCompositon(data: [CompositionPart(weight: 1.0, instruction: [1, 2], level: 0.4)])
        gauss2.prepare(device: dev, width: 900, height: 900)
        gauss2.prepareToDraw(source: tex)
        let gauss3 = BlurCompositon(data: [CompositionPart(weight: 1.0, instruction: [1, 2, 3], level: 0.3)])
        gauss3.prepare(device: dev, width: 900, height: 900)
        gauss3.prepareToDraw(source: tex)
        let gauss4 = BlurCompositon(data: [CompositionPart(weight: 1.0, instruction: [1, 2], level: 1.0),
                                           CompositionPart(weight: 0.9, instruction: [1, 4, 5], level: 1.0),
                                           CompositionPart(weight: 0.8, instruction: [3], level: 1.0),
                                           CompositionPart(weight: 0.7, instruction: [3], level: 1.0),
                                           CompositionPart(weight: 0.6, instruction: [1, 4, 6, 7], level: 1.0),
                                           CompositionPart(weight: 0.5, instruction: [1, 3], level: 1.0),
                                           CompositionPart(weight: 0.4, instruction: [2], level: 1.0),
                                           CompositionPart(weight: 0.3, instruction: [1, 4, 6, 7], level: 1.0)])
        gauss4.prepare(device: dev, width: 900, height: 900)
        gauss4.prepareToDraw(source: tex)
        let gauss5 = BlurCompositon(data: [CompositionPart(weight: 1.0, instruction: [1, 2], level: 1.0),
                                           CompositionPart(weight: 0.9, instruction: [1, 3], level: 1.0),
                                           CompositionPart(weight: 0.8, instruction: [2, 4], level: 0.5),
                                           CompositionPart(weight: 0.7, instruction: [2, 1, 2, 3, 4], level: 0.5)])
        gauss5.prepare(device: dev, width: 900, height: 900)
        gauss5.prepareToDraw(source: tex)
        let gauss6 = BlurCompositon(data: [CompositionPart(weight: 1.0, instruction: [2], level: 1.0),
                                           CompositionPart(weight: 0.9, instruction: [3], level: 1.0),
                                           CompositionPart(weight: 0.8, instruction: [4], level: 0.5),
                                           CompositionPart(weight: 0.7, instruction: [1, 2, 3, 4], level: 0.5)])
        gauss6.prepare(device: dev, width: 900, height: 900)
        gauss6.prepareToDraw(source: tex)*/
        //let blur1 = BlurCompositon(data: )
        print("HERE")
        initializeSimulationandMetal()
        initializeUI()
        prepareForMode(mode: DemoModes.multiTouch)
        Settings.demoMode = DemoModes.multiTouch
    }
    
    //The metal holds device the renderer and a MTK View
    func initializeSimulationandMetal() {
        //Grab a metal kit view which handles renderables and other cool things
        if let tempView = view as? MTKView {
            mtkView = tempView
        } else {fatalError("Couldnt cast to a MTKView Metal may not be supported on this device")}
        mtkView.backgroundColor = UIColor.black
        mtkView.framebufferOnly = false //Since we will be writing directly to the screens texture (rather than rendering triangles) we need this
        mtkView.depthStencilPixelFormat = MTLPixelFormat.depth32Float_stencil8
        mtkView.colorPixelFormat = MTLPixelFormat.bgra8Unorm
        mtkView.sampleCount = 1
        
        //Get an object representing the GPU
        if let device = MTLCreateSystemDefaultDevice() {
            mtkView.device = device
        } else {fatalError("Couldnt get a GPU representation as a device metal may not be supported")}
        
        //This will render the particles for us
        if let newRenderer = ParticleRenderer(view: mtkView, viewController: self) {
            renderer = newRenderer
        } else {fatalError("Couldnt initialize the renderer")}
        
        view.isMultipleTouchEnabled = true
        
        //This callback is required of MTKViewDelegates we will call it now to alert it of a size change
        renderer.mtkView(mtkView, drawableSizeWillChange: mtkView.drawableSize)
        
        //The delegate can draw on a view and change size
        mtkView.delegate = renderer
    }
    
    //The UI allows us to switch the mode
    func initializeUI() {
        //The menu button that opens up the options for the simulations
        menuButton.layer.borderColor = UIColor.lightGray.cgColor
        menuButton.layer.borderWidth = 1
        menuButton.layer.cornerRadius = 5
        menuButton.layer.backgroundColor = UIColor.darkGray.cgColor
        menuButton.showsTouchWhenHighlighted = true
        menuButton.imageView?.contentMode = UIViewContentMode.scaleAspectFit
        menuButton.setImage(UIImage(named: "hamburger.png"), for: UIControlState.normal)
        menuButton.addTarget(self, action: #selector(menuPress), for: UIControlEvents.touchDown)
        //view.addSubview(menuButton)
        
        //Will display the status of the simulation
        statusLabel.text = "Based on a project by Flexmonkey"
        statusLabel.textColor = UIColor.darkGray
        //view.addSubview(statusLabel)
        
        //Will display visual options
        segmentedLabel.selectedSegmentIndex = 0
        Settings.render = .Regular
        segmentedLabel.addTarget(self, action: #selector(visualPress), for: UIControlEvents.valueChanged)
        view.addSubview(segmentedLabel)
        
        label.text = "Particle Count"
        label.textColor = UIColor.darkGray
        //view.addSubview(label)
        
        slider.minimumValue = 0
        slider.maximumValue = 1
        slider.value = 0.3
        
        
        
        view.addSubview(slider)
        
    }
    @objc func resetPress() {
        renderer.resetParticles()
    }
    //viewDidLayoutSubviews is called when the view is done being set up so we now can
    //calculate where to put the buttons
    override func viewDidLayoutSubviews() {
        statusLabel.frame = CGRect(x: 5,
                                   y: view.frame.height - statusLabel.intrinsicContentSize.height,
                                   width: view.frame.width,
                                   height: statusLabel.intrinsicContentSize.height)
        
        menuButton.frame = CGRect(x: view.frame.width - 35,
                                  y: view.frame.height - 35,
                                  width: 30,
                                  height: 30)
        
        var verticalMove:CGFloat = 0
        verticalMove += 10
        segmentedLabel.center.x += 20
        if !UIApplication.shared.isStatusBarHidden {
            verticalMove += UIApplication.shared.statusBarFrame.height
        }
        segmentedLabel.center.y += verticalMove
        
        label.frame.size.width = label.intrinsicContentSize.width
        label.frame.size.height = label.intrinsicContentSize.height
        slider.frame.size.width = max(segmentedLabel.frame.size.width, label.intrinsicContentSize.width)
        slider.center.x = view.frame.width - (slider.frame.size.width / 2) - 10
        label.center.x = slider.center.x
        label.center.y = verticalMove + (label.intrinsicContentSize.height / 2)
        slider.center.y = label.center.y + (label.intrinsicContentSize.height / 2) + 8 + (slider.frame.size.height / 2)
        
        button.frame = CGRect(x: view.frame.size.width / 2,
                                   y: button.intrinsicContentSize.height / 2,
                                   width: button.intrinsicContentSize.width,
                                   height: button.intrinsicContentSize.height)
        button.center.x = view.frame.size.width / 2
        button.center.y = segmentedLabel.center.y
        
        slider.center.y = segmentedLabel.center.y
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        currentTouches = currentTouches.union(touches)
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        currentTouches = currentTouches.union(touches)
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        currentTouches = currentTouches.subtracting(touches)
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        currentTouches = currentTouches.subtracting(touches)
    }
    @objc func visualPress() {
        switch segmentedLabel.selectedSegmentIndex {
        case 0:
            Settings.render = .Regular
        case 1:
            Settings.render = .Glow
        case 2:
            Settings.render = .Cloud
        default:
            Settings.render = .Regular
        }
    }
    
    //Called when the menu is presssed
    //We use a UIAlertController to display the options for modes
    @objc func menuPress() {
        let alertController = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        
        let def = UIAlertActionStyle.default
        let cloudChamberAction = UIAlertAction(title: DemoModes.cloudChamber.rawValue, style: def, handler: calloutActionHandler)
        let orbitsAction = UIAlertAction(title: DemoModes.orbits.rawValue, style: def, handler: calloutActionHandler)
        let multiTouchAction = UIAlertAction(title: DemoModes.multiTouch.rawValue, style: def, handler: calloutActionHandler)
        let cancel = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
        
        alertController.addAction(cloudChamberAction)
        alertController.addAction(orbitsAction)
        alertController.addAction(multiTouchAction)
        alertController.addAction(cancel)
        
        let xx = menuButton.frame.origin.x
        let yy = menuButton.frame.origin.y
        alertController.popoverPresentationController?.sourceRect = CGRect(x: xx, y: yy, width: menuButton.frame.width, height: menuButton.frame.height)
        alertController.popoverPresentationController?.sourceView = view
        
        mtkView.isPaused = true
        
        present(alertController, animated: true, completion: {self.mtkView.isPaused = false})
    }
    
    //This is called when someone presses a menu option and we need to react to it
    func calloutActionHandler(value: UIAlertAction!) -> Void
    {
        Settings.demoMode = DemoModes(rawValue: value.title!)!
        
        prepareForMode(mode: Settings.demoMode)
    }
    func prepareForMode(mode: DemoModes) {
        Settings.demoMode = mode
        switch mode
        {
        case .orbits:
            Settings.dragFactor = 0.82
            Settings.respawnOutOfBoundsParticles = true
            //renderer.resetParticles(false)
            
        case .cloudChamber:
            Settings.dragFactor = 0.8
            Settings.respawnOutOfBoundsParticles = false
           // renderer.resetParticles(true)
            
        case .multiTouch:
            Settings.dragFactor = 0.95
            Settings.respawnOutOfBoundsParticles = true
            //renderer.resetParticles(false)
            currentTouches = Set<UITouch>()
        }
        
    }
        
    //This is called to update the display label and step the gravity wells which the view controls
    func update(status: String)
    {
        statusLabel.text = "Based on a project by Flexmonkey  |  " + status
        
        renderer.resetGravityWells()
        
        let lastValue = Settings.particleCount
        let floor:Int = 1000
        let currentValue = Int(pow(slider.value, 4) * Float(16000000 - floor)) + floor
        if (currentValue > lastValue) {
            renderer.resetParticles(start: lastValue / 4, end: currentValue / 4)
        }
        Settings.particleCount = currentValue
        
        switch Settings.demoMode
        {
        case .orbits:
            orbitsStep()
            
        case .cloudChamber:
            cloudChamberStep()
            
        case .multiTouch:
            multiTouchStep()
        }
    }
    
    func orbitsStep()
    {
        gravityWellAngle = gravityWellAngle + 0.0015
        
        renderer.setGravityWellProperties(gravityWell: .One,
                                             normalisedPositionX: 0.5 + 0.006 * cos(gravityWellAngle * 43),
                                             normalisedPositionY: 0.5 + 0.006 * sin(gravityWellAngle * 43),
                                             mass: 10, spin: 24)
        
        let part1 = renderer.getGravityWellNormalisedPosition(gravityWell: .One)
        renderer.setGravityWellProperties(gravityWell: .Two,
                                             normalisedPositionX: part1.x + 0.3 * sin(gravityWellAngle * 5),
                                             normalisedPositionY: part1.y + 0.3 * cos(gravityWellAngle * 5),
                                             mass: 4, spin: 18)
        
        let part2 = renderer.getGravityWellNormalisedPosition(gravityWell: .Two)
        renderer.setGravityWellProperties(gravityWell: .Three,
                                             normalisedPositionX: part2.x + 0.1 * cos(gravityWellAngle * 23),
                                             normalisedPositionY: part2.y + 0.1 * sin(gravityWellAngle * 23),
                                             mass: 6, spin: 17)
        
        let part3 = renderer.getGravityWellNormalisedPosition(gravityWell: .Three)
        renderer.setGravityWellProperties(gravityWell: .Four,
                                             normalisedPositionX: part3.x + 0.03 * sin(gravityWellAngle * 37),
                                             normalisedPositionY: part3.y + 0.03 * cos(gravityWellAngle * 37),
                                             mass: 8, spin: 25)
    }
    func cloudChamberStep() {
        gravityWellAngle = gravityWellAngle + 0.02
        
        renderer.setGravityWellProperties(gravityWell: .One,
                                             normalisedPositionX: 0.5 + 0.1 * sin(gravityWellAngle + floatPi * 0.5),
                                             normalisedPositionY: 0.5 + 0.1 * cos(gravityWellAngle + floatPi * 0.5),
                                             mass: 11 * sin(gravityWellAngle / 1.9), spin: 23 * cos(gravityWellAngle / 2.1))
        
        renderer.setGravityWellProperties(gravityWell: .Four,
                                             normalisedPositionX: 0.5 + 0.1 * sin(gravityWellAngle + floatPi * 1.5),
                                             normalisedPositionY: 0.5 + 0.1 * cos(gravityWellAngle + floatPi * 1.5),
                                             mass: 11 * sin(gravityWellAngle / 1.9), spin: 23 * cos(gravityWellAngle / 2.1))
        
        renderer.setGravityWellProperties(gravityWell: .Two,
                                             normalisedPositionX: 0.5 + (0.35 + sin(gravityWellAngle * 2.7)) * cos(gravityWellAngle / 1.3),
                                             normalisedPositionY: 0.5 + (0.35 + sin(gravityWellAngle * 2.7)) * sin(gravityWellAngle / 1.3),
                                             mass: 26, spin: -19 * sin(gravityWellAngle * 1.5))
        
        renderer.setGravityWellProperties(gravityWell: .Three,
                                             normalisedPositionX: 0.5 + (0.35 + sin(gravityWellAngle * 2.7)) * cos(gravityWellAngle / 1.3 + floatPi),
                                             normalisedPositionY: 0.5 + (0.35 + sin(gravityWellAngle * 2.7)) * sin(gravityWellAngle / 1.3 + floatPi),
                                             mass: 26, spin: -19 * sin(gravityWellAngle * 1.5))
    }
    func multiTouchStep() {
        let currentTouchesArray = Array(currentTouches)
        for i in 0..<currentTouchesArray.count {
            let touch = currentTouchesArray[i]
            let touchMultiplier = touch.force == 0 && touch.maximumPossibleForce == 0 ? 1 : Float(touch.force / touch.maximumPossibleForce) + 0.5
            
            var loc = touch.location(in: view)
            loc = CGPoint(x: loc.x / view.frame.width, y: loc.y / view.frame.height)
            renderer.setGravityWellProperties(gravityWellIndex: i, normalisedPositionX: Float(loc.x), normalisedPositionY: Float(loc.y), mass: 40 * touchMultiplier, spin: 20 * touchMultiplier)
        }
    }
    
    override var prefersStatusBarHidden: Bool {
        return true
    }
    
    override func prefersHomeIndicatorAutoHidden() -> Bool {
        return true
    }
}
