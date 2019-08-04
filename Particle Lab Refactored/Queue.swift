//
//  Queue.swift
//  Particle Lab Refactored
//
//  Created by Caleb on 12/31/17.
//  Copyright © 2017 Caleb. All rights reserved.
//

import Foundation

class Queue<T:Numeric & Comparable> {
    fileprivate var array:[T]
    
    init() {
        array = [T]()
    }
    func add(_ data: T) {
        array.append(data)
    }
    func remove() -> T {
        return array.removeFirst()
    }
    func sum() -> T {
        var sum:T = 0
        for data in array {
            sum += data
        }
        return sum
    }
    func count() -> Int {
        return array.count
    }
    func minimum() -> T {
        if (array.count > 0) {
            var min:T = array.first!
            for i in 1..<array.count {
                if (array[i] < min) {
                    min = array[i]
                }
            }
            return min
        }
        return -1
    }
    func maximum() -> T {
        if (array.count > 0) {
            var max:T = array.first!
            for i in 1..<array.count {
                if (array[i] > max) {
                    max = array[i]
                }
            }
            return max
        }
        return -1
    }
}
class FloatQueue:Queue<Float> {
    func standardDeviation() -> Float {
        let mean = average()
        var sum:Float = 0
        for val in array {
            sum += pow(val - mean, 2)
        }
        sum = sum / Float(array.count)
        return sqrt(sum)
    }
    func average() -> Float {
        return sum() / Float(array.count)
    }
}
