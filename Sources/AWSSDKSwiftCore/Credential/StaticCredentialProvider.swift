//
//  StaticCredentialProvider.swift
//  AWSSDKSwiftCore
//
//  Created by Fabian Fett on 05.12.19.
//

import Foundation
import INIParser
import NIO
import AWSSigner

public protocol StaticCredentialProvider: CredentialProvider {
    var credential    : StaticCredential { get }
    var eventLoopGroup: EventLoopGroup   { get }
}

extension StaticCredentialProvider {
  
    public func getCredential() -> EventLoopFuture<Credential> {
        // don't hop if not necessary
        if eventLoopGroup is MultiThreadedEventLoopGroup {
          return MultiThreadedEventLoopGroup.currentEventLoop!.makeSucceededFuture(credential)
        }
        
        return eventLoopGroup.next().makeSucceededFuture(credential)
    }
  
}

public struct StaticCredentialProv: StaticCredentialProvider {
  
    public let credential    : StaticCredential
    public let eventLoopGroup: EventLoopGroup
    
    init(credential: StaticCredential, eventLoopGroup: EventLoopGroup) {
        self.credential     = credential
        self.eventLoopGroup = eventLoopGroup
    }
}

/// environment variable version of credential provider that uses system environment variables to get credential details
public struct EnvironmentCredential: StaticCredentialProvider {

    public let credential    : StaticCredential
    public let eventLoopGroup: EventLoopGroup
    
    public init?(eventLoopGroup: EventLoopGroup) {
        guard let accessKeyId = ProcessInfo.processInfo.environment["AWS_ACCESS_KEY_ID"] else {
            return nil
        }
        guard let secretAccessKey = ProcessInfo.processInfo.environment["AWS_SECRET_ACCESS_KEY"] else {
            return nil
        }
      
        self.credential = StaticCredential(
            accessKeyId: accessKeyId,
            secretAccessKey: secretAccessKey,
            sessionToken: ProcessInfo.processInfo.environment["AWS_SESSION_TOKEN"])
        self.eventLoopGroup = eventLoopGroup
    }
}

/// Protocol for parsing AWS credential configs
protocol SharedCredentialsConfigParser {
    /// Parse a specified file
    ///
    /// - Parameter filename: The path to the file
    /// - Returns: A dictionary of dictionaries where the key is each profile
    /// and the value is the fields and values within that profile
    /// - Throws: If the file cannot be parsed
    func parse(filename: String) throws -> [String: [String:String]]
}

/// An implementation of SharedCredentialsConfigParser that uses INIParser
class IniConfigParser: SharedCredentialsConfigParser {
    func parse(filename: String) throws -> [String : [String : String]] {
        return try INIParser(filename).sections
    }
}

/// Provide AWS credentials via the ~/.aws/credential file
public struct SharedCredential: StaticCredentialProvider {

    /// Errors occurring when initializing a SharedCredential
    ///
    /// - missingProfile: If the profile requested was not found
    /// - missingAccessKeyId: If the access key ID was not found
    /// - missingSecretAccessKey: If the secret access key was not found
    public enum SharedCredentialError: Error, Equatable {
        case missingProfile(String)
        case missingAccessKeyId
        case missingSecretAccessKey
    }

    public let credential    : StaticCredential
    public let eventLoopGroup: EventLoopGroup

    public init(filename: String = "~/.aws/credentials",
                profile: String = "default",
                eventLoopGroup: EventLoopGroup) throws {
        try self.init(
            filename: filename,
            profile: profile,
            parser: IniConfigParser(),
            eventLoopGroup: eventLoopGroup
        )
    }

    init(filename: String,
         profile: String,
         parser: SharedCredentialsConfigParser,
         eventLoopGroup: EventLoopGroup) throws {
      
        // Expand tilde before parsing the file
        let filename = NSString(string: filename).expandingTildeInPath
        let contents = try parser.parse(filename: filename)
        guard let config = contents[profile] else {
            throw SharedCredentialError.missingProfile(profile)
        }
        guard let accessKeyId = config["aws_access_key_id"] else {
            throw SharedCredentialError.missingAccessKeyId
        }
        
        guard let secretAccessKey = config["aws_secret_access_key"] else {
            throw SharedCredentialError.missingSecretAccessKey
        }
        
        self.credential = StaticCredential(
          accessKeyId: accessKeyId,
          secretAccessKey: secretAccessKey,
          sessionToken: config["aws_session_token"])
        self.eventLoopGroup = eventLoopGroup
    }
}
