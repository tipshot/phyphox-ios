//
//  PhyphoxElementHandler.swift
//  phyphox
//
//  Created by Jonas Gessner on 11.04.18.
//  Copyright © 2018 RWTH Aachen. All rights reserved.
//

import Foundation

private extension SensorDescriptor {
    func buffer(for component: String, from buffers: [String: DataBuffer]) -> DataBuffer? {
        return (outputs.first(where: { $0.component == component })?.bufferName).map { buffers[$0] } ?? nil
    }
}

private extension ExperimentSensorInput {
    convenience init(descriptor: SensorInputDescriptor, buffers: [String: DataBuffer]) {
        let xBuffer = descriptor.buffer(for: "x", from: buffers)
        let yBuffer = descriptor.buffer(for: "y", from: buffers)
        let zBuffer = descriptor.buffer(for: "z", from: buffers)
        let tBuffer = descriptor.buffer(for: "t", from: buffers)
        let absBuffer = descriptor.buffer(for: "abs", from: buffers)
        let accuracyBuffer = descriptor.buffer(for: "accuracy", from: buffers)

        self.init(sensorType: descriptor.sensor, calibrated: true, motionSession: MotionSession.sharedSession(), rate: descriptor.rate, average: descriptor.average, xBuffer: xBuffer, yBuffer: yBuffer, zBuffer: zBuffer, tBuffer: tBuffer, absBuffer: absBuffer, accuracyBuffer: accuracyBuffer)
    }
}

private extension ExperimentGPSInput {
    convenience init(descriptor: LocationInputDescriptor, buffers: [String: DataBuffer]) {
        let latBuffer = descriptor.buffer(for: "lat", from: buffers)
        let lonBuffer = descriptor.buffer(for: "lon", from: buffers)
        let zBuffer = descriptor.buffer(for: "z", from: buffers)
        let vBuffer = descriptor.buffer(for: "v", from: buffers)
        let dirBuffer = descriptor.buffer(for: "dir", from: buffers)
        let accuracyBuffer = descriptor.buffer(for: "accuracy", from: buffers)
        let zAccuracyBuffer = descriptor.buffer(for: "zAccuracy", from: buffers)
        let tBuffer = descriptor.buffer(for: "t", from: buffers)
        let statusBuffer = descriptor.buffer(for: "status", from: buffers)
        let satellitesBuffer = descriptor.buffer(for: "satellites", from: buffers)

        self.init(latBuffer: latBuffer, lonBuffer: lonBuffer, zBuffer: zBuffer, vBuffer: vBuffer, dirBuffer: dirBuffer, accuracyBuffer: accuracyBuffer, zAccuracyBuffer: zAccuracyBuffer, tBuffer: tBuffer, statusBuffer: statusBuffer, satellitesBuffer: satellitesBuffer)
    }
}

private extension ExperimentAudioInput {
    convenience init(descriptor: AudioInputDescriptor, buffers: [String: DataBuffer]) throws {
        guard let outBuffer = descriptor.buffer(for: "output", from: buffers) else {
            throw ParseError.missingAttribute("output")
        }

        let sampleRateBuffer = descriptor.buffer(for: "rate", from: buffers)

        self.init(sampleRate: descriptor.rate, outBuffer: outBuffer, sampleRateInfoBuffer: sampleRateBuffer)
    }
}

final class PhyphoxElementHandler: ResultElementHandler, LookupElementHandler {
    typealias Result = Experiment
    
    var results = [Result]()

    var handlers: [String: ElementHandler]

    private let titleHandler = TextElementHandler()
    private let categoryHandler = TextElementHandler()
    private let descriptionHandler = MultilineTextHandler()
    private let iconHandler = IconHandler()
    private let linkHandler = LinkHandler()
    private let dataContainersHandler = DataContainersHandler()
    private let translationsHandler = TranslationsHandler()
    private let inputHandler = InputHandler()
    private let outputHandler = OutputHandler()
    private let analysisHandler = AnalysisHandler()
    private let viewsHandler = ViewsHandler()
    private let exportHandler = ExportHandler()

    init() {
        handlers = ["title": titleHandler, "category": categoryHandler, "description": descriptionHandler, "icon": iconHandler, "link": linkHandler, "data-containers": dataContainersHandler, "translations": translationsHandler, "input": inputHandler, "output": outputHandler, "analysis": analysisHandler, "views": viewsHandler, "export": exportHandler]
    }

    func beginElement(attributes: [String : String]) throws {
    }

