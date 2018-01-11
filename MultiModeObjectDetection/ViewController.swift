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

    let initialDeploymentServer = "http://10.67.101.1:3000/api"
    var remoteServer : String!

    enum States {
        case initial
        case requesting_remote
        case running_local
        case running_remote
        case empty
    }
    var state = States.initial

    @IBAction func start(_ sender: UIButton) {
        while(true) {
            runStateMachine()
            if (state == .empty) {
                break
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
            state = .empty
        case .running_remote:
            print(States.running_remote)
            state = .empty
        case .empty:
            print(States.empty)
        }
    }

    func requestingRemoteHandler() {
        var queryURL = URLComponents(string: initialDeploymentServer)
        queryURL?.queryItems = [
            URLQueryItem(name: "fromLat", value: fromLat.text),
            URLQueryItem(name: "fromLng", value: fromLng.text),
            URLQueryItem(name: "toLat", value: toLat.text),
            URLQueryItem(name: "toLng", value: toLng.text)]
        Alamofire.request(queryURL!).responseJSON { response in
            if let result = response.result.value {
                let json = JSON(result)
                self.remoteServer = json["host"].string
                self.state = .running_remote
            } else {
                print("error")
                print(response)
                self.state = .running_local
            }
        }
    }

    func initialHandler() {
        if (isConnected()) {
            state = .requesting_remote
        } else {
            state = .running_local
        }
    }



    func isConnected() -> Bool {
        let isConnectedToWifi = NetworkReachabilityManager()?.isReachableOnEthernetOrWiFi
        return isConnectedToWifi!
    }


//    Below is to be moved up

    var timer: Timer!


    let manager = SocketManager(socketURL: URL(string: "http://10.67.101.1:3001")!, config: [.log(true), .compress])
    var socket: SocketIOClient!

    let identifierLabel: UILabel = {
        let label = UILabel()
        label.backgroundColor = .white
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    func initConnection(){
        socket = manager.defaultSocket
        socket.on("connect") {data, ack in
            print("socket connected")
        }
        socket.connect()
    }

    func initCamera() {
        // here is where we start up the camera
        // for more details visit: https://www.letsbuildthatapp.com/course_video?id=1252
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
        //        VNImageRequestHandler(cgImage: <#T##CGImage#>, options: [:]).perform(<#T##requests: [VNRequest]##[VNRequest]#>)

        setupIdentifierConfidenceLabel()
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        //        print("Camera was able to capture a frame:", Date())

        guard let pixelBuffer: CVPixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // !!!Important
        // make sure to go download the models at https://developer.apple.com/machine-learning/ scroll to the bottom
        guard let model = try? VNCoreMLModel(for: Resnet50().model) else { return }
        let request = VNCoreMLRequest(model: model) { (finishedReq, err) in

            //perhaps check the err

            //            print(finishedReq.results)

            guard let results = finishedReq.results as? [VNClassificationObservation] else { return }

            guard let firstObservation = results.first else { return }

            print(firstObservation.identifier, firstObservation.confidence)

            DispatchQueue.main.async {
                self.identifierLabel.text = "\(firstObservation.identifier) \(firstObservation.confidence * 100)"
            }

        }

        try? VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:]).perform([request])
    }

    fileprivate func setupIdentifierConfidenceLabel() {
        view.addSubview(identifierLabel)
        identifierLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -32).isActive = true
        identifierLabel.leftAnchor.constraint(equalTo: view.leftAnchor).isActive = true
        identifierLabel.rightAnchor.constraint(equalTo: view.rightAnchor).isActive = true
        identifierLabel.heightAnchor.constraint(equalToConstant: 50).isActive = true
    }

    func mainImpl() {
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            print("looping")
            let isConnectedToWifi = NetworkReachabilityManager()?.isReachableOnEthernetOrWiFi
            if (isConnectedToWifi!) {
                self.socket.emit("image", Date().description)
                print("connected")
            } else {
                print("no wifi")
            }
        }
    }



    deinit {
        timer?.invalidate()
    }


}

