import UIKit
import SocketIO

class ReceiveViewController: UIViewController {
    @IBOutlet weak var keyTextField: UITextField!
    @IBOutlet weak var receiveButton: UIButton!
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
    @IBOutlet weak var progressBar: UIProgressView!
    
    // Receiver specific transfer data
    struct Transfer {
        var key: String                     // Transaction key
        var url: URL?                       // Output file URL
        var outputStream: OutputStream?     // File output stream
        var hmacContext: CCHmacContext?     // Receiver HMAC context
        var cryptorRef: CCCryptorRef?       // Receiver cryptor ref
    }
    
    var receiveSocketManager: SocketManager!    // Socket.IO socket manager
    var receiveSocket: SocketIOClient!          // Socket.IO socket
    static var receiving: Bool = false          // True if currently receiving, false if not
    private static var transfer: Transfer!      // Current transfer data
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Add editing changed target to transaction key text field
        keyTextField.addTarget(self, action: #selector(textFieldDidChange(_:)), for: .editingChanged)
        // Initialize Socket.IO
        initializeSocketIO()
    }
    
    // Hides keyboard on touch outside key text field
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        keyTextField.resignFirstResponder()
    }
    
    // Target for key text field editing changed
    @objc func textFieldDidChange(_ textField: UITextField) {
        updateReceiveButtonState()
    }
    
    // Enables receive button if key text field contains Constants.keyLength characters
    private func updateReceiveButtonState() {
        if let key = keyTextField.text {
            receiveButton.isEnabled = !key.isEmpty && key.count == Constants.keyLength
        }
    }
    
    // Initializes Socket.IO socket manager and socket with server address
    func initializeSocketIO() {
        receiveSocketManager = SocketManager(socketURL: Constants.serverAddress)
        receiveSocket = receiveSocketManager.defaultSocket
    }
    
    // Sets up Socket.IO event handlers and connects to server
    func setupSocketIO() {
        // Called when client connects to server
        receiveSocket.on(clientEvent: .connect) { data, ack in
            // Request to start receiving data
            self.requestStartReceive()
        }
        // Called when client disconnects from server
        receiveSocket.on(clientEvent: .disconnect) { data, ack in
        }
        // Called when client has an error
        receiveSocket.on(clientEvent: .error) { data, ack in
            // Terminate Socket.IO
            self.terminateSocketIO()
            // Reset receiving process
            self.resetReceive()
            UIApplication.shared.isIdleTimerDisabled = false
            self.progressBar.isHidden = true
            self.progressBar.setProgress(0, animated: false)
            self.activityIndicator.stopAnimating()
            self.receiveButton.isHidden = false
            self.keyTextField.isHidden = false
            // Show Socket.IO connection alert
            self.showSocketIOConnectionAlert()
        }
        // Connect to Socket.IO server, timeout after 5 seconds
        receiveSocket.connect(timeoutAfter: 5) {
            // Terminate Socket.IO
            self.terminateSocketIO()
            // Reset receiving process
            self.resetReceive()
            UIApplication.shared.isIdleTimerDisabled = false
            self.progressBar.isHidden = true
            self.progressBar.setProgress(0, animated: false)
            self.activityIndicator.stopAnimating()
            self.receiveButton.isHidden = false
            self.keyTextField.isHidden = false
            // Show Socket.IO connection alert
            self.showSocketIOConnectionAlert()
        }
    }
    
    // Terminates and reinitializes Socket.IO
    func terminateSocketIO() {
        // Disconnect from Socket.IO server
        receiveSocket.disconnect()
        // Remove Socket.IO event handlers
        receiveSocket.removeAllHandlers()
        // Reinitialize Socket.IO
        initializeSocketIO()
    }
    
    // Requests to start receiving data
    func requestStartReceive() {
        // Check if Socket.IO client connected to server
        if receiveSocket.status == .connected {
            // If connected, emit request
            receiveSocket.emitWithAck("requestStartReceive", ["key": ReceiveViewController.transfer.key]).timingOut(after: 0) { data in
                // Check that response data not empty
                if data.count == 1 {
                    let dictionary = data.first as! [String: String]
                    // Show password entry alert and supply salt, IV, and encrypted file name from response data
                    self.showPasswordEntryAlert(saltData: Data(base64Encoded: dictionary["salt"]!)!, ivData: Data(base64Encoded: dictionary["iv"]!)!, encryptedName: Data(base64Encoded: dictionary["encryptedName"]!)!)
                } else {
                    // Terminate Socket.IO
                    self.terminateSocketIO()
                    // Reset receiving process
                    self.resetReceive()
                    UIApplication.shared.isIdleTimerDisabled = false
                    self.activityIndicator.stopAnimating()
                    self.receiveButton.isHidden = false
                    self.keyTextField.isHidden = false
                    // Show invalid key alert
                    self.showInvalidKeyAlert()
                }
            }
        } else {
            // Terminate Socket.IO
            terminateSocketIO()
            // Reset receiving process
            resetReceive()
            UIApplication.shared.isIdleTimerDisabled = false
            activityIndicator.stopAnimating()
            receiveButton.isHidden = false
            keyTextField.isHidden = false
            // Show Socket.IO connection alert
            showSocketIOConnectionAlert()
        }
    }
    
    // Called when receive button is touched
    @IBAction func receiveButtonTouched(_ sender: UIButton) {
        // If currently receiving or sending
        if ReceiveViewController.receiving || SendViewController.sending {
            // Show transfer alert
            showTransferAlert()
            return
        }
        // Check if key text field contains Constants.keyLength characters
        if let key = keyTextField.text, !key.isEmpty && key.count == Constants.keyLength {
            // Set receiving
            ReceiveViewController.receiving = true
            keyTextField.resignFirstResponder()
            keyTextField.isHidden = true
            keyTextField.text = ""
            receiveButton.isHidden = true
            updateReceiveButtonState()
            activityIndicator.startAnimating()
            UIApplication.shared.isIdleTimerDisabled = true
            // Create transfer object with transaction key
            ReceiveViewController.transfer = Transfer(key: key, url: nil, outputStream: nil, hmacContext: nil, cryptorRef: nil)
            // Setup Socket.IO and connect to server
            setupSocketIO()
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
    
    // Shows alert for invalid transaction key
    func showInvalidKeyAlert() {
        let invalidKeyAlertController = UIAlertController(title: "Invalid Key", message: nil, preferredStyle: .alert)
        invalidKeyAlertController.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        present(invalidKeyAlertController, animated: true, completion: nil)
    }
    
    // Shows alert for transfer password entry
    func showPasswordEntryAlert(saltData: Data, ivData: Data, encryptedName: Data) {
        // Create alert
        let passwordEntryAlertController = UIAlertController(title: "Enter Password for File", message: nil, preferredStyle: .alert)
        passwordEntryAlertController.addTextField { (textField) in
            textField.placeholder = "Password"
            textField.isSecureTextEntry = true
        }
        // Add action for finished entering password
        passwordEntryAlertController.addAction(UIAlertAction(title: "OK", style: .default, handler: { (UIAlertAction) in
            let password = passwordEntryAlertController.textFields![0].text
            // Check that password is not empty
            if !password!.isEmpty {
                // Initialize receiving process
                self.initializeReceive(password: password!, saltData: saltData, ivData: ivData, encryptedName: encryptedName)
            } else {
                // Show invalid password alert
                self.showInvalidPasswordAlert(saltData: saltData, ivData: ivData, encryptedName: encryptedName)
            }
        }))
        // Add action for cancelling password entry
        passwordEntryAlertController.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { (UIAlertAction) in
            // Terminate Socket.IO
            self.terminateSocketIO()
            // Reset receiving process
            self.resetReceive()
            UIApplication.shared.isIdleTimerDisabled = false
            self.activityIndicator.stopAnimating()
            self.receiveButton.isHidden = false
            self.keyTextField.isHidden = false
        }))
        present(passwordEntryAlertController, animated: true, completion: nil)
    }
    
    // Shows alert for invalid password
    func showInvalidPasswordAlert(saltData: Data, ivData: Data, encryptedName: Data) {
        let invalidPasswordAlertController = UIAlertController(title: "Invalid Password", message: nil, preferredStyle: .alert)
        invalidPasswordAlertController.addAction(UIAlertAction(title: "OK", style: .default, handler: { (UIAlertAction) in
            self.showPasswordEntryAlert(saltData: saltData, ivData: ivData, encryptedName: encryptedName)
        }))
        present(invalidPasswordAlertController, animated: true, completion: nil)
    }
    
    // Initializes decryption, authentication, and file output stream, then begins receiving of data
    func initializeReceive(password: String, saltData: Data, ivData: Data, encryptedName: Data) {
        let passwordData = password.data(using: .utf8)!
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
        // Initialize receiver HMAC context for HMAC-SHA256
        ReceiveViewController.transfer.hmacContext = CCHmacContext()
        hmacKey.withUnsafeBytes {
            CCHmacInit(&ReceiveViewController.transfer.hmacContext!, CCHmacAlgorithm(kCCHmacAlgSHA256), $0, hmacKey.count)
        }
        // Update receiver HMAC with salt, IV, and encrypted file name
        saltData.withUnsafeBytes {
            CCHmacUpdate(&ReceiveViewController.transfer.hmacContext!, $0, saltData.count)
        }
        ivData.withUnsafeBytes {
            CCHmacUpdate(&ReceiveViewController.transfer.hmacContext!, $0, ivData.count)
        }
        encryptedName.withUnsafeBytes {
            CCHmacUpdate(&ReceiveViewController.transfer.hmacContext!, $0, encryptedName.count)
        }
        // Decrypt file name
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
        // Check if file name successfully decrypted
        guard let decryptedName = String(data: decryptedNameData, encoding: .utf8) else {
            // Reset receiver HMAC context
            ReceiveViewController.transfer.hmacContext = nil
            // Show invalid password alert
            showInvalidPasswordAlert(saltData: saltData, ivData: ivData, encryptedName: encryptedName)
            return
        }
        // Initialize receiver cryptor ref for AES-256-CBC
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
        let documentDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let transfersDirectory = documentDirectory.appendingPathComponent("transfers")
        // Check if transfers directory exists
        if !FileManager.default.fileExists(atPath: transfersDirectory.path) {
            do {
                // Create transfers directory
                try FileManager.default.createDirectory(at: transfersDirectory, withIntermediateDirectories: true, attributes: nil)
            } catch {
                fatalError()
            }
        }
        // Set transfer output file URL
        ReceiveViewController.transfer.url = transfersDirectory.appendingPathComponent(decryptedName)
        // Check if output file exists
        if FileManager.default.fileExists(atPath: ReceiveViewController.transfer.url!.path) {
            // Append _new to output file URL
            let pathExtension = ReceiveViewController.transfer.url!.pathExtension
            let newPath = ReceiveViewController.transfer.url!.deletingPathExtension().path + "_new"
            let newURL = URL(fileURLWithPath: newPath).appendingPathExtension(pathExtension)
            ReceiveViewController.transfer.url = newURL
        }
        // Open file output stream
        ReceiveViewController.transfer.outputStream = OutputStream(url: ReceiveViewController.transfer.url!, append: false)
        ReceiveViewController.transfer.outputStream!.open()
        progressBar.isHidden = false
        // Begin receiving of data
        receive()
    }
    
    // Receives encrypted data and transfer progress or HMAC hash from sender
    func receive() {
        // Emit receive request
        receiveSocket.emitWithAck("requestReceive", ["key": ReceiveViewController.transfer.key]).timingOut(after: 0) { data in
            // Check that response data not empty
            if data.count == 1 {
                let dictionary = data.first as! [String: String]
                if dictionary["encryptedData"] != nil && dictionary["progress"] != nil {
                    // If response data is encrypted data and transfer progress
                    let encryptedData = Data(base64Encoded: dictionary["encryptedData"]!)!
                    let progress = Float(dictionary["progress"]!)!
                    // Process encrypted data and transfer progress
                    self.receivedUpdate(encryptedData: encryptedData, progress: progress)
                    self.receive()
                } else if dictionary["trustedHmac"] != nil {
                    // If response data is HMAC hash
                    let trustedHmac = Data(base64Encoded: dictionary["trustedHmac"]!)!
                    // Process HMAC hash
                    self.receivedFinal(trustedHmac: trustedHmac)
                }
            } else {
                // Terminate Socket.IO
                self.terminateSocketIO()
                // Reset receive process
                self.resetReceive()
                UIApplication.shared.isIdleTimerDisabled = false
                self.progressBar.isHidden = true
                self.progressBar.setProgress(0, animated: false)
                self.activityIndicator.stopAnimating()
                self.receiveButton.isHidden = false
                self.keyTextField.isHidden = false
                // Show invalid key alert
                self.showInvalidKeyAlert()
            }
        }
    }
    
    // Decrypts and authenticates additional data from sender, then writes decrypted data to output stream
    func receivedUpdate(encryptedData: Data, progress: Float) {
        var decryptedData = Data()
        // Update receiver HMAC with encrypted data
        encryptedData.withUnsafeBytes {
            CCHmacUpdate(&ReceiveViewController.transfer.hmacContext!, $0, encryptedData.count)
        }
        // Decrypt encrypted data
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
        // Write decrypted data to output stream
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
        // Update progress bar
        progressBar.setProgress(progress, animated: true)
    }
    
    // Finalizes decryption, verifies HMAC hash, emits received to sender, and ends receiving process
    func receivedFinal(trustedHmac: Data) {
        // Finalize decryption
        var decryptedData = Data()
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
        // Generate receiver HMAC hash
        var untrustedHmac = Data(count: Int(CC_SHA256_DIGEST_LENGTH))
        untrustedHmac.withUnsafeMutableBytes {
            CCHmacFinal(&ReceiveViewController.transfer.hmacContext!, $0)
        }
        // Verify HMAC hash
        if !verifyHmac(trustedHmac: trustedHmac, untrustedHmac: untrustedHmac) {
            // Terminate receiving process
            terminateReceive()
            // Terminate Socket.IO
            terminateSocketIO()
            // Reset receiving process
            resetReceive()
            UIApplication.shared.isIdleTimerDisabled = false
            progressBar.isHidden = true
            progressBar.setProgress(0, animated: false)
            activityIndicator.stopAnimating()
            receiveButton.isHidden = false
            keyTextField.isHidden = false
            // Show could not authenticate data alert
            showCouldNotAuthenticateDataAlert()
            return
        }
        // Emit received to sender
        receiveSocket.emit("received", ["key": ReceiveViewController.transfer.key])
        // End receiving process
        endReceive()
    }
    
    // Verifies HMAC hash with constant time comparison function to prevent timing attacks
    func verifyHmac(trustedHmac: Data, untrustedHmac: Data) -> Bool {
        if trustedHmac.count != untrustedHmac.count {
            return false;
        }
        var result: UInt8 = 0;
        for (i, untrustedByte) in untrustedHmac.enumerated() {
            result |= trustedHmac[i % trustedHmac.count] ^ untrustedByte
        }
        return result == 0
    }
    
    // Shows alert for could not authenticate data
    func showCouldNotAuthenticateDataAlert() {
        let couldNotAuthenticateDataAlertController = UIAlertController(title: "Could Not Authenticate Data", message: nil, preferredStyle: .alert)
        couldNotAuthenticateDataAlertController.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        present(couldNotAuthenticateDataAlertController, animated: true, completion: nil)
    }
    
    // Saves current transfer URL as last transfer URL, cleans transfers directory, and presents activity view controller for file
    func endReceive() {
        // Save current transfer URL as last transfer URL
        saveLastTransferURL()
        // Delete all files in transfers directory except for received file
        cleanTransfersDirectory()
        // Create activity view controller for file
        let activityViewController = UIActivityViewController(activityItems: [ReceiveViewController.transfer.url!], applicationActivities: nil)
        // Terminate receiving process
        terminateReceive()
        // Terminate Socket.IO
        terminateSocketIO()
        // Reset receiving process
        resetReceive()
        UIApplication.shared.isIdleTimerDisabled = false
        progressBar.isHidden = true
        progressBar.setProgress(0, animated: false)
        activityIndicator.stopAnimating()
        receiveButton.isHidden = false
        keyTextField.isHidden = false
        // Present activity view controller for file
        present(activityViewController, animated: true, completion: nil)
    }
    
    // Saves current transfer URL as last transfer URL
    func saveLastTransferURL() {
        UserDefaults.standard.set(ReceiveViewController.transfer.url!, forKey: "lastTransferURL")
    }
    
    // Deletes all files in transfers directory except for last received file
    func cleanTransfersDirectory() {
        let documentDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let transfersDirectory = documentDirectory.appendingPathComponent("transfers")
        do {
            // Get contents of transfers directory
            let transfersDirectoryContents = try FileManager.default.contentsOfDirectory(atPath: transfersDirectory.path)
            // For each file in transfers directory
            try transfersDirectoryContents.forEach { file in
                // Get file URL
                let url = transfersDirectory.appendingPathComponent(file)
                // Delete file if not last received file
                if (url != ReceiveViewController.transfer.url!) {
                    try FileManager.default.removeItem(at: url)
                }
            }
        } catch {
            fatalError()
        }
    }
    
    // Releases cryptor ref and closes output stream
    func terminateReceive() {
        CCCryptorRelease(ReceiveViewController.transfer.cryptorRef!)
        ReceiveViewController.transfer.outputStream!.close()
    }
    
    // Sets not receiving and sets transfer object to nil
    func resetReceive() {
        ReceiveViewController.receiving = false
        ReceiveViewController.transfer = nil
    }
}
