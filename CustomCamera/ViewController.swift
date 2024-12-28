//
//  ViewController.swift
//  CustomCamera
//
//  Created by Apple on 28/12/24.
//

import UIKit

class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
    }
    
    @IBAction func btnOpenCameraClicked(_ sender: UIButton) {
        if let viewController = storyboard?.instantiateViewController(withIdentifier: "ImagePickerViewController") as? ImagePickerViewController {
            viewController.modalPresentationStyle = .overFullScreen
            self.present(viewController, animated: true)
        }
    }
    
}
