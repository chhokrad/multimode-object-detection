//
//  ViewController.swift
//  MultiModeObjectDetection
//
//  Copyright © 2018 Vanderbilt University. All rights reserved.
//

import UIKit
import Alamofire
import SwiftyJSON

class ViewController: UIViewController {

    @IBOutlet weak var fromLat: UITextField!
    @IBOutlet weak var fromLon: UITextField!

    @IBOutlet weak var toLat: UITextField!
    @IBOutlet weak var toLon: UITextField!

    @IBAction func start(_ sender: UIButton) {
        Alamofire.request("http://localhost:3000/api?fromLat=7&fromLon=12").responseJSON { response in
            if let result = response.result.value {
                let json = JSON(result)
                print(json["fromLat"])
                print(json["fromLon"])
            }
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }


}

