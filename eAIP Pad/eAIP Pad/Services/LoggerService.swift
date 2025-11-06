import Foundation
import Security

// MARK: - LoggerService

/// A service for logging events and messages within the application.
/// It supports different log levels, encryption for sensitive data, and exporting logs.
public class LoggerService {
    
    /// Singleton instance of the LoggerService.
    public static let shared = LoggerService()
    
    /// The type of log entry.
    public enum LogType: String {
        case info = "INFO"
        case warning = "WARNING"
        case error = "ERROR"
    }
    
    /// Represents a single log entry.
    public struct LogEntry {
        public let timestamp: Date
        public let type: LogType
        public let message: String
        public let isEncrypted: Bool
        
        public var formattedString: String {
            let dateFormatter = ISO8601DateFormatter()
            let timestampString = dateFormatter.string(from: timestamp)
            return "[\(timestampString)] [\(type.rawValue)] \(message)"
        }
    }
    
    private var logEntries: [LogEntry] = []
    private let logQueue = DispatchQueue(label: "com.eAIPPad.loggerQueue")
    
    // MARK: - Public Methods

    /// Adds a new log entry.
    /// - Parameters:
    ///   - type: The type of log (.info, .warning, .error).
    ///   - message: The log message.
    ///   - encrypt: If `true`, the message will be RSA encrypted. Defaults to `false`.
    public func addLog(type: LogType, message: String, encrypt shouldEncrypt: Bool = false) {
        logQueue.async {
            let messageToStore:
            String
            if shouldEncrypt {
                if let encryptedMessage = self.encrypt(string: message) {
                    messageToStore = "fetch byte infoData: \(encryptedMessage)"
                } else {
                    // 如果加密失败，记录一个错误，并存储原始消息
                    messageToStore = "Encryption failed for message: \(message)"
                    self.addLog(type: .error, message: "Failed to encrypt log message.")
                }
            } else {
                messageToStore = message
            }

            let newEntry = LogEntry(
                timestamp: Date(),
                type: type,
                message: messageToStore,
                isEncrypted: shouldEncrypt
            )
            self.logEntries.append(newEntry)
        }
    }

    /// Exports all log entries as a single formatted string.
    /// - Returns: A string containing all log entries.
    public func exportLogsToString() -> String {
        logQueue.sync {
            logEntries.map { $0.formattedString }.joined(separator: "\n")
        }
    }

    /// Exports all log entries to a `log.txt` file.
    /// - Returns: The URL of the saved log file, or `nil` if the operation fails.
    public func exportLogsToFile() -> URL? {
        let logString = exportLogsToString()
        let fileManager = FileManager.default
        let tempDirectory = fileManager.temporaryDirectory
        let fileURL = tempDirectory.appendingPathComponent("log.txt")

        do {
            try logString.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            addLog(type: .error, message: "Failed to export logs to file: \(error.localizedDescription)")
            return nil
        }
    }

    private init() {
        // Private initializer to enforce singleton pattern.
    }

    // MARK: - RSA Encryption

    /// The public key used for RSA encryption.
    ///
    /// **Security Note:** Replace this placeholder with your actual public key.
    /// For enhanced security, consider loading the key from a secure location (e.g., a separate configuration file not tracked by Git)
    /// rather than hardcoding it directly in the source code.
    private let rsaPublicKey: String = """
    -----BEGIN PUBLIC KEY-----
    YOUR_PUBLIC_KEY_HERE
    -----END PUBLIC KEY-----
    """

    /// Encrypts a string using the configured RSA public key.
    /// - Parameter string: The string to encrypt.
    /// - Returns: The Base64 encoded encrypted string, or `nil` if encryption fails.
    private func encrypt(string: String) -> String? {
        guard let data = string.data(using: .utf8) else {
            return nil
        }

        guard let publicKey = getPublicKey() else {
            return nil
        }

        var error: Unmanaged<CFError>?
        guard let encryptedData = SecKeyCreateEncryptedData(publicKey, .rsaEncryptionOAEPSHA256, data as CFData, &error) as Data? else {
            print("Encryption failed: \(error.debugDescription)")
            return nil
        }

        return encryptedData.base64EncodedString()
    }

    /// Retrieves the SecKey object from the stored public key string.
    /// - Returns: A `SecKey` object, or `nil` if the key is invalid.
    private func getPublicKey() -> SecKey? {
        let keyString = rsaPublicKey
            .replacingOccurrences(of: "-----BEGIN PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "-----END PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = Data(base64Encoded: keyString) else {
            return nil
        }

        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits as String: 2048,
        ]

        var error: Unmanaged<CFError>?
        guard let secKey = SecKeyCreateWithData(data as CFData, attributes as CFDictionary, &error) else {
            print("Failed to create SecKey: \(error.debugDescription)")
            return nil
        }
        return secKey
    }
}