//
//  SendViewController.swift
//  Courier
//
//  Created by Jordan Segalman on 6/7/18.
//  Copyright © 2018 example. All rights reserved.
//

import UIKit
import MobileCoreServices
import AVFoundation
import Photos
import Security

class SendViewController: UIViewController, UIImagePickerControllerDelegate, UINavigationControllerDelegate, UIDocumentPickerDelegate {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
    }
    
    @IBAction func sendButtonClicked(_ sender: UIButton) {
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
        let imagePickerController = UIImagePickerController()
        imagePickerController.sourceType = .camera
        imagePickerController.mediaTypes = UIImagePickerController.availableMediaTypes(for: .camera)!
        imagePickerController.allowsEditing = false
        imagePickerController.delegate = self
        present(imagePickerController, animated: true, completion: nil)
    }
    
    func openPhotoLibrary() {
        let imagePickerController = UIImagePickerController()
        imagePickerController.sourceType = .photoLibrary
        imagePickerController.mediaTypes = UIImagePickerController.availableMediaTypes(for: .photoLibrary)!
        imagePickerController.allowsEditing = false
        imagePickerController.delegate = self
        present(imagePickerController, animated: true, completion: nil)
    }
    
    func openDocument() {
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
        dismiss(animated: true, completion: nil)
    }
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        dismiss(animated: true, completion: nil)
        if urls.count == 1 {
            do {
                let name = urls[0].lastPathComponent
                let base64 = try Data(contentsOf: urls[0], options: .mappedIfSafe).base64EncodedString()
                let password = "passwordpasswordpasswordpassword"
                encryptBase64AndName(base64: base64, name: name, password: password)
            } catch {
                fatalError()
            }
        }
    }
    
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        dismiss(animated: true, completion: nil)
    }
    
    func encryptBase64AndName(base64: String, name: String, password: String) {
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
        decryptBase64AndName(encrypted: encryptedData.base64EncodedString(), authenticated: authenticatedData.base64EncodedString(), salt: saltData.base64EncodedString(), password: password)
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
            fatalError()
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
        let decryptedString = String(data: decryptedData, encoding: .utf8)
        let decryptedStringArray = decryptedString!.components(separatedBy: "$$$$$$$$")
        let base64 = decryptedStringArray[0]
        let name = decryptedStringArray[1]
        createActivityViewController(base64: base64, name: name)
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