    func endElement(with text: String, attributes: [String: String]) throws {
        let locale = attributes["locale"] ?? "en"
        guard let version = attributes["version"] else {
            throw ParseError.missingAttribute("version")
        }

        let title = try titleHandler.expectSingleResult()
        let category = try categoryHandler.expectSingleResult()
        let description = try descriptionHandler.expectSingleResult()

        let icon = try iconHandler.expectOptionalResult() ?? ExperimentIcon(string: title, image: nil)
        let translations = try translationsHandler.expectOptionalResult()

        let links = linkHandler.results

        let dataContainersDescriptor = try dataContainersHandler.expectSingleResult()
        let analysisDescriptor = try analysisHandler.expectOptionalResult()

        let analysisInputBufferNames = analysisDescriptor.map { getInputBufferNames(from: $0) } ?? []

        let experimentPersistentStorageURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)

        let buffers = try makeBuffers(from: dataContainersDescriptor, analysisInputBufferNames: analysisInputBufferNames, experimentPersistentStorageURL: experimentPersistentStorageURL)

        let analysis = try analysisDescriptor.map { descriptor -> ExperimentAnalysis in
            let analysisModules = try descriptor.modules.map({ try ExperimentAnalysisFactory.analysisModule(from: $1, for: $0, buffers: buffers) })

            return ExperimentAnalysis(modules: analysisModules, sleep: descriptor.sleep, dynamicSleep: descriptor.dynamicSleepName.map { buffers[$0] } ?? nil)
        }

        let inputDescriptor = try inputHandler.expectOptionalResult()
        let outputDescriptor = try outputHandler.expectOptionalResult()

        let output = try makeOutput(from: outputDescriptor, buffers: buffers)

        let sensorInputs = inputDescriptor?.sensors.map { ExperimentSensorInput(descriptor: $0, buffers: buffers) } ?? []
        let gpsInputs = inputDescriptor?.location.map { ExperimentGPSInput(descriptor: $0, buffers: buffers) } ?? []
        let audioInputs = try inputDescriptor?.audio.map { try ExperimentAudioInput(descriptor: $0, buffers: buffers) } ?? []

        let exportDescriptor = try exportHandler.expectSingleResult()
        let export = try makeExport(from: exportDescriptor, buffers: buffers, translations: translations)

        let viewCollectionDescriptors = try viewsHandler.expectOptionalResult()

        let viewDescriptors = try viewCollectionDescriptors?.map { ExperimentViewCollectionDescriptor(label: $0.label, translation: translations, views: try $0.views.map { try makeViewDescriptor(from: $0, buffers: buffers, translations: translations) })  }

        let experiment = Experiment(title: title, description: description, links: links, category: category, icon: icon, local: true, persistentStorageURL: experimentPersistentStorageURL, translation: translations, buffers: buffers, sensorInputs: sensorInputs, gpsInputs: gpsInputs, audioInputs: audioInputs, output: output, viewDescriptors: viewDescriptors, analysis: analysis, export: export)

