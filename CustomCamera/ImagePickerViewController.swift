//
//  ImagePickerViewController.swift
//  CustomCamera
//
//  Created by Apple on 28/12/24.
//

import UIKit
import AVFoundation
import Photos
import MobileCoreServices
import SKPhotoBrowser

typealias VoidCompletionHandler = (() -> Void)

class ImagePickerViewController: UIViewController {
    
    @IBOutlet weak var cameraView: UIView!
    @IBOutlet weak var bgBtnTakePhoto: UIView!
    @IBOutlet weak var bgBtnSwitchCamera: UIView!
    @IBOutlet weak var btnTakePhoto: UIButton!
    @IBOutlet weak var btnSwitchCamera: UIButton!
    @IBOutlet weak var bgImgPreview: UIView!
    @IBOutlet weak var imgPreview: UIImageView!
    @IBOutlet weak var bgSwitchCameraType: UIView!
    @IBOutlet weak var bgGallery: UIView!
    @IBOutlet weak var bgClose: UIView!
    @IBOutlet weak var imgSwitchCamera: UIImageView!
    @IBOutlet weak var bgFlash: UIView!
    @IBOutlet weak var stackView: UIStackView!
    
    //MARK:- Vars
    private var captureSession : AVCaptureSession?
    
    private var backCamera : AVCaptureDevice?
    private var frontCamera : AVCaptureDevice?
    private var backInput : AVCaptureInput?
    private var frontInput : AVCaptureInput?
    
    private var previewLayer : AVCaptureVideoPreviewLayer?
    
    private var videoOutput : AVCaptureVideoDataOutput?
    
    private var takePicture = false
    private var backCameraOn = true
    private var torchOn = false
    private var isRestartingSession = false

    private var supportedDeviceList: [AVCaptureDevice] = []
    private var backCameraList: [AVCaptureDevice] = []
    private var frontCameraList: [AVCaptureDevice] = []
    private var backCameraCount: Int = 0
    private var frontCameraCount: Int = 0
    
    private var timer: Timer?
    
    private let imagePickerController = UIImagePickerController()
    private var captureList: [UIImage?] = []
    
