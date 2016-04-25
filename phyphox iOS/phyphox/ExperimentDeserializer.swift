//
//  ExperimentDeserializer.swift
//  phyphox
//
//  Created by Jonas Gessner on 04.12.15.
//  Copyright © 2015 Jonas Gessner. All rights reserved.
//  By Order of RWTH Aachen.
//


import Foundation

func getElemetArrayFromValue(value: AnyObject) -> [AnyObject] {
    var values: [AnyObject] = []
    
    if value is NSMutableArray {
        for item in (value as! NSMutableArray) {
            values.append(item)
        }
    }
    else if value is NSArray {
        values.appendContentsOf(value as! Array)
    }
    else {
        values.append(value)
    }
    
    return values
}

func getElementsWithKey(xml: NSDictionary, key: String) -> [AnyObject]? {
    let read = xml[key]
    
    if let v = read {
        return getElemetArrayFromValue(v)
    }
    
    return nil
}

final class ExperimentDeserializer: NSObject {
    private let parser: NSXMLParser
    
    init(data: NSData) {
        parser = NSXMLParser(data: data)
        super.init()
    }
    
    init(inputStream: NSInputStream) {
        parser = NSXMLParser(stream: inputStream)
        super.init()
    }
    
    func deserialize() throws -> Experiment {
        XMLDictionaryParser.sharedInstance().attributesMode = XMLDictionaryAttributesMode.Dictionary
        
        let dictionary = XMLDictionaryParser.sharedInstance().dictionaryWithParser(parser)
        
        var d = dictionary["description"]
        let description: String? = (d != nil ? textFromXML(d!) : nil)
        d = dictionary["category"]
        let category: String? = (d != nil ? textFromXML(d!) : nil)
        d = dictionary["title"]
        let title: String? = (d != nil ? textFromXML(d!) : nil)
        
        let buffersRaw = parseDataContainers(dictionary["data-containers"] as! NSDictionary?)
        
        guard let buffers = buffersRaw.0 else {
            throw SerializationError.InvalidExperimentFile
        }
        
        let translation = parseTranslations(dictionary["translations"] as! NSDictionary?)
        
        let analysis = parseAnalysis(dictionary["analysis"] as! NSDictionary?, buffers: buffers)
        
        let inputs = parseInputs(dictionary["input"] as! NSDictionary?, buffers: buffers, analysis: analysis)
        
        let sensorInputs = inputs.0
        let audioInputs = inputs.1
        
        let viewDescriptors = parseViews(dictionary["views"] as! NSDictionary?, buffers: buffers, analysis: analysis, translation: translation)
        
        let export = parseExport(dictionary["export"] as! NSDictionary?, buffers: buffers, translation: translation)
        
        let output = parseOutput(dictionary["output"] as! NSDictionary?, buffers: buffers)
        
        let iconRaw = dictionary["icon"]
        let icon = parseIcon(iconRaw ?? title ?? "")
        
        guard icon != nil && title != nil && category != nil else {
            throw SerializationError.InvalidExperimentFile
        }
        
        let experiment = Experiment(title: title!, description: description, category: category!, icon: icon!, local: true, translation: translation, buffers: buffersRaw, sensorInputs: sensorInputs, audioInputs: audioInputs, output: output, viewDescriptors: viewDescriptors, analysis: analysis, export: export)
        
        return experiment
    }
    
    func deserializeAsynchronous(completion: (experiment: Experiment?, error: SerializationError?) -> Void) {
        dispatch_async(serializationQueue) { () -> Void in
            do {
                let experiment = try self.deserialize()
                
                mainThread({
                    completion(experiment: experiment, error: nil)
                })
            }
            catch {
                mainThread({
                    completion(experiment: nil, error: error as? SerializationError)
                })
            }
        }
    }
    
    //MARK: - Parsing
    
    func parseDataContainers(dataContainers: NSDictionary?) -> ([String: DataBuffer]?, [DataBuffer]?) {
        if dataContainers != nil {
            let parser = ExperimentDataContainersParser(dataContainers!)
            
            return parser.parse()
        }
        
        return (nil, nil)
    }
    
    func parseIcon(icon: AnyObject) -> ExperimentIcon? {
        let parser = ExperimentIconParser(icon)
        
        return parser.parse()
    }
    
    func parseOutput(outputs: NSDictionary?,  buffers: [String : DataBuffer]) -> ExperimentOutput? {
        if (outputs != nil) {
            let parser = ExperimentOutputParser(outputs!)
            
            return parser.parse(buffers)
        }
        
        return nil
    }
    
    func parseExport(exports: NSDictionary?, buffers: [String : DataBuffer], translation: ExperimentTranslationCollection?) -> ExperimentExport? {
        if (exports != nil) {
            let parser = ExperimentExportParser(exports!)
            
            return parser.parse(buffers, translation: translation)
        }
        
        return nil
    }
    
    func parseInputs(inputs: NSDictionary?, buffers: [String : DataBuffer], analysis: ExperimentAnalysis?) -> ([ExperimentSensorInput]?, [ExperimentAudioInput]?) {
        if (inputs != nil) {
            let parser = ExperimentInputsParser(inputs!)
            
            return parser.parse(buffers, analysis: analysis)
        }
        
        return (nil, nil)
    }
    
    func parseViews(views: NSDictionary?, buffers: [String : DataBuffer], analysis: ExperimentAnalysis?, translation: ExperimentTranslationCollection?) -> [ExperimentViewCollectionDescriptor]? {
        if (views != nil) {
            let parser = ExperimentViewsParser(views!)
            
            return parser.parse(buffers, analysis: analysis, translation: translation)
        }
        
        return nil
    }
    
    func parseAnalysis(analysis: NSDictionary?, buffers: [String : DataBuffer]) -> ExperimentAnalysis? {
        if (analysis != nil) {
            let parser = ExperimentAnalysisParser(analysis!)
            return parser.parse(buffers)
        }
        
        return nil
    }
    
    func parseTranslations(translations: NSDictionary?) -> ExperimentTranslationCollection? {
        if (translations != nil) {
            let parser = ExperimentTranslationsParser(translations!)
            
            return parser.parse()
        }
        
        return nil
    }
}