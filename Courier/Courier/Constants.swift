import Foundation

class Constants {
    static let serverAddress: URL = URL(string: "http://127.0.0.1")!    // Server address
    static let keyLength: UInt8 = 9 // Transaction key length
    static let PBKDF2Iterations: UInt32 = 1000000   // Number of iterations to use for PBKDF2
    static let inputStreamReadBytes: Int = 1048576  // Number of bytes to read at a time from file input stream
}
