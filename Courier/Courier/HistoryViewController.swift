import UIKit

class HistoryViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    // Called when share button is touched
    @IBAction func shareButtonTouched(_ sender: UIButton) {
        // Check if file exists at last transfer URL
        if let url = UserDefaults.standard.url(forKey: "lastTransferURL"), FileManager.default.fileExists(atPath: url.path) {
            // Present activity view controller for file
            let activityViewController = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            present(activityViewController, animated: true, completion: nil)
        } else {
            // Show alert if no previous transfer
            showNoPreviousTransferAlert()
        }
    }
    
    // Shows alert for no previous transfer
    func showNoPreviousTransferAlert() {
        let noPreviousTransferAlertController = UIAlertController(title: "No Previous Transfer Found", message: nil, preferredStyle: .alert)
        noPreviousTransferAlertController.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        present(noPreviousTransferAlertController, animated: true, completion: nil)
    }
}
