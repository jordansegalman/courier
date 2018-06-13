//
//  SendViewController.swift
//  Courier
//
//  Created by Jordan Segalman on 6/7/18.
//  Copyright © 2018 example. All rights reserved.
//

import UIKit
import MobileCoreServices
import Photos
import SocketIO

class SendViewController: UIViewController, UIImagePickerControllerDelegate, UINavigationControllerDelegate, UIDocumentPickerDelegate {
    @IBOutlet weak var sendButton: UIButton!
    @IBOutlet weak var keyLabel: UILabel!
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
    
    struct Transfer {
        var url: URL
        var inputStream: InputStream
        var hmacContext: CCHmacContext
        var cryptorRef: CCCryptorRef
    }
    
    let socketManager = SocketManager(socketURL: URL(string: "http://127.0.0.1")!)
    var socket: SocketIOClient!
    private static var transfer: Transfer!
    var encryptedToSend: String!
    var authenticatedToSend: String!
    var saltToSend: String!
    
    override func viewDidLoad() {
        super.viewDidLoad()
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
    
    func initializeSocketIO() {
        socket.on(clientEvent: .connect) { data, ack in
            print("Socket.IO connected")
        }
        socket.on(clientEvent: .disconnect) { data, ack in
            print("Socket.IO disconnected")
        }
        socket.on("requestSend") { data, ack in
            self.keyLabel.isHidden = true
            self.keyLabel.text = ""
            self.activityIndicator.startAnimating()
            ack.with(["encrypted": self.encryptedToSend, "authenticated": self.authenticatedToSend, "salt": self.saltToSend])
        }
        socket.on("received") { data, ack in
            self.encryptedToSend = nil
            self.authenticatedToSend = nil
            self.saltToSend = nil
            self.activityIndicator.stopAnimating()
            self.sendButton.isHidden = false
        }
        socket.connect()
    }
    
    func terminateSocketIO() {
        socket.disconnect()
        socket.removeAllHandlers()
    }
    
    func requestSendSocketIO(encrypted: String, authenticated: String, salt: String) {
        encryptedToSend = encrypted
        authenticatedToSend = authenticated
        saltToSend = salt
        socket.emitWithAck("requestSend", []).timingOut(after: 0) { data in
            self.activityIndicator.stopAnimating()
            let key = data[0] as! String
            self.keyLabel.text = key
            self.keyLabel.isHidden = false
        }
    }
    
    @IBAction func sendButtonTouched(_ sender: UIButton) {
        if socket.status != .connected {
            showSocketIOConnectionAlert()
            return
        }
        let alertController = UIAlertController(title: "Choose Something to Send", message: nil, preferredStyle: .actionSheet)
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            alertController.addAction(UIAlertAction(title: "Camera", style: .default, handler: { (UIAlertAction) in
                self.checkPermissions(sourceType: .camera)
            }))
        }
        if UIImagePickerController.isSourceTypeAvailable(.photoLibrary) {
            alertController.addAction(UIAlertAction(title: "Photos", style: .default, handler: { (UIAlertAction) in
                self.checkPermissions(sourceType: .photoLibrary)
            }))
        }
        alertController.addAction(UIAlertAction(title: "Files", style: .default, handler: { (UIAlertAction) in
            self.openDocument()
        }))
        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        present(alertController, animated: true, completion: nil)
    }
    
    func showSocketIOConnectionAlert() {
        let socketIOConnectionAlertController = UIAlertController(title: "Not Connected", message: nil, preferredStyle: .alert)
        socketIOConnectionAlertController.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        self.present(socketIOConnectionAlertController, animated: true, completion: nil)
    }
    
