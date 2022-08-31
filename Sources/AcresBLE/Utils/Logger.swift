//
//  Logger.swift
//  
//
//  Created by Jozo Mostarac on 21.07.2022..
//

import Foundation

public final class Logger {
    public static let shared = Logger()
    private init() {}

    enum Level {
        case none
        case error
        case debug
        
        var string: String {
            switch self {
            case .debug:
                return "DEBUG"
            case .error:
                return "ERROR"
            case .none:
                return ""
            }
        }
    }
    
    static func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.debug, message: message, file: file, function: function, line: line)
    }
    static func error(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.error, message: message, file: file, function: function, line: line)
    }
    
    private static func log(_ level: Level, message: String, file: String, function: String, line: Int) {
        let fileName = URL(fileURLWithPath: file).lastPathComponent.components(separatedBy: ".").first ?? ""
        let msg = "\(level.string): \(fileName).\(function)[\(line)]: \(message)"
        debugPrint(msg)
    }
}

