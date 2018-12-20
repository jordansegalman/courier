import UIKit
import MobileCoreServices
import Photos
import SocketIO

class SendViewController: UIViewController, UIImagePickerControllerDelegate, UINavigationControllerDelegate, UIDocumentPickerDelegate {
    @IBOutlet weak var sendButton: UIButton!
    @IBOutlet weak var keyLabel: UILabel!
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
    @IBOutlet weak var progressBar: UIProgressView!
    
    // Sender specific transfer data
    struct Transfer {
        var url: URL                        // Input file URL
        var bytesSent: UInt64               // Number of bytes sent
        var fileSize: UInt64?               // File size
        var inputStream: InputStream?       // File input stream
        var hmacContext: CCHmacContext?     // Sender HMAC context
        var cryptorRef: CCCryptorRef?       // Sender cryptor ref
    }
    
    var sendSocketManager: SocketManager!   // Socket.IO socket manager
    var sendSocket: SocketIOClient!         // Socket.IO socket
    static var sending: Bool = false        // True if currently sending, false if not
    private static var transfer: Transfer!  // Current transfer data
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Initialize Socket.IO
        initializeSocketIO()
    }
    
    // Initializes Socket.IO socket manager and socket with server address
    func initializeSocketIO() {
        sendSocketManager = SocketManager(socketURL: Constants.serverAddress)
        sendSocket = sendSocketManager.defaultSocket
    }
    
    // Sets up Socket.IO event handlers and connects to server
    func setupSocketIO() {
        // Called when client connects to server
        sendSocket.on(clientEvent: .connect) { data, ack in
            // Begin sending process
            self.beginSend()
        }
        // Called when client disconnects from server
        sendSocket.on(clientEvent: .disconnect) { data, ack in
        }
        // Called when client has an error
        sendSocket.on(clientEvent: .error) { data, ack in
            // Terminate Socket.IO
            self.terminateSocketIO()
            // Reset sending process
            self.resetSend()
            self.activityIndicator.stopAnimating()
            self.sendButton.isHidden = false
            // Show Socket.IO connection alert
            self.showSocketIOConnectionAlert()
        }
        // Called when receiver requests sender to start sending data
        sendSocket.on("requestStartSend") { data, ack in
            // Start sending process
            self.keyLabel.isHidden = true
            self.keyLabel.text = ""
            self.activityIndicator.startAnimating()
            self.progressBar.isHidden = false
            UIApplication.shared.isIdleTimerDisabled = true
            // Show password creation alert
            self.showPasswordCreationAlert(ack: ack)
        }
        // Called when receiver requests sender to send additional data
        sendSocket.on("requestSend") { data, ack in
            self.send(ack: ack)
        }
        // Called when receiver successfully received all data and notifies sender
        sendSocket.on("received") { data, ack in
            // Terminate sending process
            self.terminateSend()
            UIApplication.shared.isIdleTimerDisabled = false
            self.progressBar.isHidden = true
            self.progressBar.setProgress(0, animated: false)
            self.activityIndicator.stopAnimating()
            // Terminate Socket.IO
            self.terminateSocketIO()
            // Reset sending process
            self.resetSend()
            self.sendButton.isHidden = false
        }
        // Connect to Socket.IO server, timeout after 5 seconds
        sendSocket.connect(timeoutAfter: 5) {
            // Terminate Socket.IO
            self.terminateSocketIO()
            // Reset sending process
            self.resetSend()
            self.activityIndicator.stopAnimating()
            self.sendButton.isHidden = false
            // Show Socket.IO connection alert
            self.showSocketIOConnectionAlert()
        }
    }
    
    // Terminates and reinitializes Socket.IO
    func terminateSocketIO() {
        // Disconnect from Socket.IO server
        sendSocket.disconnect()
        // Remove Socket.IO event handlers
        sendSocket.removeAllHandlers()
        // Reinitialize Socket.IO
        initializeSocketIO()
    }
    
    // Requests to start sending data
    func requestStartSend() {
        // Check if Socket.IO client connected to server
        if sendSocket.status == .connected {
            // If connected, emit request
            sendSocket.emitWithAck("requestStartSend", []).timingOut(after: 0) { data in
                // Get generated transaction key
                let key = data.first as! String
                // Set and show transaction key
                self.keyLabel.text = key
                self.keyLabel.isHidden = false
            }
        } else {
            // Terminate Socket.IO
            terminateSocketIO()
            // Reset sending process
            resetSend()
            sendButton.isHidden = false
            // Show Socket.IO connection alert
            showSocketIOConnectionAlert()
        }
    }
    
    // Called when send button is touched
    @IBAction func sendButtonTouched(_ sender: UIButton) {
        // If currently sending or receiving
        if SendViewController.sending || ReceiveViewController.receiving {
            // Show transfer alert
            showTransferAlert()
            return
        }
        // Set sending
        SendViewController.sending = true
        sendButton.isHidden = true
        activityIndicator.startAnimating()
        // Setup Socket.IO and connect to server
        setupSocketIO()
    }
    
    // Begins sending process
    func beginSend() {
        activityIndicator.stopAnimating()
        // Delete all files in temporary directory
        cleanTemporaryDirectory()
        // Show alert for choosing something to send
        let alertController = UIAlertController(title: "Choose Something to Send", message: nil, preferredStyle: .actionSheet)
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            alertController.addAction(UIAlertAction(title: "Camera", style: .default, handler: { (UIAlertAction) in
                // Check camera permission
                self.checkPermissions(sourceType: .camera)
            }))
        }
        if UIImagePickerController.isSourceTypeAvailable(.photoLibrary) {
            alertController.addAction(UIAlertAction(title: "Photo Library", style: .default, handler: { (UIAlertAction) in
                // Check photo library permission
                self.checkPermissions(sourceType: .photoLibrary)
            }))
        }
        alertController.addAction(UIAlertAction(title: "Files", style: .default, handler: { (UIAlertAction) in
            // Open file
            self.openDocument()
        }))
        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { (UIAlertAction) in
            // Terminate Socket.IO
            self.terminateSocketIO()
            // Reset sending process
            self.resetSend()
            self.sendButton.isHidden = false
        }))
        present(alertController, animated: true, completion: nil)
    }
    
    // Deletes all files in temporary directory
    func cleanTemporaryDirectory() {
        do {
            // Get contents of temporary directory
            let temporaryDirectoryContents = try FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path)
            // For each file in temporary directory
            try temporaryDirectoryContents.forEach { file in
                // Get file URL
                let url = FileManager.default.temporaryDirectory.appendingPathComponent(file)
                // Delete file
                try FileManager.default.removeItem(at: url)
            }
        } catch {
            fatalError()
        }
    }
    
    // Shows alert for transfer currently in progress
    func showTransferAlert() {
        let transferAlertController = UIAlertController(title: "Another transfer is currently in progress.", message: nil, preferredStyle: .alert)
        transferAlertController.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        present(transferAlertController, animated: true, completion: nil)
    }
    
    // Shows alert for not connected to Socket.IO server
    func showSocketIOConnectionAlert() {
        let socketIOConnectionAlertController = UIAlertController(title: "Not Connected", message: nil, preferredStyle: .alert)
        socketIOConnectionAlertController.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        present(socketIOConnectionAlertController, animated: true, completion: nil)
    }
    
    // Checks permissions for camera or photo library
    func checkPermissions(sourceType: UIImagePickerController.SourceType) {
        if sourceType == .camera {
            // Check camera permission
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                // Check microphone permission
                checkMicrophonePermissions()
            case .denied:
                // Show permissions alert
                showPermissionsAlert(sourceType: .camera)
            case .notDetermined:
                // Request camera permission
                AVCaptureDevice.requestAccess(for: .video, completionHandler: { accessGranted in
                    if accessGranted {
                        // Check microphone permission
                        self.checkMicrophonePermissions()
                    }
                })
            case .restricted:
                // Show permissions alert
                showPermissionsAlert(sourceType: .camera)
            }
        } else if sourceType == .photoLibrary {
            // Check photo library permission
            switch PHPhotoLibrary.authorizationStatus() {
            case .authorized:
                // Open photo library
                openPhotoLibrary()
            case .denied:
                // Show permissions alert
                showPermissionsAlert(sourceType: .photoLibrary)
            case .notDetermined:
                // Request photo library permission
                PHPhotoLibrary.requestAuthorization({ (status) in
                    if status == PHAuthorizationStatus.authorized {
                        // Open photo library
                        self.openPhotoLibrary()
                    }
                })
            case .restricted:
                // Show permissions alert
                showPermissionsAlert(sourceType: .photoLibrary)
            }
        }
    }
    
    // Checks permission for microphone
    func checkMicrophonePermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            // Open camera
            openCamera()
        case .denied:
            // Show microphone permissions alert
            showMicrophonePermissionsAlert()
        case .notDetermined:
            // Request microphone permission
            AVCaptureDevice.requestAccess(for: .audio, completionHandler: {_ in
                // Open camera
                self.openCamera()
            })
        case .restricted:
            // Show microphone permissions alert
            showMicrophonePermissionsAlert()
        }
    }
    
    // Shows alert for no camera or photo library permission
    func showPermissionsAlert(sourceType: UIImagePickerController.SourceType) {
        // Create alert
        var alertTitle: String = ""
        if sourceType == .camera {
            alertTitle = "Courier does not have permission to access the camera. Please allow access to the camera in Settings."
        } else if sourceType == .photoLibrary {
            alertTitle = "Courier does not have permission to access your photo library. Please allow access to your photo library in Settings."
        }
        let permissionsAlertController = UIAlertController(title: alertTitle, message: nil, preferredStyle: .alert)
        // Add action for opening Settings
        permissionsAlertController.addAction(UIAlertAction(title: "Settings", style: .default, handler: { (permissionsAlertController) in
            UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!, options: Dictionary(uniqueKeysWithValues: [:].map { key, value in (UIApplication.OpenExternalURLOptionsKey(rawValue: key), value)}), completionHandler: nil)
        }))
        // Add action for cancelling
        permissionsAlertController.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        // Terminate Socket.IO
        terminateSocketIO()
        // Reset sending process
        resetSend()
        sendButton.isHidden = false
        present(permissionsAlertController, animated: true, completion: nil)
    }
    
    // Shows alert for no microphone permission
    func showMicrophonePermissionsAlert() {
        // Create alert
        let microphonePermissionsAlertController = UIAlertController(title: "Courier does not have permission to access the microphone.", message: nil, preferredStyle: .alert)
        microphonePermissionsAlertController.addAction(UIAlertAction(title: "OK", style: .default, handler: { (alertController) in
            // Open camera without microphone
            self.openCamera()
        }))
        present(microphonePermissionsAlertController, animated: true, completion: nil)
    }
    
    // Opens the camera
    func openCamera() {
        let imagePickerController = UIImagePickerController()
        imagePickerController.sourceType = .camera
        imagePickerController.mediaTypes = UIImagePickerController.availableMediaTypes(for: .camera)!
        imagePickerController.allowsEditing = false
        imagePickerController.delegate = self
        present(imagePickerController, animated: true, completion: nil)
    }
    
    // Opens the photo library
    func openPhotoLibrary() {
        let imagePickerController = UIImagePickerController()
        imagePickerController.sourceType = .photoLibrary
        imagePickerController.mediaTypes = UIImagePickerController.availableMediaTypes(for: .photoLibrary)!
        imagePickerController.allowsEditing = false
        imagePickerController.delegate = self
        present(imagePickerController, animated: true, completion: nil)
    }
    
    // Opens the document picker
    func openDocument() {
        let documentPickerController = UIDocumentPickerViewController(documentTypes: [kUTTypeItem as String], in: .import)
        documentPickerController.allowsMultipleSelection = false
        documentPickerController.modalPresentationStyle = .fullScreen
        documentPickerController.delegate = self
        present(documentPickerController, animated: true, completion: nil)
    }
    
    // Handles photo or video picked
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        let info = Dictionary(uniqueKeysWithValues: info.map {key, value in (key.rawValue, value)})
        dismiss(animated: true, completion: nil)
        if info[UIImagePickerController.InfoKey.mediaType.rawValue] as! CFString == kUTTypeImage {
            // If picked image
            if picker.sourceType == .camera {
                // From camera
                let name = UUID().uuidString + ".png"
                let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
                // Get image URL
                if let originalImage = info[UIImagePickerController.InfoKey.originalImage.rawValue] as? UIImage {
                    do {
                        try originalImage.pngData()!.write(to: url, options: .atomic)
                        
                    } catch {
                        fatalError()
                    }
                } else if let editedImage = info[UIImagePickerController.InfoKey.editedImage.rawValue] as? UIImage {
                    do {
                        try editedImage.pngData()!.write(to: url, options: .atomic)
                    } catch {
                        fatalError()
                    }
                }
                // Create transfer object with image URL
                SendViewController.transfer = Transfer(url: url, bytesSent: 0, fileSize: nil, inputStream: nil, hmacContext: nil, cryptorRef: nil)
                // Request to start sending data
                requestStartSend()
            } else {
                // From photo library
                if let imageURL = info[UIImagePickerController.InfoKey.imageURL.rawValue] as? URL {
                    // Create transfer object with image URL
                    SendViewController.transfer = Transfer(url: imageURL, bytesSent: 0, fileSize: nil, inputStream: nil, hmacContext: nil, cryptorRef: nil)
                    // Request to start sending data
                    requestStartSend()
                }
            }
        }
        if info[UIImagePickerController.InfoKey.mediaType.rawValue] as! CFString == kUTTypeMovie {
            // If picked video
            if let mediaURL = info[UIImagePickerController.InfoKey.mediaURL.rawValue] as? URL {
                // Create transfer object with video URL
                SendViewController.transfer = Transfer(url: mediaURL, bytesSent: 0, fileSize: nil, inputStream: nil, hmacContext: nil, cryptorRef: nil)
                // Request to start sending data
                requestStartSend()
            }
        }
    }
    
    // Handles image picker cancelled
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        // Terminate Socket.IO
        terminateSocketIO()
        // Reset sending process
        resetSend()
        sendButton.isHidden = false
        dismiss(animated: true, completion: nil)
    }
    
    // Handles document picked
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        dismiss(animated: true, completion: nil)
        if urls.count == 1 {
            // Create transfer object with document URL
            SendViewController.transfer = Transfer(url: urls.first!, bytesSent: 0, fileSize: nil, inputStream: nil, hmacContext: nil, cryptorRef: nil)
            // Request to start sending data
            requestStartSend()
        }
    }
    
    // Handles document picker cancelled
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        // Terminate Socket.IO
        terminateSocketIO()
        // Reset sending process
        resetSend()
        sendButton.isHidden = false
        dismiss(animated: true, completion: nil)
    }
    
    // Shows alert for transfer password creation
    func showPasswordCreationAlert(ack: SocketAckEmitter) {
        // Create alert
        let passwordCreationAlertController = UIAlertController(title: "Create Password for File", message: nil, preferredStyle: .alert)
        passwordCreationAlertController.addTextField { (textField) in
            textField.placeholder = "Password"
            textField.isSecureTextEntry = true
        }
        passwordCreationAlertController.addTextField { (textField) in
            textField.placeholder = "Confirm Password"
            textField.isSecureTextEntry = true
        }
        // Add action for finished creating password
        passwordCreationAlertController.addAction(UIAlertAction(title: "OK", style: .default, handler: { (UIAlertAction) in
            let password = passwordCreationAlertController.textFields![0].text
            let confirmPassword = passwordCreationAlertController.textFields![1].text
            // Check that password and confirm password are the same
            if password == confirmPassword {
                if !password!.isEmpty {
                    // Initialize sending process
                    self.initializeSend(password: password!, ack: ack)
                } else {
                    // Show password cannot be empty alert
                    self.showPasswordCannotBeEmptyAlert(ack: ack)
                }
            } else {
                // Show passwords did not match alert
                self.showPasswordsDidNotMatchAlert(ack: ack)
            }
        }))
        // Add action for cancelling password creation
        passwordCreationAlertController.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { (UIAlertAction) in
            UIApplication.shared.isIdleTimerDisabled = false
            self.progressBar.isHidden = true
            self.progressBar.setProgress(0, animated: false)
            self.activityIndicator.stopAnimating()
            // Terminate Socket.IO
            self.terminateSocketIO()
            // Reset sending process
            self.resetSend()
            self.sendButton.isHidden = false
        }))
        present(passwordCreationAlertController, animated: true, completion: nil)
    }
    
    // Shows alert for passwords did not match
    func showPasswordsDidNotMatchAlert(ack: SocketAckEmitter) {
        let passwordsDidNotMatchAlertController = UIAlertController(title: "Passwords Did Not Match", message: nil, preferredStyle: .alert)
        passwordsDidNotMatchAlertController.addAction(UIAlertAction(title: "OK", style: .default, handler: { (UIAlertAction) in
            self.showPasswordCreationAlert(ack: ack)
        }))
        present(passwordsDidNotMatchAlertController, animated: true, completion: nil)
    }
    
    // Shows alert for password cannot be empty
    func showPasswordCannotBeEmptyAlert(ack: SocketAckEmitter) {
        let passwordCannotBeEmptyAlertController = UIAlertController(title: "Password Cannot Be Empty", message: nil, preferredStyle: .alert)
        passwordCannotBeEmptyAlertController.addAction(UIAlertAction(title: "OK", style: .default, handler: { (UIAlertAction) in
            self.showPasswordCreationAlert(ack: ack)
        }))
        present(passwordCannotBeEmptyAlertController, animated: true, completion: nil)
    }
    
    // Initializes encryption, authentication, and file input stream, then replies to receiver with salt, initialization vector, and encrypted file name
    func initializeSend(password: String, ack: SocketAckEmitter) {
        // Get file size
        let url = SendViewController.transfer.url
        do {
            let attr = try FileManager.default.attributesOfItem(atPath: url.path)
            SendViewController.transfer.fileSize = attr[.size] as? UInt64
        } catch {
            fatalError()
        }
        let passwordData = password.data(using: .utf8)!
        // Generate 512-bit secure pseudorandom salt
        var saltData = Data(count: Int(CC_SHA512_DIGEST_LENGTH))
        let saltStatus = saltData.withUnsafeMutableBytes { saltBytes in
            SecRandomCopyBytes(kSecRandomDefault, Int(CC_SHA512_DIGEST_LENGTH), saltBytes)
        }
        if saltStatus != errSecSuccess {
            fatalError()
        }
        // Create 512-bit key using PBKDF2 with HMAC-SHA512 as PRF, Constants.PBKDF2Iterations iterations, 512-bit salt, and password
        var keyData = Data(count: Int(CC_SHA512_DIGEST_LENGTH))
        let derivationStatus = keyData.withUnsafeMutableBytes { keyBytes in
            saltData.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), password, passwordData.count, saltBytes, Int(CC_SHA512_DIGEST_LENGTH), CCPBKDFAlgorithm(kCCPRFHmacAlgSHA512), Constants.PBKDF2Iterations, keyBytes, Int(CC_SHA512_DIGEST_LENGTH))
            }
        }
        if derivationStatus != kCCSuccess {
            fatalError()
        }
        // Get 256-bit encryption key from first half of 512-bit key
        let encryptionKey = keyData.subdata(in: 0..<(Int(CC_SHA512_DIGEST_LENGTH) / 2))
        // Get 256-bit HMAC key from second half of 512-bit key
        let hmacKey = keyData.subdata(in: (Int(CC_SHA512_DIGEST_LENGTH) / 2)..<Int(CC_SHA512_DIGEST_LENGTH))
        let keySize = encryptionKey.count
        if keySize != kCCKeySizeAES256 {
            fatalError()
        }
        // Initialize sender HMAC context for HMAC-SHA256
        SendViewController.transfer.hmacContext = CCHmacContext()
        hmacKey.withUnsafeBytes {
            CCHmacInit(&SendViewController.transfer.hmacContext!, CCHmacAlgorithm(kCCHmacAlgSHA256), $0, hmacKey.count)
        }
        // Generate secure pseudorandom initialization vector for 128-bit AES block size
        let ivSize = kCCBlockSizeAES128
        var ivData = Data(count: ivSize)
        let ivStatus = ivData.withUnsafeMutableBytes { ivBytes in
            SecRandomCopyBytes(kSecRandomDefault, ivSize, ivBytes)
        }
        if ivStatus != errSecSuccess {
            fatalError()
        }
        // Encrypt file name
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
        // Update sender HMAC with salt, IV, and encrypted file name
        saltData.withUnsafeBytes {
            CCHmacUpdate(&SendViewController.transfer.hmacContext!, $0, saltData.count)
        }
        ivData.withUnsafeBytes {
            CCHmacUpdate(&SendViewController.transfer.hmacContext!, $0, ivData.count)
        }
        encryptedName.withUnsafeBytes {
            CCHmacUpdate(&SendViewController.transfer.hmacContext!, $0, encryptedName.count)
        }
        // Initialize sender cryptor ref for AES-256-CBC
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
        // Open file input stream
        SendViewController.transfer.inputStream = InputStream(url: url)
        SendViewController.transfer.inputStream!.open()
        // Reply to receiver with salt, initialization vector, and encrypted file name
        ack.with(["salt": saltData.base64EncodedString(), "iv": ivData.base64EncodedString(), "encryptedName": encryptedName.base64EncodedString()])
    }
    
    // Encrypts and authenticates additional data from file input stream, then replies to receiver with encrypted data and transfer progress or HMAC hash
    func send(ack: SocketAckEmitter) {
        var inputData = Data(count: Constants.inputStreamReadBytes)
        let inputLength = inputData.count
        var encryptedData = Data()
        // Check if file input stream has bytes available
        if SendViewController.transfer.inputStream!.hasBytesAvailable {
            // Read Constants.inputStreamReadBytes bytes of input stream data
            let result = inputData.withUnsafeMutableBytes { inputBytes in
                SendViewController.transfer.inputStream!.read(inputBytes, maxLength: inputLength)
            }
            if result == -1 {
                fatalError()
            }
            // Encrypt input stream data
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
            // Update sender HMAC with encrypted data
            encryptedData.withUnsafeBytes {
                CCHmacUpdate(&SendViewController.transfer.hmacContext!, $0, encryptedData.count)
            }
            // Update number of bytes sent and get transfer progress
            SendViewController.transfer.bytesSent += UInt64(inputData.count)
            if SendViewController.transfer.bytesSent > SendViewController.transfer.fileSize! {
                SendViewController.transfer.bytesSent = SendViewController.transfer.fileSize!
            }
            let progress = Float(SendViewController.transfer.bytesSent) / Float(SendViewController.transfer.fileSize!)
            // Update progress bar
            progressBar.setProgress(progress, animated: true)
            // Reply to receiver with encrypted data and transfer progress
            ack.with(["encryptedData": encryptedData.base64EncodedString(), "progress": String(progress)])
        } else {
            // Finalize encryption
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
            // Generate sender HMAC hash
            var trustedHmac = Data(count: Int(CC_SHA256_DIGEST_LENGTH))
            trustedHmac.withUnsafeMutableBytes {
                CCHmacFinal(&SendViewController.transfer.hmacContext!, $0)
            }
            // Reply to receiver with HMAC hash
            ack.with(["trustedHmac": trustedHmac.base64EncodedString()])
        }
    }
    
    // Releases cryptor ref and closes file input stream
    func terminateSend() {
        CCCryptorRelease(SendViewController.transfer.cryptorRef!)
        SendViewController.transfer.inputStream!.close()
    }
    
    // Sets not sending and sets transfer object to nil
    func resetSend() {
        SendViewController.sending = false
        SendViewController.transfer = nil
    }
}