    var isOpened: Bool = false
    var closeCompletion: VoidCompletionHandler?

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Do any additional setup after loading the view.
        checkAndOpenLibrary()
        checkForFlash()
        resetBgImgPreview()
        // Fetch all camera options
        let deviceTypes: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera, .builtInTelephotoCamera, .builtInDualCamera, .builtInDualWideCamera, .builtInTripleCamera, .builtInUltraWideCamera]
        let cameraDevices = AVCaptureDevice.DiscoverySession(deviceTypes: deviceTypes,
                                                             mediaType: .video,
                                                             position: .unspecified)
        supportedDeviceList = cameraDevices.devices
        frontCameraList = supportedDeviceList.filter { $0.position == .front }
        backCameraList = supportedDeviceList.filter { $0.position == .back }
        for device in backCameraList {
            print("- \(device.localizedName) (Position: \(device.position)) (Camera Type: \(device.deviceType.rawValue))")
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        checkPermissions()
        setupAndStartCaptureSession()
    }
    
    private func checkAndOpenLibrary() {
        let authStatus = PHPhotoLibrary.authorizationStatus()
        switch authStatus {
        case .authorized:
            break
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization({ (status) in
                DispatchQueue.main.async {
                    switch status {
                    case .authorized:
                        break
                    default:
                        self.alertPromptToAllowCameraAccessViaSetting("Restricted From Using Camera")
                    }
                }
            })
        case .restricted:
            alertPromptToAllowCameraAccessViaSetting("Restricted From Using Camera")
        case .denied:
            alertPromptToAllowCameraAccessViaSetting("Change Privacy Setting And Allow Access To Library")
        default:
            break
        }
    }

    func takePhoto() {
        btnTakePhotoClicked(UIButton())
    }
    
    @IBAction func btnCloseClicked(_ sender: UIButton) {
        isOpened = false
        stopAndDestroySession()
        backCameraCount = 0
        frontCameraCount = 0
        takePicture = false
        backCameraOn = true
        torchOn = false
        resetAndMove()
        closeCompletion?()
        dismiss(animated: true)
    }
    
    @IBAction func btnGalleryClicked(_ sender: UIButton) {
        openUIImagePicker()
    }
    
    @IBAction func btnTakePhotoClicked(_ sender: UIButton) {
        takePicture = true
        provideShortVibrationFeedback()
    }
    
    @IBAction func btnFlashClicked(_ sender: UIButton) {
        torchOn.toggle()
        toggleTorch(on: torchOn)
    }
    
    @IBAction func btnSwitchCameraClicked(_ sender: UIButton) {
        if isRestartingSession == false {
            isRestartingSession = true
            stopAndDestroySession()
            backCameraOn.toggle()
            setupAndStartCaptureSession()
        }
        // switchCameraInput()
    }
    
    @IBAction func btnSwitchCameraTypeClicked(_ sender: UIButton) {
        if isRestartingSession == false {
            isRestartingSession = true
            if backCameraOn {
                let count = backCameraList.count
                if count > 1 {
                    stopAndDestroySession()
                    if backCameraCount < count - 1 {
                        backCameraCount += 1
                    } else {
                        backCameraCount = 0
                    }
                    setupAndStartCaptureSession()
                } else {
                    backCameraCount = 0
                    isRestartingSession = false
                }
            } else {
                let count = frontCameraList.count
                if count > 1 {
                    stopAndDestroySession()
                    if frontCameraCount < count - 1 {
                        frontCameraCount += 1
                    } else {
                        frontCameraCount = 0
                    }
                    setupAndStartCaptureSession()
                } else {
                    frontCameraCount = 0
                    isRestartingSession = false
                }
            }
        }
    }
    
    @IBAction func btnShareClicked(_ sender: UIButton) {
        if let img = imgPreview.image {
            self.stopTimer()
            self.openPrevieController(img)
            self.resetBgImgPreview()
        }
    }
    
    private func provideShortVibrationFeedback() {
        let feedbackGenerator = UIImpactFeedbackGenerator(style: .light)
        feedbackGenerator.prepare()
        feedbackGenerator.impactOccurred()
    }
    
    private func animateBgImgPreview() {
        UIView.animate(withDuration: 0.35) {
            self.bgImgPreview.alpha = 1
            self.bgImgPreview.transform = .identity
        } completion: { _ in
            // Cancel any existing timer
            self.stopTimer()
            // Create a new timer
            self.timer = Timer.scheduledTimer(withTimeInterval: 2,
                                              repeats: false) { [weak self] _ in
                guard let self else { return }
                guard self.timer != nil else { return }
                self.resetAndMove()
            }
        }
    }
    
    private func resetAndMove() {
        if self.takePicture == false {
            UIView.animate(withDuration: 0.35) {
                self.moveBgImgPreView()
            } completion: { _ in
                self.resetBgImgPreview()
            }
        }
    }
    
    private func resetBgImgPreview() {
        bgImgPreview.alpha = 0
        bgImgPreview.transform = .init(scaleX: 2, y: 2)
    }
    
    private func moveBgImgPreView() {
        bgImgPreview.transform = .init(translationX: 200, y: 0)
    }
    
    /// Stops the timer and ensures the block won't be executed
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    private func dismissView() {
        imagePickerController.dismiss(animated: true)
    }
    
    private func checkForFlash() {
        let count = backCameraList.count
        if backCameraCount < count {
            guard let device = AVCaptureDevice.default(backCameraList[backCameraCount].deviceType,
                                                       for: .video,
                                                       position: .back) else {
                bgFlash.isHidden = true
                return
            }
            bgFlash.isHidden = !device.hasTorch
        } else {
            bgFlash.isHidden = true
        }
    }
    
    private func toggleTorch(on: Bool) {
        let count = backCameraList.count
        if backCameraCount < count {
            if  let device = AVCaptureDevice.default(backCameraList[backCameraCount].deviceType,
                                                     for: .video,
                                                     position: .back) {
                if device.hasTorch {
                    do {
                        try device.lockForConfiguration()
                        if on == true {
                            device.torchMode = .on
                        } else {
                            device.torchMode = .off
                        }
                        device.unlockForConfiguration()
                        return
                    } catch {
                        print("Error enabling torch: \(error)")
                    }
                }
            }
        }
        bgFlash.isHidden = true
    }
}

extension ImagePickerViewController {
    //MARK: - Permissions
    private func checkPermissions() {
        let cameraAuthStatus =  AVCaptureDevice.authorizationStatus(for: AVMediaType.video)
        switch cameraAuthStatus {
        case .authorized:
            return
        case .denied:
            alertPromptToAllowCameraAccessViaSetting("Change Privacy Setting And Allow Access To Library")
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: AVMediaType.video, completionHandler:
                                            { (authorized) in
                if authorized == false {
                    self.alertPromptToAllowCameraAccessViaSetting("Restricted From Using Camera")
                }
            })
        case .restricted:
            alertPromptToAllowCameraAccessViaSetting("Restricted From Using Camera")
        default:
            self.alertPromptToAllowCameraAccessViaSetting("Restricted From Using Camera")
        }
    }
}

