//
//  AutocorrelationAnalysis.swift
//  phyphox
//
//  Created by Jonas Gessner on 06.12.15.
//  Copyright © 2015 Jonas Gessner. All rights reserved.
//  By Order of RWTH Aachen.
//

import Foundation
import Accelerate

final class AutocorrelationAnalysis: ExperimentAnalysisModule {
    private var minXIn: ExperimentAnalysisDataIO?
    private var maxXIn: ExperimentAnalysisDataIO?
    
    private var xIn: DataBuffer?
    private var yIn: DataBuffer!
    
    private var xOut: ExperimentAnalysisDataIO?
    private var yOut: ExperimentAnalysisDataIO?
    
    override init(inputs: [ExperimentAnalysisDataIO], outputs: [ExperimentAnalysisDataIO], additionalAttributes: [String : AnyObject]?) throws {
        for input in inputs {
            if input.asString == "x" {
                xIn = input.buffer!
            }
            else if input.asString == "y" {
                yIn = input.buffer!
            }
            else if input.asString == "minX" {
                minXIn = input
            }
            else if input.asString == "maxX" {
                maxXIn = input
            }
            else {
                print("Error: Invalid analysis input: \(input.asString)")
            }
        }
        
        for output in outputs {
            if output.asString == "x" {
                xOut = output
            }
            else if output.asString == "y" {
                yOut = output
            }
            else {
                print("Error: Invalid analysis output: \(output.asString)")
            }
        }
        
        try super.init(inputs: inputs, outputs: outputs, additionalAttributes: additionalAttributes)
    }
    
    override func update() {
        var minX: Double = -Double.infinity
        var maxX: Double = Double.infinity
        
        var needsFiltering = false
        
        if let m = minXIn?.getSingleValue() {
            minX = m
            needsFiltering = true
        }
        
        if let m = maxXIn?.getSingleValue() {
            maxX = m
            needsFiltering = true
        }
        
        let y = yIn.toArray()
        var count = y.count
        
        var xValues: [Double] = []
        var yValues: [Double] = []
        
        if count > 0 {
            if xIn != nil {
                count = min(xIn!.count, count);
            }
            
            var x: [Double]!
            
            if xOut != nil {
                if xIn != nil {
                    x = [Double](count: count, repeatedValue: 0.0)
                    
                    let xRaw = xIn!.toArray()
                    
                    let first = xRaw.first
                    
                    if first == nil {
                        return
                    }
                    
                    if first! == 0.0 {
                        x = xRaw
                    }
                    else {
                        vDSP_vsaddD(xRaw, 1, [-first!], &x!, 1, vDSP_Length(count))
                    }
                }
                else {
                    x = [Double](count: count, repeatedValue: 0.0)
                    
                    vDSP_vrampD([0.0], [1.0], &x!, 1, vDSP_Length(count))
                }
            }
            
            /*
             A := [a0, ... , an]
             F := [a0, ... , an]
             
             (wanted behaviour)
             for (n = 0; n < N; ++n)
                C[n] = sum(A[n+p] * F[p], 0 <= p < N-n);
             
             <=>
             
             P := N
             A := [a0, ... , an, 0, ... , 0]
             F := [a0, ... , an]
             
             (vDSP_conv)
             for (n = 0; n < N; ++n)
                C[n] = sum(A[n+p] * F[p], 0 <= p < P);
             */
            
            var normalizeVector = [Double](count: count, repeatedValue: 0.0)
            
            let paddedY = y + normalizeVector
            
            var corrY = y
            
            vDSP_convD(paddedY, 1, paddedY, 1, &corrY, 1, vDSP_Length(count), vDSP_Length(count))
            
            
            //Normalize
            vDSP_vrampD([Double(count)], [-1.0], &normalizeVector, 1, vDSP_Length(count))
            
            var normalizedY = normalizeVector
            
            vDSP_vdivD(normalizeVector, 1, corrY, 1, &normalizedY, 1, vDSP_Length(count))
            
            
            var minimizedY = normalizedY
            
            let minimizedX: [Double]
            
            if needsFiltering {
                var index = 0
                
                minimizedX = x.filter { d -> Bool in
                    if d < minX || d > maxX {
                        if index < minimizedY.count {
                            minimizedY.removeAtIndex(index)
                        }
                        return false
                    }
                    
                    index += 1
                    
                    return true
                }
            }
            else {
                minimizedX = x
            }
            
            xValues = minimizedX
            yValues = minimizedY
        }
        
        if yOut != nil {
            if yOut!.clear {
                yOut!.buffer!.replaceValues(yValues)
            }
            else {
                yOut!.buffer!.appendFromArray(yValues)
            }
        }
        
        if xOut != nil {
            if xOut!.clear {
                xOut!.buffer!.replaceValues(xValues)
            }
            else {
                xOut!.buffer!.appendFromArray(xValues)
            }
        }
    }
}
