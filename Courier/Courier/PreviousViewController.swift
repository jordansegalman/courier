//
//  PreviousViewController.swift
//  Courier
//
//  Created by Jordan Segalman on 6/18/18.
//  Copyright © 2018 example. All rights reserved.
//

import UIKit

class PreviousViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    @IBAction func shareButtonTouched(_ sender: UIButton) {
        if let url = UserDefaults.standard.url(forKey: "lastTransferURL"), FileManager.default.fileExists(atPath: url.path) {
            let activityViewController = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            present(activityViewController, animated: true, completion: nil)
        } else {
            showNoPreviousTransferAlert()
        }
    }
    
    func showNoPreviousTransferAlert() {
        let noPreviousTransferAlertController = UIAlertController(title: "No Previous Transfer Found", message: nil, preferredStyle: .alert)
        noPreviousTransferAlertController.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        present(noPreviousTransferAlertController, animated: true, completion: nil)
    }
}
