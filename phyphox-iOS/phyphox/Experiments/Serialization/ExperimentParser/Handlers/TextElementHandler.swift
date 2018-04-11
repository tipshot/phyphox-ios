//
//  TextElementHandler.swift
//  phyphox
//
//  Created by Jonas Gessner on 11.04.18.
//  Copyright © 2018 RWTH Aachen. All rights reserved.
//

import Foundation

final class TextElementHandler: AttributeLessResultHandler, ChildLessResultHandler {
    typealias Result = String

    private(set) var results = [Result]()

    func endElement(with text: String) throws {
        guard !text.isEmpty else { throw ParseError.missingText }

        results.append(text)
    }
}