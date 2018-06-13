//
//  ReceiveViewController.swift
//  Courier
//
//  Created by Jordan Segalman on 6/7/18.
//  Copyright © 2018 example. All rights reserved.
//

import UIKit
import SocketIO

class ReceiveViewController: UIViewController {
    @IBOutlet weak var keyTextField: UITextField!
    @IBOutlet weak var receiveButton: UIButton!
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
    
    let socketManager = SocketManager(socketURL: URL(string: "http://127.0.0.1")!)
    var socket: SocketIOClient!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        keyTextField.addTarget(self, action: #selector(textFieldDidChange(_:)), for: .editingChanged)
        socket = socketManager.defaultSocket
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        initializeSocketIO()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        terminateSocketIO()
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        keyTextField.resignFirstResponder()
    }
    
    @objc func textFieldDidChange(_ textField: UITextField) {
        updateReceiveButtonState()
    }
    
    private func updateReceiveButtonState() {
        if let key = keyTextField.text {
            receiveButton.isEnabled = !key.isEmpty && key.count == 9
        }
    }
    
    func initializeSocketIO() {
        socket.on(clientEvent: .connect) { data, ack in
            print("Socket.IO connected")
        }
        socket.on(clientEvent: .disconnect) { data, ack in
            print("Socket.IO disconnected")
        }
        socket.connect()
    }
    
    func terminateSocketIO() {
        socket.disconnect()
        socket.removeAllHandlers()
    }
    
    @IBAction func receiveButtonTouched(_ sender: UIButton) {
        if socket.status != .connected {
            showSocketIOConnectionAlert()
            return
        }
        if let key = keyTextField.text, !key.isEmpty && key.count == 9 {
            keyTextField.text = ""
            keyTextField.isHidden = true
            receiveButton.isHidden = true
            activityIndicator.startAnimating()
            socket.emitWithAck("requestReceive", ["key": key]).timingOut(after: 0) { data in
                if data.count == 1 {
                    let dictionary = data[0] as! [String: String]
                    self.socket.emit("received", ["key": key])
                    self.decryptBase64AndName(encrypted: dictionary["encrypted"]!, authenticated: dictionary["authenticated"]!, salt: dictionary["salt"]!, password: "passwordpasswordpasswordpassword")
                } else {
                    self.keyTextField.isHidden = false
                    self.receiveButton.isHidden = false
                    self.activityIndicator.stopAnimating()
                    self.showIncorrectKeyAlert()
                }
            }
        }
    }
    
    func showSocketIOConnectionAlert() {
        let socketIOConnectionAlertController = UIAlertController(title: "Not Connected", message: nil, preferredStyle: .alert)
        socketIOConnectionAlertController.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        self.present(socketIOConnectionAlertController, animated: true, completion: nil)
    }
    
    func showIncorrectKeyAlert() {
        let socketIOConnectionAlertController = UIAlertController(title: "Incorrect Key", message: nil, preferredStyle: .alert)
        socketIOConnectionAlertController.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        present(socketIOConnectionAlertController, animated: true, completion: nil)
    }
    
    func decryptBase64AndName(encrypted: String, authenticated: String, salt: String, password: String) {
        let encryptedData = Data(base64Encoded: encrypted)!
        let authenticatedData = Data(base64Encoded: authenticated)!
        let saltData = Data(base64Encoded: salt)!
        let passwordData = password.data(using: .utf8)!
        var keyData = Data(count: Int(CC_SHA512_DIGEST_LENGTH))
        let derivationStatus = keyData.withUnsafeMutableBytes { keyBytes in
            saltData.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), password, passwordData.count, saltBytes, Int(CC_SHA512_DIGEST_LENGTH), CCPBKDFAlgorithm(kCCPRFHmacAlgSHA512), 100000, keyBytes, Int(CC_SHA512_DIGEST_LENGTH))
            }
        }
        if derivationStatus != kCCSuccess {
            fatalError()
        }
        let encryptionKey = keyData.subdata(in: 0..<(Int(CC_SHA512_DIGEST_LENGTH) / 2))
        let authenticationKey = keyData.subdata(in: (Int(CC_SHA512_DIGEST_LENGTH) / 2)..<Int(CC_SHA512_DIGEST_LENGTH))
        var unauthenticatedData = Data(count: Int(CC_SHA256_DIGEST_LENGTH))
        unauthenticatedData.withUnsafeMutableBytes { unauthenticatedBytes in
            encryptedData.withUnsafeBytes { encryptedBytes in
                authenticationKey.withUnsafeBytes { authenticationKeyBytes in
                    CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA256), authenticationKeyBytes, authenticationKey.count, encryptedBytes, encryptedData.count, unauthenticatedBytes)
                }
            }
        }
        if unauthenticatedData != authenticatedData {
            self.keyTextField.isHidden = false
            self.receiveButton.isHidden = false
            self.activityIndicator.stopAnimating()
            showIncorrectPasswordAlert()
            return
        }
        let keySize = encryptionKey.count
        if keySize != kCCKeySizeAES256 {
            fatalError()
        }
        let ivSize = kCCBlockSizeAES128
        let decryptedSize = size_t(encryptedData.count - ivSize)
        var decryptedData = Data(count: decryptedSize)
        var numBytesDecrypted: size_t = 0
        let decryptionStatus = decryptedData.withUnsafeMutableBytes { decryptedBytes in
            encryptedData.withUnsafeBytes { encryptedDataBytes in
                encryptionKey.withUnsafeBytes { encryptionKeyBytes in
                    CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding), encryptionKeyBytes, keySize, encryptedDataBytes, encryptedDataBytes + ivSize, decryptedSize, decryptedBytes, decryptedSize, &numBytesDecrypted)
                }
            }
        }
        if decryptionStatus != kCCSuccess {
            fatalError()
        }
        decryptedData.count = numBytesDecrypted
        if let decryptedString = String(data: decryptedData, encoding: .utf8) {
            let decryptedStringArray = decryptedString.components(separatedBy: "$$$$$$$$")
            let base64 = decryptedStringArray[0]
            let name = decryptedStringArray[1]
            self.keyTextField.isHidden = false
            self.receiveButton.isHidden = false
            self.activityIndicator.stopAnimating()
            createActivityViewController(base64: base64, name: name)
        } else {
            self.keyTextField.isHidden = false
            self.receiveButton.isHidden = false
            self.activityIndicator.stopAnimating()
            showIncorrectPasswordAlert()
        }
    }
    
    func showIncorrectPasswordAlert() {
        let socketIOConnectionAlertController = UIAlertController(title: "Incorrect Password", message: nil, preferredStyle: .alert)
        socketIOConnectionAlertController.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        self.present(socketIOConnectionAlertController, animated: true, completion: nil)
    }
    
    func createActivityViewController(base64: String, name: String) {
        do {
            let decodedData: Data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters)!
            let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try decodedData.write(to: fileURL, options: .atomicWrite)
            let activityViewController = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
            present(activityViewController, animated: true, completion: nil)
        } catch {
            fatalError()
        }
    }
}