extension ImagePickerViewController {
    
    //MARK: - Camera Setup
    private func setupAndStartCaptureSession() {
        DispatchQueue.global(qos: .userInitiated).async {
            //init session
            self.captureSession = AVCaptureSession()
            //start configuration
            guard let captureSession = self.captureSession else { return }
            captureSession.beginConfiguration()
            //session specific configuration
            if captureSession.canSetSessionPreset(.photo) {
                captureSession.sessionPreset = .photo
            }
            captureSession.automaticallyConfiguresCaptureDeviceForWideColor = true
            //setup inputs
            self.setupInputs()
            DispatchQueue.main.async {
                //setup preview layer
                self.setupPreviewLayer()
            }
            //setup output
            self.setupOutput()
            //commit configuration
            captureSession.commitConfiguration()
            //start running it
            captureSession.startRunning()
            self.isRestartingSession = false
        }
    }
    
    private func setupInputs() {
        guard let captureSession else { return }
        if backCameraOn {
            let count = backCameraList.count
            if backCameraCount < count {
                //get back camera
                if let device = AVCaptureDevice.default(backCameraList[backCameraCount].deviceType,
                                                        for: .video,
                                                        position: .back) {
                    backCamera = device
                    //now we need to create an input objects from our devices
                    guard let bInput = try? AVCaptureDeviceInput(device: device) else {
                        self.alertPromptToAllowCameraAccessViaSetting("Restricted From Using Camera")
                        return
                    }
                    backInput = bInput
                    if !captureSession.canAddInput(bInput) {
                        self.alertPromptToAllowCameraAccessViaSetting("Restricted From Using Camera")
                    }
                    //connect back camera input to session
                    captureSession.addInput(bInput)
                } else {
                    //handle this appropriately for production purposes
                    self.alertPromptToAllowCameraAccessViaSetting("Restricted From Using Camera")
                }
            }
        } else {
            let count = frontCameraList.count
            if frontCameraCount < count {
                //get front camera
                if let device = AVCaptureDevice.default(frontCameraList[frontCameraCount].deviceType,
                                                        for: .video,
                                                        position: .front) {
                    frontCamera = device
                    guard let fInput = try? AVCaptureDeviceInput(device: device) else {
                        self.alertPromptToAllowCameraAccessViaSetting("Restricted From Using Camera")
                        return
                    }
                    frontInput = fInput
                    if !captureSession.canAddInput(fInput) {
                        self.alertPromptToAllowCameraAccessViaSetting("Restricted From Using Camera")
                    }
                    captureSession.addInput(fInput)
                } else {
                    self.alertPromptToAllowCameraAccessViaSetting("Restricted From Using Camera")
                }
            }
        }
    }
    
    private func setupOutput() {
        videoOutput = AVCaptureVideoDataOutput()
        guard let captureSession else { return }
        guard let videoOutput else { return }
        let videoQueue = DispatchQueue(label: "videoQueue", qos: .userInteractive)
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        } else {
            self.alertPromptToAllowCameraAccessViaSetting("Restricted From Using Camera")
        }
        videoOutput.connections.first?.videoOrientation = .portrait
    }
    
    private func setupPreviewLayer() {
        guard let captureSession else { return }
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        guard let previewLayer else { return }
        view.layer.insertSublayer(previewLayer, below: btnSwitchCamera.layer)
        // previewLayer.frame = self.view.layer.frame
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        
        view.bringSubviewToFront(bgImgPreview)
        view.bringSubviewToFront(bgBtnTakePhoto)
        view.bringSubviewToFront(bgBtnSwitchCamera)
        view.bringSubviewToFront(bgSwitchCameraType)
        view.bringSubviewToFront(bgGallery)
        view.bringSubviewToFront(bgClose)
        view.bringSubviewToFront(bgFlash)
        view.bringSubviewToFront(stackView)
        if backCameraOn {
            let count = backCameraList.count
            bgSwitchCameraType.isHidden = (count == 1 || count == 0)
            checkForFlash()
        } else {
            let count = frontCameraList.count
            bgSwitchCameraType.isHidden = (count == 1 || count == 0)
            bgFlash.isHidden = true
        }
    }
    
    private func stopAndDestroySession() {
        // Stop the session to release resources
        captureSession?.stopRunning()
        // Remove preview layer
        previewLayer?.removeFromSuperlayer()
        // Remove inputs and outputs (if necessary)
        if let inputs = captureSession?.inputs {
            for input in inputs {
                captureSession?.removeInput(input)
            }
        }
        if let outputs = captureSession?.outputs {
            for output in outputs {
                captureSession?.removeOutput(output)
            }
        }
        // Set capture session to nil
        captureSession = nil
        previewLayer = nil
        torchOn = false
    }
}

