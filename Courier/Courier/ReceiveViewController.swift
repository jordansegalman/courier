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
    @IBOutlet weak var progressBar: UIProgressView!
    
    struct Transfer {
        var key: String
        var url: URL?
        var outputStream: OutputStream?
        var hmacContext: CCHmacContext?
        var cryptorRef: CCCryptorRef?
    }
    
    var receiveSocketManager: SocketManager!
    var receiveSocket: SocketIOClient!
    static var receiving: Bool = false
    private static var transfer: Transfer!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        keyTextField.addTarget(self, action: #selector(textFieldDidChange(_:)), for: .editingChanged)
        initializeSocketIO()
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
        receiveSocketManager = SocketManager(socketURL: URL(string: "http://127.0.0.1")!)
        receiveSocket = receiveSocketManager.defaultSocket
    }
    
    func setupSocketIO() {
        receiveSocket.on(clientEvent: .connect) { data, ack in
            print("Socket.IO connected")
            self.requestStartReceive()
        }
        receiveSocket.on(clientEvent: .disconnect) { data, ack in
            print("Socket.IO disconnected")
        }
        receiveSocket.on(clientEvent: .error) { data, ack in
            print("Socket.IO error")
            self.terminateSocketIO()
            self.resetReceive()
            UIApplication.shared.isIdleTimerDisabled = false
            self.progressBar.isHidden = true
            self.progressBar.setProgress(0, animated: false)
            self.activityIndicator.stopAnimating()
            self.receiveButton.isHidden = false
            self.keyTextField.isHidden = false
            self.showSocketIOConnectionAlert()
        }
        receiveSocket.connect(timeoutAfter: 5) {
            print("Socket.IO error")
            self.terminateSocketIO()
            self.resetReceive()
            UIApplication.shared.isIdleTimerDisabled = false
            self.progressBar.isHidden = true
            self.progressBar.setProgress(0, animated: false)
            self.activityIndicator.stopAnimating()
            self.receiveButton.isHidden = false
            self.keyTextField.isHidden = false
            self.showSocketIOConnectionAlert()
        }
    }
    
    func terminateSocketIO() {
        receiveSocket.disconnect()
        receiveSocket.removeAllHandlers()
        initializeSocketIO()
    }
    
    func requestStartReceive() {
        if receiveSocket.status == .connected {
            receiveSocket.emitWithAck("requestStartReceive", ["key": ReceiveViewController.transfer.key]).timingOut(after: 0) { data in
                if data.count == 1 {
                    let dictionary = data.first as! [String: String]
                    self.showPasswordEntryAlert(saltData: Data(base64Encoded: dictionary["salt"]!)!, ivData: Data(base64Encoded: dictionary["iv"]!)!, encryptedName: Data(base64Encoded: dictionary["encryptedName"]!)!)
                } else {
                    self.terminateSocketIO()
                    self.resetReceive()
                    UIApplication.shared.isIdleTimerDisabled = false
                    self.activityIndicator.stopAnimating()
                    self.receiveButton.isHidden = false
                    self.keyTextField.isHidden = false
                    self.showIncorrectKeyAlert()
                }
            }
        } else {
            terminateSocketIO()
            resetReceive()
            UIApplication.shared.isIdleTimerDisabled = false
            self.activityIndicator.stopAnimating()
            self.receiveButton.isHidden = false
            self.keyTextField.isHidden = false
            showSocketIOConnectionAlert()
        }
    }
    
    @IBAction func receiveButtonTouched(_ sender: UIButton) {
        if ReceiveViewController.receiving || SendViewController.sending {
            showTransferAlert()
            return
        }
        if let key = keyTextField.text, !key.isEmpty && key.count == 9 {
            ReceiveViewController.receiving = true
            keyTextField.resignFirstResponder()
            keyTextField.isHidden = true
            keyTextField.text = ""
            receiveButton.isHidden = true
            updateReceiveButtonState()
            activityIndicator.startAnimating()
            UIApplication.shared.isIdleTimerDisabled = true
            ReceiveViewController.transfer = Transfer(key: key, url: nil, outputStream: nil, hmacContext: nil, cryptorRef: nil)
            setupSocketIO()
        }
    }
    
    func showTransferAlert() {
        let transferAlertController = UIAlertController(title: "Another transfer is currently in progress.", message: nil, preferredStyle: .alert)
        transferAlertController.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        present(transferAlertController, animated: true, completion: nil)
    }
    
    func showSocketIOConnectionAlert() {
        let socketIOConnectionAlertController = UIAlertController(title: "Not Connected", message: nil, preferredStyle: .alert)
        socketIOConnectionAlertController.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        present(socketIOConnectionAlertController, animated: true, completion: nil)
    }
    
    func showIncorrectKeyAlert() {
        let incorrectKeyAlertController = UIAlertController(title: "Incorrect Key", message: nil, preferredStyle: .alert)
        incorrectKeyAlertController.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        present(incorrectKeyAlertController, animated: true, completion: nil)
    }
    
    func showPasswordEntryAlert(saltData: Data, ivData: Data, encryptedName: Data) {
        let passwordEntryAlertController = UIAlertController(title: "Enter Password for File", message: nil, preferredStyle: .alert)
        passwordEntryAlertController.addTextField { (textField) in
            textField.placeholder = "Password"
            textField.isSecureTextEntry = true
        }
        passwordEntryAlertController.addAction(UIAlertAction(title: "OK", style: .default, handler: { (UIAlertAction) in
            let password = passwordEntryAlertController.textFields![0].text
            if !password!.isEmpty {
                self.initializeReceive(password: password!, saltData: saltData, ivData: ivData, encryptedName: encryptedName)
            } else {
                self.showInvalidPasswordAlert(saltData: saltData, ivData: ivData, encryptedName: encryptedName)
            }
        }))
        passwordEntryAlertController.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { (UIAlertAction) in
            self.terminateSocketIO()
            self.resetReceive()
            UIApplication.shared.isIdleTimerDisabled = false
            self.activityIndicator.stopAnimating()
            self.receiveButton.isHidden = false
            self.keyTextField.isHidden = false
        }))
        present(passwordEntryAlertController, animated: true, completion: nil)
    }
    
    func showInvalidPasswordAlert(saltData: Data, ivData: Data, encryptedName: Data) {
        let invalidPasswordAlertController = UIAlertController(title: "Invalid Password", message: nil, preferredStyle: .alert)
        invalidPasswordAlertController.addAction(UIAlertAction(title: "OK", style: .default, handler: { (UIAlertAction) in
            self.showPasswordEntryAlert(saltData: saltData, ivData: ivData, encryptedName: encryptedName)
        }))
        present(invalidPasswordAlertController, animated: true, completion: nil)
    }
    
    func initializeReceive(password: String, saltData: Data, ivData: Data, encryptedName: Data) {
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
        let hmacKey = keyData.subdata(in: (Int(CC_SHA512_DIGEST_LENGTH) / 2)..<Int(CC_SHA512_DIGEST_LENGTH))
        let keySize = encryptionKey.count
        if keySize != kCCKeySizeAES256 {
            fatalError()
        }
        ReceiveViewController.transfer.hmacContext = CCHmacContext()
        hmacKey.withUnsafeBytes {
            CCHmacInit(&ReceiveViewController.transfer.hmacContext!, CCHmacAlgorithm(kCCHmacAlgSHA256), $0, hmacKey.count)
        }
        // ADD SALT, IV, AND ENCRYPTED NAME TO RECEIVER HMAC
        saltData.withUnsafeBytes {
            CCHmacUpdate(&ReceiveViewController.transfer.hmacContext!, $0, saltData.count)
        }
        ivData.withUnsafeBytes {
            CCHmacUpdate(&ReceiveViewController.transfer.hmacContext!, $0, ivData.count)
        }
        encryptedName.withUnsafeBytes {
            CCHmacUpdate(&ReceiveViewController.transfer.hmacContext!, $0, encryptedName.count)
        }
        // DECRYPT NAME
        let decryptedNameDataSize = size_t(encryptedName.count - ivData.count)
        var decryptedNameData = Data(count: decryptedNameDataSize)
        var numBytesDecrypted: size_t = 0
        let nameDecryptionStatus = decryptedNameData.withUnsafeMutableBytes { decryptedNameDataBytes in
            encryptedName.withUnsafeBytes { encryptedNameBytes in
                encryptionKey.withUnsafeBytes { encryptionKeyBytes in
                    CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding), encryptionKeyBytes, keySize, encryptedNameBytes, encryptedNameBytes + ivData.count, decryptedNameDataSize, decryptedNameDataBytes, decryptedNameDataSize, &numBytesDecrypted)
                }
            }
        }
        if nameDecryptionStatus != kCCSuccess {
            fatalError()
        }
        decryptedNameData.count = numBytesDecrypted
        guard let decryptedName = String(data: decryptedNameData, encoding: .utf8) else {
            ReceiveViewController.transfer.hmacContext = nil
            showInvalidPasswordAlert(saltData: saltData, ivData: ivData, encryptedName: encryptedName)
            return
        }
        // SETUP CRYPTORS
        ReceiveViewController.transfer.cryptorRef = encryptionKey.withUnsafeBytes { (encryptionKeyBytes: UnsafePointer<UInt8>) in
            ivData.withUnsafeBytes { (ivBytes: UnsafePointer<UInt8>) in
                var cryptorRefOut: CCCryptorRef?
                let result = CCCryptorCreate(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding), encryptionKeyBytes, encryptionKey.count, ivBytes, &cryptorRefOut)
                if result != kCCSuccess {
                    fatalError()
                }
                return cryptorRefOut
            }
        }
        // OPEN STREAMS
        cleanTemporaryDirectory()
        ReceiveViewController.transfer.url = FileManager.default.temporaryDirectory.appendingPathComponent(decryptedName)
        ReceiveViewController.transfer.outputStream = OutputStream(url: ReceiveViewController.transfer.url!, append: true)
        ReceiveViewController.transfer.outputStream!.open()
        progressBar.isHidden = false
        receive()
    }
    
    func receive() {
        receiveSocket.emitWithAck("requestReceive", ["key": ReceiveViewController.transfer.key]).timingOut(after: 0) { data in
            if data.count == 1 {
                let dictionary = data.first as! [String: String]
                if dictionary["encryptedData"] != nil && dictionary["progress"] != nil {
                    let encryptedData = Data(base64Encoded: dictionary["encryptedData"]!)!
                    let progress = Float(dictionary["progress"]!)!
                    self.receivedUpdate(encryptedData: encryptedData, progress: progress)
                    self.receive()
                } else if dictionary["trustedHmac"] != nil {
                    let trustedHmac = Data(base64Encoded: dictionary["trustedHmac"]!)!
                    self.receivedFinal(trustedHmac: trustedHmac)
                }
            } else {
                self.terminateSocketIO()
                self.resetReceive()
                UIApplication.shared.isIdleTimerDisabled = false
                self.progressBar.isHidden = true
                self.progressBar.setProgress(0, animated: false)
                self.activityIndicator.stopAnimating()
                self.receiveButton.isHidden = false
                self.keyTextField.isHidden = false
                self.showIncorrectKeyAlert()
            }
        }
    }
    
    func receivedUpdate(encryptedData: Data, progress: Float) {
        var decryptedData = Data()
        // DECRYPT UPDATED DATA
        encryptedData.withUnsafeBytes {
            CCHmacUpdate(&ReceiveViewController.transfer.hmacContext!, $0, encryptedData.count)
        }
        let decryptedOutputLength = CCCryptorGetOutputLength(ReceiveViewController.transfer.cryptorRef!, encryptedData.count, false)
        decryptedData.count = decryptedOutputLength
        var decryptedOutputMoved = 0
        let updateResult = encryptedData.withUnsafeBytes { encryptedBytes in
            decryptedData.withUnsafeMutableBytes { decryptedBytes in
                CCCryptorUpdate(ReceiveViewController.transfer.cryptorRef!, encryptedBytes, encryptedData.count, decryptedBytes, decryptedOutputLength, &decryptedOutputMoved)
            }
        }
        if updateResult != kCCSuccess {
            fatalError()
        }
        decryptedData.count = decryptedOutputMoved
        // SEND UPDATED CHUNK TO STREAM
        var outputData = decryptedData
        let outputLength = outputData.count
        if ReceiveViewController.transfer.outputStream!.hasSpaceAvailable {
            let result = outputData.withUnsafeMutableBytes { outputBytes in
                ReceiveViewController.transfer.outputStream!.write(outputBytes, maxLength: outputLength)
            }
            if result == -1 {
                fatalError()
            }
        } else {
            fatalError()
        }
        // UPDATE PROGRESS BAR
        self.progressBar.setProgress(progress, animated: true)
    }
    
    func receivedFinal(trustedHmac: Data) {
        // DECRYPT FINAL DATA
        var decryptedData = Data()
        var untrustedHmac = Data(count: Int(CC_SHA256_DIGEST_LENGTH))
        untrustedHmac.withUnsafeMutableBytes {
            CCHmacFinal(&ReceiveViewController.transfer.hmacContext!, $0)
        }
        let decryptedOutputLength = CCCryptorGetOutputLength(ReceiveViewController.transfer.cryptorRef!, 0, true)
        decryptedData.count = decryptedOutputLength
        var decryptedOutputMoved = 0
        let finalResult = decryptedData.withUnsafeMutableBytes { decryptedBytes in
            CCCryptorFinal(ReceiveViewController.transfer.cryptorRef!, decryptedBytes, decryptedOutputLength, &decryptedOutputMoved)
        }
        if finalResult != kCCSuccess {
            fatalError()
        }
        decryptedData.count = decryptedOutputMoved
        // RELEASE CRYPTORS AND CLOSE STREAMS
        CCCryptorRelease(ReceiveViewController.transfer.cryptorRef!)
        ReceiveViewController.transfer.outputStream!.close()
        // COMPARE HMACS, PREVENT TIMING ATTACK
        if !verifyHmac(trustedHmac: trustedHmac, untrustedHmac: untrustedHmac) {
            terminateSocketIO()
            resetReceive()
            UIApplication.shared.isIdleTimerDisabled = false
            self.progressBar.isHidden = true
            self.progressBar.setProgress(0, animated: false)
            self.activityIndicator.stopAnimating()
            self.receiveButton.isHidden = false
            self.keyTextField.isHidden = false
            showCouldNotAuthenticateDataAlert()
            return
        }
        self.receiveSocket.emit("received", ["key": ReceiveViewController.transfer.key])
        self.presentActivityViewController()
    }
    
    func verifyHmac(trustedHmac: Data, untrustedHmac: Data) -> Bool {
        var result: UInt8 = trustedHmac.count == untrustedHmac.count ? 0 : 1
        for (i, untrustedByte) in untrustedHmac.enumerated() {
            result |= trustedHmac[i % trustedHmac.count] ^ untrustedByte
        }
        return result == 0
    }
    
    func showCouldNotAuthenticateDataAlert() {
        let couldNotAuthenticateDataAlertController = UIAlertController(title: "Could Not Authenticate Data", message: nil, preferredStyle: .alert)
        couldNotAuthenticateDataAlertController.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        present(couldNotAuthenticateDataAlertController, animated: true, completion: nil)
    }
    
    func presentActivityViewController() {
        // PRESENT ACTIVITY VIEW CONTROLLER
        let activityViewController = UIActivityViewController(activityItems: [ReceiveViewController.transfer.url!], applicationActivities: nil)
        terminateSocketIO()
        resetReceive()
        UIApplication.shared.isIdleTimerDisabled = false
        self.progressBar.isHidden = true
        self.progressBar.setProgress(0, animated: false)
        self.activityIndicator.stopAnimating()
        self.receiveButton.isHidden = false
        self.keyTextField.isHidden = false
        present(activityViewController, animated: true, completion: nil)
    }
    
    func cleanTemporaryDirectory() {
        do {
            let temporaryDirectoryContents = try FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path)
            try temporaryDirectoryContents.forEach { file in
                let url = FileManager.default.temporaryDirectory.appendingPathComponent(file)
                try FileManager.default.removeItem(at: url)
            }
        } catch {
            fatalError()
        }
    }
    
    func resetReceive() {
        ReceiveViewController.receiving = false
        ReceiveViewController.transfer = nil
    }
}
