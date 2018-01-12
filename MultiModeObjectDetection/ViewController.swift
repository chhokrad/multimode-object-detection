//
//  ViewController.swift
//  MultiModeObjectDetection
//
//  Copyright © 2018 Vanderbilt University. All rights reserved.
//

import Alamofire
import AVKit
import SwiftyJSON
import SocketIO
import UIKit
import Vision





class ViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {

    @IBOutlet weak var fromLat: UITextField!
    @IBOutlet weak var fromLng: UITextField!
    @IBOutlet weak var toLat: UITextField!
    @IBOutlet weak var toLng: UITextField!

    let initialDeploymentServer = "http://10.66.11.62:3000/api"
    var remoteServer : String!
    var manager_ : SocketManagerSpec!
    var socket: SocketIOClient!
    var CurrentFrame : CVPixelBuffer!
    var CurrentImage : UIImage!
    var CurrentFrameToSend : CMSampleBuffer!

    enum States {
        case initial
        case requesting_remote
        case running_local
        case connect_remote
        case running_remote
        case empty
    }
    var state = States.initial
    var isRunning = false
    var ticks =  0
    @IBAction func start(_ sender: UIButton) {
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            self.ticks += 1
            print(Date())
            print(self.ticks)
            if (!self.isRunning) {
                print("Running StateMachine")
                self.isRunning = true
                self.runStateMachine()
            }
            else{
                print("Skipping This tick")
            }
        }
    }

    func runStateMachine() {
        switch state {
        case .initial:
            print(States.initial)
            initialHandler()
        case .requesting_remote:
            print(States.requesting_remote)
            requestingRemoteHandler()
        case .running_local:
            print(States.running_local)
            runningLocalHandler()
        case .connect_remote:
            print(States.connect_remote)
            connectRemoteHandler()
        case .running_remote:
            print(States.running_remote)
            print(remoteServer)
            runningRemoteHandler()
        case .empty:
            print(States.empty)
        }
    }
    
    func connectRemoteHandler() {
        initConnection()
    }
    
    func runningRemoteHandler() {
        if (!isConnected()){
            state = .running_local
        } else {
            // This is async, be careful
            sendFile()
        }
        isRunning = false;
//        sendFile()
//        if (!isConnected()){
//            state = .running_local
//            isRunning = false
//        }
    }
    
    func sendFile() {
        let imageData = UIImageJPEGRepresentation(CurrentImage, 0.5)
//        let imageData = UIImagePNGRepresentation(sendingImage)
        let encodeImageData = imageData?.base64EncodedString()
        self.socket.emit("NewFrame", encodeImageData!)
    }
    
    func runningLocalHandler(){
        manager_.disconnect()
        manager_.removeSocket(socket)
        performDetection()
        if (isConnected()){
            state = .connect_remote
        }
        isRunning = false
    }
    
    func requestingRemoteHandler() {
        var queryURL = URLComponents(string: initialDeploymentServer)
        queryURL?.queryItems = [
            URLQueryItem(name: "fromLat", value: fromLat.text),
            URLQueryItem(name: "fromLng", value: fromLng.text),
            URLQueryItem(name: "toLat", value: toLat.text),
            URLQueryItem(name: "toLng", value: toLng.text)]
            Alamofire.request(queryURL!).validate().responseJSON { response in
                switch response.result {
                    case .success:
                        if let result = response.result.value {
                            self.remoteServer = JSON(result)["host"].string
                            self.state = .connect_remote
                        } else {
                            self.state = .running_local
                        }
                    case .failure:
                        self.state = .running_local
                }
                self.isRunning = false
            }
    }
    
    func initialHandler() {
        initCamera()
        if (isConnected()) {
            state = .requesting_remote
        } else {
            state = .running_local
        }
        isRunning = false
    }

    func isConnected() -> Bool {
        let isConnectedToWifi = NetworkReachabilityManager()?.isReachableOnEthernetOrWiFi
        return isConnectedToWifi!
    }

    func initConnection() {
        print("initConnection")
        print(remoteServer)
        manager_ = SocketManager(socketURL: URL(string: remoteServer)!, config: [.log(true), .compress])
        socket = manager_.defaultSocket
        socket.on("connect") {data, ack in
            print("socket connected")
            self.state = .running_remote
            self.isRunning = false
        }
        socket.connect()
    }

    let identifierLabel: UILabel = {
        let label = UILabel()
        label.backgroundColor = .white
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    func initCamera() {
        let captureSession = AVCaptureSession()
        captureSession.sessionPreset = .photo
        guard let captureDevice = AVCaptureDevice.default(for: .video) else { return }
        guard let input = try? AVCaptureDeviceInput(device: captureDevice) else { return }
        captureSession.addInput(input)
        captureSession.startRunning()
        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        view.layer.addSublayer(previewLayer)
        previewLayer.frame = view.frame
        let dataOutput = AVCaptureVideoDataOutput()
        dataOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        captureSession.addOutput(dataOutput)
        setupIdentifierConfidenceLabel()
    }
    
    fileprivate func setupIdentifierConfidenceLabel() {
        view.addSubview(identifierLabel)
        identifierLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -32).isActive = true
        identifierLabel.leftAnchor.constraint(equalTo: view.leftAnchor).isActive = true
        identifierLabel.rightAnchor.constraint(equalTo: view.rightAnchor).isActive = true
        identifierLabel.heightAnchor.constraint(equalToConstant: 50).isActive = true
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer: CVPixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        CurrentFrameToSend = sampleBuffer
        CurrentFrame = pixelBuffer
        let ciimage : CIImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context:CIContext = CIContext.init(options: nil)
        let cgImage:CGImage = context.createCGImage(ciimage, from: ciimage.extent)!
        CurrentImage = UIImage.init(cgImage: cgImage)
    }
    
    func imageFromSampleBuffer(sampleBuffer : CMSampleBuffer) -> UIImage
    {
        // Get a CMSampleBuffer's Core Video image buffer for the media data
        let  imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
        // Lock the base address of the pixel buffer
        CVPixelBufferLockBaseAddress(imageBuffer!, CVPixelBufferLockFlags.readOnly);
        
        
        // Get the number of bytes per row for the pixel buffer
        let baseAddress = CVPixelBufferGetBaseAddress(imageBuffer!);
        
        // Get the number of bytes per row for the pixel buffer
        let bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer!);
        // Get the pixel buffer width and height
        let width = CVPixelBufferGetWidth(imageBuffer!);
        let height = CVPixelBufferGetHeight(imageBuffer!);
        
        // Create a device-dependent RGB color space
        let colorSpace = CGColorSpaceCreateDeviceRGB();
        
        // Create a bitmap graphics context with the sample buffer data
        var bitmapInfo: UInt32 = CGBitmapInfo.byteOrder32Little.rawValue
        bitmapInfo |= CGImageAlphaInfo.premultipliedFirst.rawValue & CGBitmapInfo.alphaInfoMask.rawValue
        //let bitmapInfo: UInt32 = CGBitmapInfo.alphaInfoMask.rawValue
        let context = CGContext.init(data: baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo)
        // Create a Quartz image from the pixel data in the bitmap graphics context
        let quartzImage = context?.makeImage();
        // Unlock the pixel buffer
        CVPixelBufferUnlockBaseAddress(imageBuffer!, CVPixelBufferLockFlags.readOnly);
        
        // Create an image object from the Quartz image
        let image = UIImage.init(cgImage: quartzImage!);
        
        return (image);
    }
    
    func performDetection(){
        guard let model = try? VNCoreMLModel(for: Resnet50().model) else { return }
        let request = VNCoreMLRequest(model: model) { (finishedReq, err) in
            guard let results = finishedReq.results as? [VNClassificationObservation] else { return }
            guard let firstObservation = results.first else { return }
            print(firstObservation.identifier, firstObservation.confidence)
            DispatchQueue.main.async {
                self.identifierLabel.text = "\(firstObservation.identifier) \(firstObservation.confidence * 100)"
            }
        }
        try? VNImageRequestHandler(cvPixelBuffer: CurrentFrame, options: [:]).perform([request])
    }
}

