//
//  SinAnalysis.swift
//  phyphox
//
//  Created by Jonas Gessner on 06.12.15.
//  Copyright © 2015 RWTH Aachen. All rights reserved.
//

import Foundation

final class SinAnalysis: ExperimentAnalysisModule {
    
    override func update() {
        var iterator: IndexingGenerator<Array<Double>>? = nil
        var lastValue: Double = 0.0
        
        //Get value or iterator
        if let val = inputs.first!.value  {
            lastValue = val
        }
        else {
            //iterator
            iterator = inputs.first!.buffer!.generate()
        }
        
        let outBuffer = outputs.first!.buffer!
        
        outBuffer.clear()
        
        if (iterator == nil) {
            outBuffer.append(sin(lastValue))
        }
        else {
            while let next = iterator!.next() { //For each output value or at least once for values
                outBuffer.append(sin(next))
            }
        }
    }
}
