//
//  ExperimentCollection.swift
//  phyphox
//
//  Created by Jonas Gessner on 04.12.15.
//  Copyright © 2015 Jonas Gessner. All rights reserved.
//  By Order of RWTH Aachen.
//

import Foundation

final class ExperimentCollection {
    private(set) var title: String
    var experiments: [(experiment: Experiment, custom: Bool)]
    
    init(title: String, experiments: [Experiment], customExperiments: Bool) {
        self.title = title
        self.experiments = experiments.map { ($0, customExperiments) }
    }
}