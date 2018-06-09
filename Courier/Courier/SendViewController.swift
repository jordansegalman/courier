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
import CryptoSwift
import Security

class SendViewController: UIViewController, UIImagePickerControllerDelegate, UINavigationControllerDelegate, UIDocumentPickerDelegate {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
    }
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo
        info: [String : Any]) {
        dismiss(animated: true, completion: nil)
        if info[UIImagePickerControllerMediaType] as! CFString == kUTTypeImage {
            if picker.sourceType == .camera {
                var base64: String = ""
                if let originalImage = info[UIImagePickerControllerOriginalImage] as? UIImage {
                    base64 = UIImagePNGRepresentation(originalImage)!.base64EncodedString()
                } else if let editedImage = info[UIImagePickerControllerEditedImage] as? UIImage {
                    base64 = UIImagePNGRepresentation(editedImage)!.base64EncodedString()
                }
                let decodedData: Data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters)!
                let decodedImage = UIImage(data: decodedData)!
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAsset(from: decodedImage)
                }) { saved, error in
                    if saved {
                        let alertController = UIAlertController(title: "Photo Successfully Saved", message: nil, preferredStyle: .alert)
                        alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
                        self.present(alertController, animated: true, completion: nil)
                    } else {
                        let alertController = UIAlertController(title: "Failed to Save Photo", message: nil, preferredStyle: .alert)
                        alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
                        self.present(alertController, animated: true, completion: nil)
                    }
                }
            } else {
                if let imageURL = info[UIImagePickerControllerImageURL] as? URL {
                    do {
                        let name = imageURL.lastPathComponent
                        let base64 = try Data(contentsOf: imageURL, options: .mappedIfSafe).base64EncodedString()
                        let decodedData: Data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters)!
                        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(name)
                        try decodedData.write(to: fileURL, options: .atomicWrite)
                        PHPhotoLibrary.shared().performChanges({
                            PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: fileURL)
                        }) { saved, error in
                            if saved {
                                let alertController = UIAlertController(title: "Photo Successfully Saved", message: nil, preferredStyle: .alert)
                                alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
                                self.present(alertController, animated: true, completion: nil)
                            } else {
                                let alertController = UIAlertController(title: "Failed to Save Photo", message: nil, preferredStyle: .alert)
                                alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
                                self.present(alertController, animated: true, completion: nil)
                            }
                            do {
                                try FileManager.default.removeItem(at: fileURL)
                            } catch {
                                fatalError()
                            }
                        }
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
                    let decodedData: Data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters)!
                    let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(name)
                    try decodedData.write(to: fileURL, options: .atomicWrite)
                    PHPhotoLibrary.shared().performChanges({
                        PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
                    }) { saved, error in
                        if saved {
                            let alertController = UIAlertController(title: "Video Successfully Saved", message: nil, preferredStyle: .alert)
                            alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
                            self.present(alertController, animated: true, completion: nil)
                        } else {
                            let alertController = UIAlertController(title: "Failed to Save Video", message: nil, preferredStyle: .alert)
                            alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
                            self.present(alertController, animated: true, completion: nil)
                        }
                        do {
                            try FileManager.default.removeItem(at: fileURL)
                        } catch {
                            fatalError()
                        }
                    }
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
                var ivBytes = Data(count: 12)
                let result = ivBytes.withUnsafeMutableBytes {
                    SecRandomCopyBytes(kSecRandomDefault, 12, $0)
                }
                if result == errSecSuccess {
                    let password = Array("password".utf8)
                    var saltBytes = Data(count: 64)
                    let result = saltBytes.withUnsafeMutableBytes {
                        SecRandomCopyBytes(kSecRandomDefault, 64, $0)
                    }
                    if result == errSecSuccess {
                        let salt = Array(saltBytes.toHexString().utf8)
                        let hash = try PKCS5.PBKDF2(password: password, salt: salt, iterations: 4096, keyLength: 32, variant: .sha512).calculate()
                        let iv = Array(ivBytes.toHexString().utf8)
                        let gcm1 = GCM(iv: iv, mode: .combined)
                        let aes1 = try AES(key: hash, blockMode: gcm1, padding: .noPadding)
                        let encrypted = try aes1.encrypt(Array(base64.utf8))
                        let gcm2 = GCM(iv: iv, mode: .combined)
                        let aes2 = try AES(key: hash, blockMode: gcm2, padding: .noPadding)
                        let decrypted = try aes2.decrypt(encrypted)
                        let decodedData: Data = Data(base64Encoded: String(data: Data(bytes: decrypted), encoding: .utf8)!, options: .ignoreUnknownCharacters)!
                        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(name)
                        try decodedData.write(to: fileURL, options: .atomicWrite)
                        let activityViewController = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
                        present(activityViewController, animated: true, completion: nil)
                    }
                }
            } catch {
                fatalError()
            }
        }
    }
    
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        dismiss(animated: true, completion: nil)
    }
    
    @IBAction func sendButtonClicked(_ sender: UIButton) {
        let actionSheet = UIAlertController(title: "Send Something", message: "Choose something to send...", preferredStyle: .actionSheet)
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            actionSheet.addAction(UIAlertAction(title: "Camera", style: .default, handler: { (UIAlertAction) in
                self.checkPermissions(sourceType: .camera)
            }))
        }
        if UIImagePickerController.isSourceTypeAvailable(.photoLibrary) {
            actionSheet.addAction(UIAlertAction(title: "Photo Library", style: .default, handler: { (UIAlertAction) in
                self.checkPermissions(sourceType: .photoLibrary)
            }))
        }
        actionSheet.addAction(UIAlertAction(title: "File", style: .default, handler: { (UIAlertAction) in
            self.openDocument()
        }))
        actionSheet.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        present(actionSheet, animated: true, completion: nil)
    }
    
    func checkPermissions(sourceType: UIImagePickerControllerSourceType) {
        if sourceType == .camera {
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                switch AVCaptureDevice.authorizationStatus(for: .audio) {
                case .authorized:
                    openCamera()
                case .denied:
                    let alertController = UIAlertController(title: "Courier does not have permission to access the microphone.", message: nil, preferredStyle: .alert)
                    alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: { (alertController) in
                        self.openCamera()
                    }))
                    self.present(alertController, animated: true, completion: nil)
                case .notDetermined:
                    AVCaptureDevice.requestAccess(for: .audio, completionHandler: {_ in self.openCamera()
                    })
                case .restricted:
                    let alertController = UIAlertController(title: "Courier does not have permission to access the microphone.", message: nil, preferredStyle: .alert)
                    alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: { (alertController) in
                        self.openCamera()
                    }))
                    self.present(alertController, animated: true, completion: nil)
                }
            case .denied:
                showPermissionsAlert(sourceType: .camera)
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video, completionHandler: {accessGranted in
                    if accessGranted {
                        switch AVCaptureDevice.authorizationStatus(for: .audio) {
                        case .authorized:
                            self.openCamera()
                        case .denied:
                            let alertController = UIAlertController(title: "Courier does not have permission to access the microphone.", message: nil, preferredStyle: .alert)
                            alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: { (alertController) in
                                self.openCamera()
                            }))
                            self.present(alertController, animated: true, completion: nil)
                        case .notDetermined:
                            AVCaptureDevice.requestAccess(for: .audio, completionHandler: {_ in self.openCamera()
                            })
                        case .restricted:
                            let alertController = UIAlertController(title: "Courier does not have permission to access the microphone.", message: nil, preferredStyle: .alert)
                            alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: { (alertController) in
                                self.openCamera()
                            }))
                            self.present(alertController, animated: true, completion: nil)
                        }
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
    
    func showPermissionsAlert(sourceType: UIImagePickerControllerSourceType) {
        var alertTitle: String = ""
        if sourceType == .camera {
            alertTitle = "Courier does not have permission to access the camera. Please allow access to the camera in Settings."
        } else if sourceType == .photoLibrary {
            alertTitle = "Courier does not have permission to access your photo library. Please allow access to your photo library in Settings."
        }
        let permissionsAlertController = UIAlertController(title: alertTitle, message: nil, preferredStyle: .alert)
        permissionsAlertController.addAction(UIAlertAction(title: "Settings", style: .default, handler: { (permissionsAlertController) in
            UIApplication.shared.open(URL(string: UIApplicationOpenSettingsURLString)!, options: [:], completionHandler: nil)
            }))
        permissionsAlertController.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        present(permissionsAlertController, animated: true, completion: nil)
    }
}
