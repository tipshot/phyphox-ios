//
//  InputElementHandler.swift
//  phyphox
//
//  Created by Jonas Gessner on 11.04.18.
//  Copyright © 2018 RWTH Aachen. All rights reserved.
//

import Foundation
import CoreBluetooth

// This file contains element handlers for the `input` child element (and its child elements) of the `phyphox` root element.

struct SensorOutputDescriptor {
    let component: String?
    let bufferName: String
}

protocol SensorDescriptor {
    var outputs: [SensorOutputDescriptor] { get }
}

private final class SensorOutputElementHandler: ResultElementHandler, ChildlessElementHandler {
    var results = [SensorOutputDescriptor]()

    func startElement(attributes: AttributeContainer) throws {}

    private enum Attribute: String, AttributeKey {
        case component
    }

    func endElement(text: String, attributes: AttributeContainer) throws {
        guard !text.isEmpty else { throw ElementHandlerError.missingText }

        let attributes = attributes.attributes(keyedBy: Attribute.self)

        let component = attributes.optionalString(for: .component) ?? "output"
        results.append(SensorOutputDescriptor(component: component, bufferName: text))
    }

    func clear() {
        results.removeAll()
    }
}

struct LocationInputDescriptor: SensorDescriptor {
    let outputs: [SensorOutputDescriptor]
}

private final class LocationElementHandler: ResultElementHandler, LookupElementHandler {
    var results = [LocationInputDescriptor]()

    private let outputHandler = SensorOutputElementHandler()

    var childHandlers: [String : ElementHandler]

    init() {
        childHandlers = ["output": outputHandler]
    }

    func startElement(attributes: AttributeContainer) throws {}

    func endElement(text: String, attributes: AttributeContainer) throws {
        results.append(LocationInputDescriptor(outputs: outputHandler.results))
    }
}

struct SensorInputDescriptor: SensorDescriptor {
    let sensor: SensorType
    let rate: Double
    let average: Bool

    let outputs: [SensorOutputDescriptor]
}

private final class SensorElementHandler: ResultElementHandler, LookupElementHandler {
    var results = [SensorInputDescriptor]()

    private let outputHandler = SensorOutputElementHandler()

    var childHandlers: [String : ElementHandler]

    init() {
        childHandlers = ["output": outputHandler]
    }

    func startElement(attributes: AttributeContainer) throws {}

    private enum Attribute: String, AttributeKey {
        case type
        case rate
        case average
    }

    func endElement(text: String, attributes: AttributeContainer) throws {
        let attributes = attributes.attributes(keyedBy: Attribute.self)

        let sensor: SensorType = try attributes.value(for: .type)

        let frequency = try attributes.optionalValue(for: .rate) ?? 0.0
        let average = try attributes.optionalValue(for: .average) ?? false

        let rate = frequency.isNormal ? 1.0/frequency : 0.0

        if average && rate == 0.0 {
            throw ElementHandlerError.message("Averaging is enabled but rate is 0")
        }

        results.append(SensorInputDescriptor(sensor: sensor, rate: rate, average: average, outputs: outputHandler.results))
    }
}

struct AudioInputDescriptor: SensorDescriptor {
    let rate: UInt
    let outputs: [SensorOutputDescriptor]
}

private final class AudioElementHandler: ResultElementHandler, LookupElementHandler {
    var results = [AudioInputDescriptor]()

    private let outputHandler = SensorOutputElementHandler()

    var childHandlers: [String : ElementHandler]

    init() {
        childHandlers = ["output": outputHandler]
    }

    func startElement(attributes: AttributeContainer) throws {}

    private enum Attribute: String, AttributeKey {
        case rate
    }

    func endElement(text: String, attributes: AttributeContainer) throws {
        let attributes = attributes.attributes(keyedBy: Attribute.self)

        let rate: UInt = try attributes.optionalValue(for: .rate) ?? 48000

        results.append(AudioInputDescriptor(rate: rate, outputs: outputHandler.results))
    }
}

enum BluetoothOutputExtra: String, LosslessStringConvertible {
    case time
    case none
}

struct BluetoothOutputDescriptor {
    let char: CBUUID
    let conversion: InputConversion?
    let bufferName: String
    let extra: BluetoothOutputExtra
}

private final class BluetoothOutputElementHandler: ResultElementHandler, ChildlessElementHandler {
    var results = [BluetoothOutputDescriptor]()
    
    func startElement(attributes: AttributeContainer) throws {}
    
    private enum Attribute: String, AttributeKey {
        case char
        case extra
        case conversion
        case offset
        case length
        case decimalPoint
        case separator
        case label
        case index
    }
    
    func endElement(text: String, attributes: AttributeContainer) throws {
        guard !text.isEmpty else { throw ElementHandlerError.missingText }
        
        let attributes = attributes.attributes(keyedBy: Attribute.self)
        
        let uuidString: String = try attributes.nonEmptyString(for: .char)
        let uuid = try CBUUID(uuidString: uuidString)
        
        let extra: BluetoothOutputExtra = try attributes.optionalValue(for: .extra) ?? .none
        
        let conversion: InputConversion?
        
        if extra == .none {
            let conversionName = try attributes.nonEmptyString(for: .conversion)
            
            switch conversionName {
            case "string":
                let decimalPoint: String? = attributes.optionalString(for: .decimalPoint)
                let offset: Int = try attributes.optionalValue(for: .offset) ?? 0
                let length: Int? = try attributes.optionalValue(for: .length)
                conversion = StringInputConversion(decimalPoint: decimalPoint, offset: offset, length: length)
            case "formattedString":
                let separator: String? = attributes.optionalString(for: .separator)
                let label: String? = attributes.optionalString(for: .label)
                let index: Int = try attributes.optionalValue(for: .index) ?? 0
                conversion = FormattedStringInputConversion(separator: separator, label: label, index: index)
            case "singleByte":
                let offset: Int = try attributes.optionalValue(for: .offset) ?? 0
                let length: Int? = try attributes.optionalValue(for: .length)
                conversion = SimpleInputConversion(function: .uInt8, offset: offset, length: length)
            default:
                let conversionFunction: SimpleInputConversion.ConversionFunction = try attributes.value(for: .conversion)
                let offset: Int = try attributes.optionalValue(for: .offset) ?? 0
                let length: Int? = try attributes.optionalValue(for: .length)
                conversion = SimpleInputConversion(function: conversionFunction, offset: offset, length: length)
            }
        } else {
            conversion = nil
        }
        
        results.append(BluetoothOutputDescriptor(char: uuid, conversion: conversion, bufferName: text, extra: extra))
    }
    
