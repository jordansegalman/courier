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
    @IBOutlet weak var progressBar: UIProgressView!
    
    struct Transfer {
        var url: URL
        var fileSize: UInt64?
        var inputStream: InputStream?
        var hmacContext: CCHmacContext?
        var cryptorRef: CCCryptorRef?
    }
    
    let sendSocketManager = SocketManager(socketURL: URL(string: "http://127.0.0.1")!)
    var sendSocket: SocketIOClient!
    static var sending: Bool = false
    private static var transfer: Transfer!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        sendSocket = sendSocketManager.defaultSocket
    }
    
    func initializeSocketIO() {
        sendSocket.on(clientEvent: .connect) { data, ack in
            print("Socket.IO connected")
            self.requestStartSend()
        }
        sendSocket.on(clientEvent: .disconnect) { data, ack in
            print("Socket.IO disconnected")
        }
        sendSocket.on("requestStartSend") { data, ack in
            self.keyLabel.isHidden = true
            self.keyLabel.text = ""
            self.activityIndicator.startAnimating()
            self.progressBar.isHidden = false
            UIApplication.shared.isIdleTimerDisabled = true
            self.initializeSend(ack: ack)
        }
        sendSocket.on("requestSend") { data, ack in
            self.send(ack: ack)
        }
        sendSocket.on("received") { data, ack in
            self.terminateSend()
            self.cleanTemporaryDirectory()
            UIApplication.shared.isIdleTimerDisabled = false
            self.progressBar.isHidden = true
            self.progressBar.setProgress(0, animated: false)
            self.activityIndicator.stopAnimating()
            self.terminateSocketIO()
            self.resetSend()
            self.sendButton.isHidden = false
        }
        sendSocket.connect()
    }
    
    func terminateSocketIO() {
        sendSocket.disconnect()
        sendSocket.removeAllHandlers()
    }
    
    func requestStartSend() {
        if sendSocket.status == .connected {
            sendSocket.emitWithAck("requestStartSend", []).timingOut(after: 0) { data in
                SendViewController.sending = true
                let key = data.first as! String
                self.keyLabel.text = key
                self.keyLabel.isHidden = false
            }
        } else {
            terminateSocketIO()
            resetSend()
            sendButton.isHidden = false
            showSocketIOConnectionAlert()
        }
    }
    
    @IBAction func sendButtonTouched(_ sender: UIButton) {
        if SendViewController.sending || ReceiveViewController.receiving {
            showTransferAlert()
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
    
    func showTransferAlert() {
        let socketIOConnectionAlertController = UIAlertController(title: "Another transfer is currently in progress.", message: nil, preferredStyle: .alert)
        socketIOConnectionAlertController.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        present(socketIOConnectionAlertController, animated: true, completion: nil)
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
                let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
                if let originalImage = info[UIImagePickerControllerOriginalImage] as? UIImage {
                    do {
                        try UIImagePNGRepresentation(originalImage)!.write(to: url, options: .atomic)

                    } catch {
                        fatalError()
                    }
                } else if let editedImage = info[UIImagePickerControllerEditedImage] as? UIImage {
                    do {
                        try UIImagePNGRepresentation(editedImage)!.write(to: url, options: .atomic)
                    } catch {
                        fatalError()
                    }
                }
                SendViewController.transfer = Transfer(url: url, fileSize: nil, inputStream: nil, hmacContext: nil, cryptorRef: nil)
                initializeSocketIO()
            } else {
                if let imageURL = info[UIImagePickerControllerImageURL] as? URL {
                    SendViewController.transfer = Transfer(url: imageURL, fileSize: nil, inputStream: nil, hmacContext: nil, cryptorRef: nil)
                    initializeSocketIO()
                }
            }
        }
        if info[UIImagePickerControllerMediaType] as! CFString == kUTTypeMovie {
            if let mediaURL = info[UIImagePickerControllerMediaURL] as? URL {
                SendViewController.transfer = Transfer(url: mediaURL, fileSize: nil, inputStream: nil, hmacContext: nil, cryptorRef: nil)
                initializeSocketIO()
            }
        }
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        terminateSocketIO()
        sendButton.isHidden = false
        dismiss(animated: true, completion: nil)
    }
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        dismiss(animated: true, completion: nil)
        if urls.count == 1 {
            SendViewController.transfer = Transfer(url: urls.first!, fileSize: nil, inputStream: nil, hmacContext: nil, cryptorRef: nil)
            initializeSocketIO()
        }
    }
    
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        terminateSocketIO()
        sendButton.isHidden = false
        dismiss(animated: true, completion: nil)
    }
    
    func initializeSend(ack: SocketAckEmitter) {
        // GET FILESIZE
        let url = SendViewController.transfer.url
        do {
            let attr = try FileManager.default.attributesOfItem(atPath: url.path)
            SendViewController.transfer.fileSize = attr[.size] as? UInt64
        } catch {
            fatalError()
        }
        // GENERATE SALT, ENCRYPTION KEY, HMAC KEY, AND IV
        let password: String = "passwordpasswordpasswordpassword"
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
        let hmacKey = keyData.subdata(in: (Int(CC_SHA512_DIGEST_LENGTH) / 2)..<Int(CC_SHA512_DIGEST_LENGTH))
        let keySize = encryptionKey.count
        if keySize != kCCKeySizeAES256 {
            fatalError()
        }
        SendViewController.transfer.hmacContext = CCHmacContext()
        hmacKey.withUnsafeBytes {
            CCHmacInit(&SendViewController.transfer.hmacContext!, CCHmacAlgorithm(kCCHmacAlgSHA256), $0, hmacKey.count)
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
        let name = url.lastPathComponent
        let nameData = name.data(using: .utf8)!
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
            CCHmacUpdate(&SendViewController.transfer.hmacContext!, $0, saltData.count)
        }
        ivData.withUnsafeBytes {
            CCHmacUpdate(&SendViewController.transfer.hmacContext!, $0, ivData.count)
        }
        encryptedName.withUnsafeBytes {
            CCHmacUpdate(&SendViewController.transfer.hmacContext!, $0, encryptedName.count)
        }
        // SETUP CRYPTORS
        SendViewController.transfer.cryptorRef = encryptionKey.withUnsafeBytes { (encryptionKeyBytes: UnsafePointer<UInt8>) in
            ivData.withUnsafeBytes { (ivBytes: UnsafePointer<UInt8>) in
                var cryptorRefOut: CCCryptorRef?
                let result = CCCryptorCreate(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding), encryptionKeyBytes, encryptionKey.count, ivBytes, &cryptorRefOut)
                if result != kCCSuccess {
                    fatalError()
                }
                return cryptorRefOut
            }
        }
        // OPEN STREAMS
        SendViewController.transfer.inputStream = InputStream(url: url)
        SendViewController.transfer.inputStream!.open()
        // SEND SALT, IV, AND ENCRYPTED NAME TO RECEIVER
        ack.with(["salt": saltData.base64EncodedString(), "iv": ivData.base64EncodedString(), "encryptedName": encryptedName.base64EncodedString()])
    }
    
    func send(ack: SocketAckEmitter) {
        var inputData = Data(count: 1048576)
        let inputLength = inputData.count
        var encryptedData = Data()
        if SendViewController.transfer.inputStream!.hasBytesAvailable {
            let result = inputData.withUnsafeMutableBytes { inputBytes in
                SendViewController.transfer.inputStream!.read(inputBytes, maxLength: inputLength)
            }
            if result == -1 {
                fatalError()
            }
            // ENCRYPT UPDATED DATA
            let encryptedOutputLength = CCCryptorGetOutputLength(SendViewController.transfer.cryptorRef!, inputData.count, false)
            encryptedData.count = encryptedOutputLength
            var encryptedOutputMoved = 0
            let updateResult = inputData.withUnsafeBytes { inputBytes in
                encryptedData.withUnsafeMutableBytes { encryptedBytes in
                    CCCryptorUpdate(SendViewController.transfer.cryptorRef!, inputBytes, inputLength, encryptedBytes, encryptedOutputLength, &encryptedOutputMoved)
                }
            }
            if updateResult != kCCSuccess {
                fatalError()
            }
            encryptedData.count = encryptedOutputMoved
            encryptedData.withUnsafeBytes {
                CCHmacUpdate(&SendViewController.transfer.hmacContext!, $0, encryptedData.count)
            }
            // GET TRANSFER PROGRESS
            let progress = (SendViewController.transfer.inputStream!.property(forKey: .fileCurrentOffsetKey) as! NSNumber).floatValue / Float(SendViewController.transfer.fileSize!)
            // UPDATE PROGRESS BAR
            self.progressBar.setProgress(progress, animated: true)
            // SEND encryptedData TO RECEIVER
            ack.with(["encryptedData": encryptedData.base64EncodedString(), "progress": String(progress)])
        } else {
            // ENCRYPT FINAL DATA
            let encryptedOutputLength = CCCryptorGetOutputLength(SendViewController.transfer.cryptorRef!, 0, true)
            encryptedData.count = encryptedOutputLength
            var encryptedOutputMoved = 0
            let finalResult = encryptedData.withUnsafeMutableBytes { encryptedBytes in
                CCCryptorFinal(SendViewController.transfer.cryptorRef!, encryptedBytes, encryptedOutputLength, &encryptedOutputMoved)
            }
            if finalResult != kCCSuccess {
                fatalError()
            }
            encryptedData.count = encryptedOutputMoved
            var hmac = Data(count: Int(CC_SHA256_DIGEST_LENGTH))
            hmac.withUnsafeMutableBytes {
                CCHmacFinal(&SendViewController.transfer.hmacContext!, $0)
            }
            // SEND hmac TO RECEIVER
            ack.with(["hmac": hmac.base64EncodedString()])
        }
    }
    
    func terminateSend() {
        // RELEASE CRYPTORS AND CLOSE STREAMS
        CCCryptorRelease(SendViewController.transfer.cryptorRef!)
        SendViewController.transfer.inputStream!.close()
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
    
    func resetSend() {
        SendViewController.sending = false
        SendViewController.transfer = nil
    }
}