extension ImagePickerViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        if !takePicture {
            return //we have nothing to do with the image buffer
        }
        
        //try and get a CVImageBuffer out of the sample buffer
        guard let cvBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        //get a CIImage out of the CVImageBuffer
        let ciImage = CIImage(cvImageBuffer: cvBuffer)
        
        guard let cgImage = cgImage(from: ciImage) else { return } // the above function
        let uiImage = UIImage(cgImage: cgImage) // ready to be saved!

        //get UIImage out of CIImage
        // let uiImage = UIImage(ciImage: ciImage)
        DispatchQueue.main.async {
            self.imgPreview.image = uiImage
            self.takePicture = false
            self.animateBgImgPreview()
            self.captureList.append(self.imgPreview.image)
            DispatchQueue.global().async { [weak self] in
                guard let self else { return }
                self.saveToGallery()
            }
        }
    }
    
    private func cgImage(from ciImage: CIImage) -> CGImage? {
        let context = CIContext(options: nil)
        return context.createCGImage(ciImage, from: ciImage.extent)
    }
    
    private func saveToGallery() {
        for item in captureList {
            guard let item else { return }
            UIImageWriteToSavedPhotosAlbum(item, self, #selector(imageSaveCompleted(_:didFinishSavingWithError:contextInfo:)), nil)
        }
        DispatchQueue.main.async {
            self.captureList = []
        }
    }

    @objc private func imageSaveCompleted(_ image: UIImage,
                                  didFinishSavingWithError error: Error?,
                                  contextInfo: UnsafeRawPointer) {
        if let error = error {
            print("Error saving image: \(error.localizedDescription)")
        } else {
            print("Image saved successfully!")
        }
    }
}

extension ImagePickerViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    
    private func openUIImagePicker() {
        imagePickerController.delegate = self
        topViewController()?.present(imagePickerController,
                                     animated: true,
                                     completion: nil)
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true, completion: nil)
    }
    
    func imagePickerController(_ picker: UIImagePickerController,
                               didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        picker.dismiss(animated: true) {
            if let img = info[.editedImage] as? UIImage {
                DispatchQueue.main.async {
                    self.openPrevieController(img)
                    // CommonFunctions.externalTextShare(obj: [img])
                }
            } else if let img = info[.originalImage] as? UIImage {
                DispatchQueue.main.async {
                    self.openPrevieController(img)
                    // CommonFunctions.externalTextShare(obj: [img])
                }
            } else {
                print("No image found")
            }
        }
    }
    
    private func openPrevieController(_ img: UIImage) {
        var images = [SKPhoto]()
        let photo = SKPhoto.photoWithImage(img)
        photo.contentMode = .scaleAspectFit
        images.append(photo)
        let browser = SKPhotoBrowser(photos: images)
        browser.initializePageIndex(0)
        self.present(browser,
                     animated: true)
    }
    
    private func topViewController(controller: UIViewController? = UIApplication.shared.keyWindow?.rootViewController) -> UIViewController? {
        if let navigationController = controller as? UINavigationController {
            return topViewController(controller: navigationController.visibleViewController)
        }
        if let tabController = controller as? UITabBarController {
            if let selected = tabController.selectedViewController {
                return topViewController(controller: selected)
            }
        }
        if let presented = controller?.presentedViewController {
            return topViewController(controller: presented)
        }
        return controller
    }
}

extension ImagePickerViewController {
    private func alertPromptToAllowCameraAccessViaSetting(_ message: String) {
        let alert = UIAlertController(title: "Alert",
                                      message: message,
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Settings",
                                      style: .destructive,
                                      handler: { (action) in
            if let url = URL(string:UIApplication.openSettingsURLString) {
                if UIApplication.shared.canOpenURL(url) {
                    UIApplication.shared.open(url,
                                              completionHandler: { (success) in
                        print("Settings opened: \(success)")
                    })
                }
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.dismiss(animated: true)
            }
        }))
        alert.addAction(UIAlertAction(title: "Cancel",
                                      style: .cancel,
                                      handler: { (action) in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.dismiss(animated: true)
            }
        }))
        present(alert,
                animated: true,
                completion: nil)
        isOpened = false
    }
}
