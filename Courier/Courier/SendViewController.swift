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
    
    enum FileType {
        case camera, photo, video
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
    }
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo
        info: [String : Any]) {
        dismiss(animated: true, completion: nil)
        if let selectedImage = info[UIImagePickerControllerOriginalImage] as? UIImage {
            let base64: String = UIImagePNGRepresentation(selectedImage)!.base64EncodedString()
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
        }
        if let videoURL = info[UIImagePickerControllerMediaURL] as? URL {
            do {
                let base64 = try Data(contentsOf: videoURL, options: .mappedIfSafe).base64EncodedString()
                let decodedData: Data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters)!
                let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("temp.mov")
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
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        dismiss(animated: true, completion: nil)
    }
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
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
    
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        dismiss(animated: true, completion: nil)
    }
    
    @IBAction func sendButtonClicked(_ sender: UIButton) {
        let actionSheet = UIAlertController(title: "Send Something", message: "Choose something to send...", preferredStyle: .actionSheet)
        actionSheet.addAction(UIAlertAction(title: "Camera", style: .default, handler: { (UIAlertAction) in
            self.checkPermissions(fileType: .camera)
        }))
        actionSheet.addAction(UIAlertAction(title: "Photo", style: .default, handler: { (UIAlertAction) in
            self.checkPermissions(fileType: .photo)
        }))
        actionSheet.addAction(UIAlertAction(title: "Video", style: .default, handler: { (UIAlertAction) in
            self.checkPermissions(fileType: .video)
        }))
        actionSheet.addAction(UIAlertAction(title: "File", style: .default, handler: { (UIAlertAction) in
            self.pickFile()
        }))
        actionSheet.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        present(actionSheet, animated: true, completion: nil)
    }
    
    func checkPermissions(fileType: FileType) {
        if fileType == FileType.camera {
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
                showPermissionsAlert(fileType: fileType)
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
                showPermissionsAlert(fileType: fileType)
            }
        } else if fileType == FileType.photo {
            switch PHPhotoLibrary.authorizationStatus() {
            case .authorized:
                pickPhoto()
            case .denied:
                showPermissionsAlert(fileType: fileType)
            case .notDetermined:
                PHPhotoLibrary.requestAuthorization({ (status) in
                    if status == PHAuthorizationStatus.authorized {
                        self.pickPhoto()
                    }
                })
            case .restricted:
                showPermissionsAlert(fileType: fileType)
            }
        } else if fileType == FileType.video {
            switch PHPhotoLibrary.authorizationStatus() {
            case .authorized:
                pickVideo()
            case .denied:
                showPermissionsAlert(fileType: fileType)
            case .notDetermined:
                PHPhotoLibrary.requestAuthorization({ (status) in
                    if status == PHAuthorizationStatus.authorized {
                        self.pickVideo()
                    }
                })
            case .restricted:
                showPermissionsAlert(fileType: fileType)
            }
        }
    }
    
    func openCamera() {
        let imagePickerController = UIImagePickerController()
        imagePickerController.sourceType = .camera
        imagePickerController.mediaTypes = [kUTTypeImage as String, kUTTypeMovie as String]
        imagePickerController.delegate = self
        present(imagePickerController, animated: true, completion: nil)
    }
    
    func pickPhoto() {
        let imagePickerController = UIImagePickerController()
        imagePickerController.sourceType = .photoLibrary
        imagePickerController.delegate = self
        present(imagePickerController, animated: true, completion: nil)
    }
    
    func pickVideo() {
        let imagePickerController = UIImagePickerController()
        imagePickerController.sourceType = .photoLibrary
        imagePickerController.mediaTypes = [kUTTypeMovie as String, kUTTypeVideo as String]
        imagePickerController.delegate = self
        present(imagePickerController, animated: true, completion: nil)
    }
    
    func pickFile() {
        let documentPickerController = UIDocumentPickerViewController(documentTypes: [kUTTypeItem as String], in: .import)
        documentPickerController.modalPresentationStyle = .formSheet
        documentPickerController.delegate = self
        present(documentPickerController, animated: true, completion: nil)
    }
    
    func showPermissionsAlert(fileType: FileType) {
        var alertTitle: String = ""
        if fileType == FileType.camera {
            alertTitle = "Courier does not have permission to access the camera. Please allow access to the camera in Settings."
        } else if fileType == FileType.photo || fileType == FileType.video {
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