    func checkPermissions(sourceType: UIImagePickerControllerSourceType) {
        if sourceType == .camera {
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                checkMicrophonePermissions()
            case .denied:
                showPermissionsAlert(sourceType: .camera)
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video, completionHandler: {accessGranted in
                    if accessGranted {
                        self.checkMicrophonePermissions()
                    }
                })
            case .restricted:
                showPermissionsAlert(sourceType: .camera)
            }
        } else if sourceType == .photoLibrary {
            switch PHPhotoLibrary.authorizationStatus() {
            case .authorized:
                openPhotoLibrary()
            case .denied:
                showPermissionsAlert(sourceType: .photoLibrary)
            case .notDetermined:
                PHPhotoLibrary.requestAuthorization({ (status) in
                    if status == PHAuthorizationStatus.authorized {
                        self.openPhotoLibrary()
                    }
                })
            case .restricted:
                showPermissionsAlert(sourceType: .photoLibrary)
            }
        }
    }
    
    func checkMicrophonePermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            openCamera()
        case .denied:
            showMicrophonePermissionsAlert()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio, completionHandler: {_ in self.openCamera()
            })
        case .restricted:
            showMicrophonePermissionsAlert()
        }
    }
    
    func showPermissionsAlert(sourceType: UIImagePickerControllerSourceType) {
        var alertTitle: String = ""
        if sourceType == .camera {
            alertTitle = "Courier does not have permission to access the camera. Please allow access to the camera in Settings."
        } else if sourceType == .photoLibrary {
            alertTitle = "Courier does not have permission to access your photos. Please allow access to your photos in Settings."
        }
        let permissionsAlertController = UIAlertController(title: alertTitle, message: nil, preferredStyle: .alert)
        permissionsAlertController.addAction(UIAlertAction(title: "Settings", style: .default, handler: { (permissionsAlertController) in
            UIApplication.shared.open(URL(string: UIApplicationOpenSettingsURLString)!, options: [:], completionHandler: nil)
        }))
        permissionsAlertController.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        present(permissionsAlertController, animated: true, completion: nil)
    }
    
    func showMicrophonePermissionsAlert() {
        let microphonePermissionsAlertController = UIAlertController(title: "Courier does not have permission to access the microphone.", message: nil, preferredStyle: .alert)
        microphonePermissionsAlertController.addAction(UIAlertAction(title: "OK", style: .default, handler: { (alertController) in
            self.openCamera()
        }))
        self.present(microphonePermissionsAlertController, animated: true, completion: nil)
    }

    func openCamera() {
        sendButton.isHidden = true
        let imagePickerController = UIImagePickerController()
        imagePickerController.sourceType = .camera
        imagePickerController.mediaTypes = UIImagePickerController.availableMediaTypes(for: .camera)!
        imagePickerController.allowsEditing = false
        imagePickerController.delegate = self
        present(imagePickerController, animated: true, completion: nil)
    }
    
    func openPhotoLibrary() {
        sendButton.isHidden = true
        let imagePickerController = UIImagePickerController()
        imagePickerController.sourceType = .photoLibrary
        imagePickerController.mediaTypes = UIImagePickerController.availableMediaTypes(for: .photoLibrary)!
        imagePickerController.allowsEditing = false
        imagePickerController.delegate = self
        present(imagePickerController, animated: true, completion: nil)
    }
    
    func openDocument() {
        sendButton.isHidden = true
        let documentPickerController = UIDocumentPickerViewController(documentTypes: [kUTTypeItem as String], in: .import)
        documentPickerController.allowsMultipleSelection = false
        documentPickerController.modalPresentationStyle = .fullScreen
        documentPickerController.delegate = self
        present(documentPickerController, animated: true, completion: nil)
    }
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo
        info: [String : Any]) {
        dismiss(animated: true, completion: nil)
        if info[UIImagePickerControllerMediaType] as! CFString == kUTTypeImage {
            if picker.sourceType == .camera {
                let name = UUID().uuidString + ".png"
                var base64: String = ""
                if let originalImage = info[UIImagePickerControllerOriginalImage] as? UIImage {
                    base64 = UIImagePNGRepresentation(originalImage)!.base64EncodedString()
                } else if let editedImage = info[UIImagePickerControllerEditedImage] as? UIImage {
                    base64 = UIImagePNGRepresentation(editedImage)!.base64EncodedString()
                }
                let password = "passwordpasswordpasswordpassword"
                encryptBase64AndName(base64: base64, name: name, password: password)
            } else {
                if let imageURL = info[UIImagePickerControllerImageURL] as? URL {
                    do {
                        let name = imageURL.lastPathComponent
                        let base64 = try Data(contentsOf: imageURL, options: .mappedIfSafe).base64EncodedString()
                        let password = "passwordpasswordpasswordpassword"
                        encryptBase64AndName(base64: base64, name: name, password: password)
                    } catch {
                        fatalError()
                    }
                }
            }
        }
        if info[UIImagePickerControllerMediaType] as! CFString == kUTTypeMovie {
            if let mediaURL = info[UIImagePickerControllerMediaURL] as? URL {
                do {
                    let name = mediaURL.lastPathComponent
                    let base64 = try Data(contentsOf: mediaURL, options: .mappedIfSafe).base64EncodedString()
                    let password = "passwordpasswordpasswordpassword"
                    encryptBase64AndName(base64: base64, name: name, password: password)
                } catch {
                    fatalError()
                }
            }
        }
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        sendButton.isHidden = false
        dismiss(animated: true, completion: nil)
    }
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        dismiss(animated: true, completion: nil)
        if urls.count == 1 {
            do {
                let name = urls[0].lastPathComponent
                
                //------------------------------------------------
                
                // !!!!!!! Store url on sender, send transfer ready to server and get key, send transfer request from receiver with key, once confirms transfer send salt, iv, and iv hmac to receiver, receiver request first chunk, open url and start transferring chunks (wait for request, ack chunk, wait for response, ack chunk...), ack receiver no more chunks after FINAL chunk sent, close streams, open url on receiver !!!!!!!
                
                // GENERATE SALT, ENCRYPTION KEY, HMAC KEY, AND IV
                let nameData = name.data(using: .utf8)!
                let tempPassword: String = "passwordpasswordpasswordpassword"
                let tempPasswordData = tempPassword.data(using: .utf8)!
                var saltData = Data(count: Int(CC_SHA512_DIGEST_LENGTH))
                let saltStatus = saltData.withUnsafeMutableBytes { saltBytes in
                    SecRandomCopyBytes(kSecRandomDefault, Int(CC_SHA512_DIGEST_LENGTH), saltBytes)
                }
                if saltStatus != errSecSuccess {
                    fatalError()
                }
                var keyData = Data(count: Int(CC_SHA512_DIGEST_LENGTH))
                let derivationStatus = keyData.withUnsafeMutableBytes { keyBytes in
                    saltData.withUnsafeBytes { saltBytes in
                        CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), tempPassword, tempPasswordData.count, saltBytes, Int(CC_SHA512_DIGEST_LENGTH), CCPBKDFAlgorithm(kCCPRFHmacAlgSHA512), 100000, keyBytes, Int(CC_SHA512_DIGEST_LENGTH))
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
                var hmacContext = CCHmacContext()
                hmacKey.withUnsafeBytes {
                    CCHmacInit(&hmacContext, CCHmacAlgorithm(kCCHmacAlgSHA256), $0, hmacKey.count)
                }
                var hmacContext2 = CCHmacContext()
                hmacKey.withUnsafeBytes {
                    CCHmacInit(&hmacContext2, CCHmacAlgorithm(kCCHmacAlgSHA256), $0, hmacKey.count)
                }
                let ivSize = kCCBlockSizeAES128
                var ivData = Data(count: ivSize)
                let ivStatus = ivData.withUnsafeMutableBytes { ivBytes in
                    SecRandomCopyBytes(kSecRandomDefault, ivSize, ivBytes)
                }
                if ivStatus != errSecSuccess {
                    fatalError()
                }
                // ENCRYPT NAME
                let encryptedNameSize = size_t(nameData.count + kCCBlockSizeAES128 + ivSize)
                var encryptedName = Data(count: encryptedNameSize)
                var numBytesEncrypted: size_t = 0
                let nameEncryptionStatus = encryptedName.withUnsafeMutableBytes { encryptedNameBytes in
                    nameData.withUnsafeBytes { nameBytes in
                        encryptionKey.withUnsafeBytes { encryptionKeyBytes in
                            CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding), encryptionKeyBytes, keySize, encryptedNameBytes, nameBytes, nameData.count, encryptedNameBytes + ivSize, encryptedNameSize, &numBytesEncrypted)
                        }
                    }
                }
                if nameEncryptionStatus != kCCSuccess {
                    fatalError()
                }
                encryptedName.count = numBytesEncrypted + ivSize
                // ADD SALT, IV, AND ENCRYPTED NAME TO SENDER HMAC
                saltData.withUnsafeBytes {
                    CCHmacUpdate(&hmacContext, $0, saltData.count)
                }
                ivData.withUnsafeBytes {
                    CCHmacUpdate(&hmacContext, $0, ivData.count)
                }
                encryptedName.withUnsafeBytes {
                    CCHmacUpdate(&hmacContext, $0, encryptedName.count)
                }
                // SEND SALT, IV, AND ENCRYPTED NAME TO RECEIVER
                // ADD SALT, IV, AND ENCRYPTED NAME TO RECEIVER HMAC
                saltData.withUnsafeBytes {
                    CCHmacUpdate(&hmacContext2, $0, saltData.count)
                }
                ivData.withUnsafeBytes {
                    CCHmacUpdate(&hmacContext2, $0, ivData.count)
                }
                encryptedName.withUnsafeBytes {
                    CCHmacUpdate(&hmacContext2, $0, encryptedName.count)
                }
                // DECRYPT NAME
                let decryptedNameDataSize = size_t(encryptedName.count - ivSize)
                var decryptedNameData = Data(count: decryptedNameDataSize)
                var numBytesDecrypted: size_t = 0
                let nameDecryptionStatus = decryptedNameData.withUnsafeMutableBytes { decryptedNameDataBytes in
                    encryptedName.withUnsafeBytes { encryptedNameBytes in
                        encryptionKey.withUnsafeBytes { encryptionKeyBytes in
                            CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding), encryptionKeyBytes, keySize, encryptedNameBytes, encryptedNameBytes + ivSize, decryptedNameDataSize, decryptedNameDataBytes, decryptedNameDataSize, &numBytesDecrypted)
                        }
                    }
                }
                if nameDecryptionStatus != kCCSuccess {
                    fatalError()
                }
                decryptedNameData.count = numBytesDecrypted
                let decryptedName = String(data: decryptedNameData, encoding: .utf8)!
                // SETUP CRYPTORS
                let cryptorRef: CCCryptorRef?
                var encryptedData = Data()
                cryptorRef = encryptionKey.withUnsafeBytes { (encryptionKeyBytes: UnsafePointer<UInt8>) in
                    ivData.withUnsafeBytes { (ivBytes: UnsafePointer<UInt8>) in
                        var cryptorRefOut: CCCryptorRef?
                        let result = CCCryptorCreate(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding), encryptionKeyBytes, encryptionKey.count, ivBytes, &cryptorRefOut)
                        if result != kCCSuccess {
                            fatalError()
                        }
                        return cryptorRefOut
                    }
                }
                let cryptorRef2: CCCryptorRef?
                var decryptedData = Data()
                cryptorRef2 = encryptionKey.withUnsafeBytes { (encryptionKeyBytes: UnsafePointer<UInt8>) in
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
                var inputData = Data(count: 1048576)
                let inputLength = inputData.count
                let inputStream: InputStream = InputStream(url: urls[0])!
                let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(decryptedName)
                let outputStream: OutputStream = OutputStream(url: outputURL, append: true)!
                outputStream.open()
                inputStream.open()
                // CHANGE TO IF STATEMENT AND ONLY CALL WHEN RECEIVER REQUESTS
                while inputStream.hasBytesAvailable {
                    let result = inputData.withUnsafeMutableBytes { inputBytes in
                        inputStream.read(inputBytes, maxLength: inputLength)
                    }
                    if result == -1 {
                        fatalError()
                    }
                    // ENCRYPT UPDATED DATA
                    let encryptedOutputLength = CCCryptorGetOutputLength(cryptorRef, inputData.count, false)
                    encryptedData.count = encryptedOutputLength
                    var encryptedOutputMoved = 0
                    let updateResult = inputData.withUnsafeBytes { inputBytes in
                        encryptedData.withUnsafeMutableBytes { encryptedBytes in
                            CCCryptorUpdate(cryptorRef, inputBytes, inputLength, encryptedBytes, encryptedOutputLength, &encryptedOutputMoved)
                        }
                    }
                    if updateResult != kCCSuccess {
                        fatalError()
                    }
                    encryptedData.count = encryptedOutputMoved
                    encryptedData.withUnsafeBytes {
                        CCHmacUpdate(&hmacContext, $0, encryptedData.count)
                    }
                    // SEND encryptedData TO RECEIVER
                    // DECRYPT UPDATED DATA
                    encryptedData.withUnsafeBytes {
                        CCHmacUpdate(&hmacContext2, $0, encryptedData.count)
                    }
                    let decryptedOutputLength = CCCryptorGetOutputLength(cryptorRef2, encryptedData.count, false)
                    decryptedData.count = decryptedOutputLength
                    var decryptedOutputMoved = 0
                    let updateResult2 = encryptedData.withUnsafeBytes { encryptedBytes in
                        decryptedData.withUnsafeMutableBytes { decryptedBytes in
                            CCCryptorUpdate(cryptorRef2, encryptedBytes, encryptedOutputMoved, decryptedBytes, decryptedOutputLength, &decryptedOutputMoved)
                        }
                    }
                    if updateResult2 != kCCSuccess {
                        fatalError()
                    }
                    decryptedData.count = decryptedOutputMoved
                    // SEND UPDATED CHUNK TO STREAM
                    var outputData = decryptedData
                    let outputLength = outputData.count
                    if outputStream.hasSpaceAvailable {
                        let result = outputData.withUnsafeMutableBytes { outputBytes in
                            outputStream.write(outputBytes, maxLength: outputLength)
                        }
                        if result == -1 {
                            fatalError()
                        }
                    } else {
                        fatalError()
                    }
                }
                // ENCRYPT FINAL DATA
                let encryptedOutputLength = CCCryptorGetOutputLength(cryptorRef, 0, true)
                encryptedData.count = encryptedOutputLength
                var encryptedOutputMoved = 0
                let finalResult = encryptedData.withUnsafeMutableBytes { encryptedBytes in
                    CCCryptorFinal(cryptorRef, encryptedBytes, encryptedOutputLength, &encryptedOutputMoved)
                }
                if finalResult != kCCSuccess {
                    fatalError()
                }
                encryptedData.count = encryptedOutputMoved
                var hmac = Data(count: Int(CC_SHA256_DIGEST_LENGTH))
                hmac.withUnsafeMutableBytes {
                    CCHmacFinal(&hmacContext, $0)
                }
                // DECRYPT FINAL DATA
                var hmac2 = Data(count: Int(CC_SHA256_DIGEST_LENGTH))
                hmac2.withUnsafeMutableBytes {
                    CCHmacFinal(&hmacContext2, $0)
                }
                let decryptedOutputLength = CCCryptorGetOutputLength(cryptorRef2, 0, true)
                decryptedData.count = decryptedOutputLength
                var decryptedOutputMoved = 0
                let finalResult2 = decryptedData.withUnsafeMutableBytes { decryptedBytes in
                    CCCryptorFinal(cryptorRef2, decryptedBytes, decryptedOutputLength, &decryptedOutputMoved)
                }
                if finalResult2 != kCCSuccess {
                    fatalError()
                }
                decryptedData.count = decryptedOutputMoved
                // RELEASE CRYPTORS AND CLOSE STREAMS
                if cryptorRef != nil {
                    CCCryptorRelease(cryptorRef)
                }
                if cryptorRef2 != nil {
                    CCCryptorRelease(cryptorRef2)
                }
                inputStream.close()
                outputStream.close()
                // COMPARE HMACS AND PREVENT TIMING ATTACK
                if !hmacCompare(hmac, hmac2) {
                    fatalError()
                }
                // DELETE FINAL DIR FILES, COPY TEMP DIR TO FINAL DIR, DELETE TEMP DIR FILES
                // PRESENT ACTIVITY VIEW CONTROLLER
                let activityViewController = UIActivityViewController(activityItems: [outputURL], applicationActivities: nil)
                present(activityViewController, animated: true, completion: nil)
                return
                
                //------------------------------------------------
                
                let base64 = try Data(contentsOf: urls[0], options: .mappedIfSafe).base64EncodedString()
                let password = "passwordpasswordpasswordpassword"
                encryptBase64AndName(base64: base64, name: name, password: password)
            } catch {
                fatalError()
            }
        }
    }
    
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        sendButton.isHidden = false
        dismiss(animated: true, completion: nil)
    }
    
    func hmacCompare(_ first: Data, _ second: Data) -> Bool {
        var compareKey = Data(count: Int(CC_SHA256_DIGEST_LENGTH))
        let compareKeyStatus = compareKey.withUnsafeMutableBytes { compareKeyBytes in
            SecRandomCopyBytes(kSecRandomDefault, Int(CC_SHA256_DIGEST_LENGTH), compareKeyBytes)
        }
        if compareKeyStatus != errSecSuccess {
            fatalError()
        }
        var firstHmac = Data(count: Int(CC_SHA256_DIGEST_LENGTH))
        firstHmac.withUnsafeMutableBytes { firstHmacBytes in
            first.withUnsafeBytes { firstBytes in
                compareKey.withUnsafeBytes { compareKeyBytes in
                    CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA256), compareKeyBytes, compareKey.count, firstBytes, first.count, firstHmacBytes)
                }
            }
        }
        var secondHmac = Data(count: Int(CC_SHA256_DIGEST_LENGTH))
        secondHmac.withUnsafeMutableBytes { secondHmacBytes in
            second.withUnsafeBytes { secondBytes in
                compareKey.withUnsafeBytes { compareKeyBytes in
                    CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA256), compareKeyBytes, compareKey.count, secondBytes, second.count, secondHmacBytes)
                }
            }
        }
        return firstHmac == secondHmac
    }
    
    func encryptBase64AndName(base64: String, name: String, password: String) {
        activityIndicator.startAnimating()
        let toEncrypt = base64 + "$$$$$$$$" + name
        let toEncryptData = toEncrypt.data(using: .utf8)!
        let passwordData = password.data(using: .utf8)!
        var saltData = Data(count: Int(CC_SHA512_DIGEST_LENGTH))
        let saltStatus = saltData.withUnsafeMutableBytes { saltBytes in
            SecRandomCopyBytes(kSecRandomDefault, Int(CC_SHA512_DIGEST_LENGTH), saltBytes)
        }
        if saltStatus != errSecSuccess {
            fatalError()
        }
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
        let keySize = encryptionKey.count
        if keySize != kCCKeySizeAES256 {
            fatalError()
        }
        let ivSize = kCCBlockSizeAES128
        let encryptedSize = size_t(toEncryptData.count + kCCBlockSizeAES128 + ivSize)
        var encryptedData = Data(count: encryptedSize)
        let ivStatus = encryptedData.withUnsafeMutableBytes { ivBytes in
            SecRandomCopyBytes(kSecRandomDefault, ivSize, ivBytes)
        }
        if ivStatus != errSecSuccess {
            fatalError()
        }
        var numBytesEncrypted: size_t = 0
        let encryptionStatus = encryptedData.withUnsafeMutableBytes { encryptedBytes in
            toEncryptData.withUnsafeBytes { toEncryptDataBytes in
                encryptionKey.withUnsafeBytes { encryptionKeyBytes in
                    CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding), encryptionKeyBytes, keySize, encryptedBytes, toEncryptDataBytes, toEncryptData.count, encryptedBytes + ivSize, encryptedSize, &numBytesEncrypted)
                }
            }
        }
        if encryptionStatus != kCCSuccess {
            fatalError()
        }
        encryptedData.count = numBytesEncrypted + ivSize
        var authenticatedData = Data(count: Int(CC_SHA256_DIGEST_LENGTH))
        authenticatedData.withUnsafeMutableBytes { authenticatedBytes in
            encryptedData.withUnsafeBytes { encryptedBytes in
                authenticationKey.withUnsafeBytes { authenticationKeyBytes in
                    CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA256), authenticationKeyBytes, authenticationKey.count, encryptedBytes, encryptedData.count, authenticatedBytes)
                }
            }
        }
        if socket.status == .connected {
            requestSendSocketIO(encrypted: encryptedData.base64EncodedString(), authenticated: authenticatedData.base64EncodedString(), salt: saltData.base64EncodedString())
        } else {
            activityIndicator.stopAnimating()
            sendButton.isHidden = false
            showSocketIOConnectionAlert()
        }
    }
}