        results.append(experiment)
    }

    private func makeViewDescriptor(from descriptor: ViewElementDescriptor, buffers: [String: DataBuffer], translations: ExperimentTranslationCollection?) throws -> ViewDescriptor {
        if let descriptor = descriptor as? SeparatorViewElementDescriptor {
            let color = try descriptor.color.map({ string -> UIColor in
                guard let color = UIColor(hexString: string) else {
                    throw ParseError.unreadableData
                }

                return color
            }) ?? kBackgroundColor

            return SeparatorViewDescriptor(height: descriptor.height, color: color)
        }
        else if let descriptor = descriptor as? InfoViewElementDescriptor {
            return InfoViewDescriptor(label: descriptor.label, translation: translations)
        }
        else if let descriptor = descriptor as? ValueViewElementDescriptor {
            guard let buffer = buffers[descriptor.inputBufferName] else {
                throw ParseError.missingElement
            }

            return ValueViewDescriptor(label: descriptor.label, translation: translations, size: descriptor.size, scientific: descriptor.scientific, precision: descriptor.precision, unit: descriptor.unit, factor: descriptor.factor, buffer: buffer, mappings: descriptor.mappings)
        }
        else if let descriptor = descriptor as? EditViewElementDescriptor {
            guard let buffer = buffers[descriptor.outputBufferName] else {
                throw ParseError.missingElement
            }

            if buffer.isEmpty {
                buffer.append(descriptor.defaultValue)
            }

            return EditViewDescriptor(label: descriptor.label, translation: translations, signed: descriptor.signed, decimal: descriptor.decimal, unit: descriptor.unit, factor: descriptor.factor, min: descriptor.min, max: descriptor.max, defaultValue: descriptor.defaultValue, buffer: buffer)
        }
        else if let descriptor = descriptor as? ButtonViewElementDescriptor {
            let dataFlow = try descriptor.dataFlow.map { flow -> (ExperimentAnalysisDataIO, DataBuffer) in
                guard let outputBuffer = buffers[flow.outputBufferName] else {
                    throw ParseError.missingElement
                }

                let input: ExperimentAnalysisDataIO

                switch flow.input {
                case .buffer(let bufferName):
                    guard let buffer = buffers[bufferName] else {
                        throw ParseError.missingElement
                    }

                    input = .buffer(buffer: buffer, usedAs: "", clear: true)
                case .value(let value):
                    input = .value(value: value, usedAs: "")
                case .clear:
                    input = .buffer(buffer: emptyBuffer, usedAs: "", clear: true)
                }

                return (input, outputBuffer)
            }

            return ButtonViewDescriptor(label: descriptor.label, translation: translations, dataFlow: dataFlow)
        }
        else if let descriptor = descriptor as? GraphViewElementDescriptor {
            let xBuffer = try descriptor.xInputBufferName.map({ name -> DataBuffer in
                guard let buffer = buffers[name] else {
                    throw ParseError.missingElement
                }
                return buffer
            })

            guard let yBuffer = buffers[descriptor.yInputBufferName] else {
                throw ParseError.missingElement
            }

            let color = try descriptor.color.map({ string -> UIColor in
                guard let color = UIColor(hexString: string) else {
                    throw ParseError.unreadableData
                }

                return color
            }) ?? kHighlightColor

            return GraphViewDescriptor(label: descriptor.label, translation: translations, xLabel: descriptor.xLabel, yLabel: descriptor.yLabel, xInputBuffer: xBuffer, yInputBuffer: yBuffer, logX: descriptor.logX, logY: descriptor.logY, xPrecision: descriptor.xPrecision, yPrecision: descriptor.yPrecision, scaleMinX: descriptor.scaleMinX, scaleMaxX: descriptor.scaleMaxX, scaleMinY: descriptor.scaleMinY, scaleMaxY: descriptor.scaleMaxY, minX: descriptor.minX, maxX: descriptor.maxX, minY: descriptor.minY, maxY: descriptor.maxY, aspectRatio: descriptor.aspectRatio, drawDots: descriptor.drawDots, partialUpdate: descriptor.partialUpdate, history: descriptor.history, lineWidth: descriptor.lineWidth, color: color)
        }
        else {
            throw ParseError.unexpectedElement
        }
    }

    private func makeOutput(from descriptor: AudioOutputDescriptor?, buffers: [String: DataBuffer]) throws -> ExperimentOutput? {
        guard let descriptor = descriptor else {
            return nil
        }

        guard let buffer = buffers[descriptor.inputBufferName] else {
            throw ParseError.missingElement
        }

        return ExperimentOutput(audioOutput: ExperimentAudioOutput(sampleRate: descriptor.rate, loop: descriptor.loop, dataSource: buffer))
    }

    private func makeExport(from descriptors: [ExportSetDescriptor], buffers: [String: DataBuffer], translations: ExperimentTranslationCollection?) throws -> ExperimentExport {
        let sets = try descriptors.map { descriptor -> ExperimentExportSet in
            let dataSets = try descriptor.dataSets.map { set -> (String, DataBuffer) in
                guard let buffer = buffers[set.bufferName] else {
                    throw ParseError.missingElement
                }

                return (descriptor.name, buffer)
            }

            return ExperimentExportSet(name: descriptor.name, data: dataSets, translation: translations)
        }

        return ExperimentExport(sets: sets)
    }

    private func makeBuffers(from descriptors: [BufferDescriptor], analysisInputBufferNames: Set<String>, experimentPersistentStorageURL: URL) throws -> [String: DataBuffer] {
        var buffers: [String: DataBuffer] = [:]

        for descriptor in descriptors {
            let storageType: DataBuffer.StorageType

            let bufferSize = descriptor.size
            let name = descriptor.name
            let staticBuffer = descriptor.staticBuffer
            let baseContents = descriptor.baseContents

            if bufferSize == 0 && !analysisInputBufferNames.contains(name) {
                let bufferURL = experimentPersistentStorageURL.appendingPathComponent(name).appendingPathExtension(bufferContentsFileExtension)

                storageType = .hybrid(memorySize: 5000, persistentStorageLocation: bufferURL)
            }
            else {
                storageType = .memory(size: bufferSize)
            }

            let buffer = try DataBuffer(name: name, storage: storageType, baseContents: baseContents, static: staticBuffer)

            buffers[name] = buffer

        }

        return buffers
    }

    private func getInputBufferNames(from analysis: AnalysisDescriptor) -> Set<String> {
        let inputBufferNames = analysis.modules.flatMap({ $0.descriptor.inputs }).compactMap({ descriptor -> String? in
            switch descriptor {
            case .buffer(name: let name, usedAs: _, clear: _):
                return name
            case .value(value: _, usedAs: _):
                return nil
            case .empty:
                return nil
            }
        })

        return Set(inputBufferNames)
    }
}