    func clear() {
        results.removeAll()
    }
}

struct BluetoothConfigDescriptor {
    let char: CBUUID
    let data: Data
}

final class BluetoothConfigElementHandler: ResultElementHandler, ChildlessElementHandler {
    var results = [BluetoothConfigDescriptor]()
    
    func startElement(attributes: AttributeContainer) throws {}
    
    private enum Attribute: String, AttributeKey {
        case char
        case conversion
    }
    
    func endElement(text: String, attributes: AttributeContainer) throws {
        guard !text.isEmpty else { throw ElementHandlerError.missingText }
        
        let attributes = attributes.attributes(keyedBy: Attribute.self)
        
        let uuidString: String = try attributes.nonEmptyString(for: .char)
        let uuid = try CBUUID(uuidString: uuidString)
        
        let conversionName = try attributes.nonEmptyString(for: .conversion)
        let conversion: ConfigConversion
        switch conversionName {
        case "singleByte":
            conversion = SimpleConfigConversion(function: .uInt8)
        default:
            let conversionFunction: SimpleConfigConversion.ConversionFunction = try attributes.value(for: .conversion)
            conversion = SimpleConfigConversion(function: conversionFunction)
        }
        
        results.append(BluetoothConfigDescriptor(char: uuid, data: conversion.convert(data: text)))
    }
    
    func clear() {
        results.removeAll()
    }
}

enum BluetoothMode: String, LosslessStringConvertible {
    case notification
    case indication
    case poll
}

struct BluetoothInputBlockDescriptor {
    let id: String?
    let name: String?
    let uuid: CBUUID?
    let mode: BluetoothMode
    let rate: Double?
    let subscribeOnStart: Bool
    let autoConnect: Bool
    let outputs: [BluetoothOutputDescriptor]
    let configs: [BluetoothConfigDescriptor]
}

private final class BluetoothElementHandler: ResultElementHandler, LookupElementHandler {
    var results = [BluetoothInputBlockDescriptor]()
    
    private let outputHandler = BluetoothOutputElementHandler()
    private let configHandler = BluetoothConfigElementHandler()
    
    var childHandlers: [String : ElementHandler]
    
    init() {
        childHandlers = ["output": outputHandler, "config": configHandler]
    }
    
    func startElement(attributes: AttributeContainer) throws {}
    
    private enum Attribute: String, AttributeKey {
        case id
        case name
        case uuid
        case mode
        case subscribeOnStart
        case rate
        case autoConnect
    }
    
    func endElement(text: String, attributes: AttributeContainer) throws {
        let attributes = attributes.attributes(keyedBy: Attribute.self)
        
        let id: String? = attributes.optionalString(for: .id)
        let name: String? = attributes.optionalString(for: .name)
        let uuidString: String? = attributes.optionalString(for: .uuid)
        let uuid: CBUUID?
        if let uuidString = uuidString {
            uuid = try CBUUID(uuidString: uuidString)
        } else {
            uuid = nil
        }
        let mode: BluetoothMode = try attributes.value(for: .mode)
        let subscribeOnStart: Bool = try attributes.optionalValue(for: .subscribeOnStart) ?? false
        let autoConnect: Bool = try attributes.optionalValue(for: .autoConnect) ?? false
        let rate: Double? = try attributes.optionalValue(for: .rate)
        
        guard mode != .poll || (rate != nil && rate!.isFinite && rate! > 0) else {
            throw ElementHandlerError.message("For poll mode, a finite rate > 0 is required.")
        }
        
        results.append(BluetoothInputBlockDescriptor(id: id, name: name, uuid: uuid, mode: mode, rate: rate, subscribeOnStart: subscribeOnStart, autoConnect: autoConnect, outputs: outputHandler.results, configs: configHandler.results))
    }
}

final class InputElementHandler: ResultElementHandler, LookupElementHandler, AttributelessElementHandler {
    typealias Result = (sensors: [SensorInputDescriptor], audio: [AudioInputDescriptor], location: [LocationInputDescriptor], bluetooth: [BluetoothInputBlockDescriptor])

    var results = [Result]()

    private let sensorHandler = SensorElementHandler()
    private let audioHandler = AudioElementHandler()
    private let locationHandler = LocationElementHandler()
    private let bluetoothHandler = BluetoothElementHandler()

    var childHandlers: [String: ElementHandler]

    init() {
        childHandlers = ["sensor": sensorHandler, "audio": audioHandler, "location": locationHandler, "bluetooth": bluetoothHandler]
    }

    func endElement(text: String, attributes: AttributeContainer) throws {
        let audio = audioHandler.results
        let location = locationHandler.results
        let sensors = sensorHandler.results
        let bluetooth = bluetoothHandler.results

        results.append((sensors, audio, location, bluetooth))
    }
}


