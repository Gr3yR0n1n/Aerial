//
//  ManifestLoader.swift
//  Aerial
//
//  Created by John Coates on 10/28/15.
//  Copyright © 2015 John Coates. All rights reserved.
//

import Foundation
import ScreenSaver

typealias manifestLoadCallback = ([AerialVideo]) -> (Void)

class ManifestLoader {
    static let instance: ManifestLoader = ManifestLoader()
    
    lazy var preferences = Preferences.sharedInstance
    var callbacks = [manifestLoadCallback]()
    var loadedManifest = [AerialVideo]()
    var playedVideos = [AerialVideo]()
    var offlineMode: Bool = false
    
    func addCallback(_ callback:@escaping manifestLoadCallback) {
        if loadedManifest.count > 0 {
            callback(loadedManifest)
        } else {
            callbacks.append(callback)
        }
    }
    
    func randomVideo() -> AerialVideo? {
        let shuffled = loadedManifest.shuffled()
        for video in shuffled {
            let inRotation = preferences.videoIsInRotation(videoID: video.id)
            
            if !inRotation {
                debugLog("video is disabled: \(video)")
                continue
            }
            
            // check if we're in offline mode
            if offlineMode == true {
                if video.isAvailableOffline == false {
                    continue
                }
            }
            
            return video
        }
        
        // nothing available??? return first thing we find
        return shuffled.first
    }
    
    init() {
        // start loading right away!
        let completionHandler = { (data: Data?, response: URLResponse?, error: Error?) -> Void in
            if let error = error {
                NSLog("Aerial Error Loading Manifest: \(error)")
                self.loadSavedManifest()
                return
            }
            
            guard let data = data else {
                NSLog("Couldn't load manifest!")
                self.loadSavedManifest()
                return
            }
            self.preferences.manifest = data
            
            DispatchQueue.main.async(execute: { () -> Void in
                self.readJSONFromData(data)
            })
            
        }
        
        /*
        if let path = Bundle.main.path(forResource: "~/.aerial.plist", ofType: "plist") {
            if let dict = NSDictionary(contentsOfFile: path) {
                // Use dictionary here
                var apiURL = dict["apiURL"] ?? ""
            }
        }
        if apiURL == nil {
            let apiURL = "http://www.gr3yR0n1n.com/aerial/videos/entries.json"
            defaults.set(apiURL as NSString, forKey: "apiURL")
        }
        */
        
        let apiURL = loadapiURL()
        
        if apiURL == nil {
            let apiURL = "http://www.gr3yR0n1n.com/aerial/videos/entries.json"
        }
        
        //data.setObject("http://www.gr3yR0n1n.com/aerial/videos/entries.json", forKey: "apiURL")
        //data.writeToFile(path, atomically: true)
        
        let url = URL(string: apiURL!)
        
        
        // use ephemeral session so when we load json offline it fails and puts us in offline mode
        let configuration = URLSessionConfiguration.ephemeral
        let session = URLSession(configuration: configuration)
        let task = session.dataTask(with: url!, completionHandler: completionHandler)
        task.resume()
    }
    
    func loadSavedManifest() {
        guard let savedJSON = preferences.manifest else {
            debugLog("Couldn't find saved manifest")
            return
        }
        
        offlineMode = true
        readJSONFromData(savedJSON)
    }
    
    func loadapiURL() -> String? {
        let paths = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true) as NSArray
        let documentDirectory = paths[0] as! String
        let path = documentDirectory.appending("/aerial.plist")
        let fileManager = FileManager.default
        if(!fileManager.fileExists(atPath: path)){
            if let bundlePath = Bundle.main.path(forResource: "aerial", ofType: "plist"){
                let result = NSMutableDictionary(contentsOfFile: bundlePath)
                print("Bundle file myData.plist is -> \(result?.description)")
                do{
                    try fileManager.copyItem(atPath: bundlePath, toPath: path)
                }catch{
                    print("copy failure.")
                }
            }else{
                print("file aerial.plist not found.")
            }
        }else{
            print("file aerial.plist already exits at path.")
        }
        
        let resultDictionary = NSMutableDictionary(contentsOfFile: path)
        print("load aerial.plist is ->\(resultDictionary?.description)")
        
        let myDict = NSDictionary(contentsOfFile: path)
        if let dict = myDict{
            return dict.object(forKey: "apiURL") as! String?
        }else{
            print("load failure.")
            return nil
        }
    }
    
    func readJSONFromData(_ data: Data) {
        var videos = [AerialVideo]()
        
        do {
            let options = JSONSerialization.ReadingOptions.allowFragments
            let batches = try JSONSerialization.jsonObject(with: data,
                                                           options: options) as! Array<NSDictionary>
            
            for batch: NSDictionary in batches {
                let assets = batch["assets"] as! Array<NSDictionary>
                
                for item in assets {
                    let url = item["url"] as! String
                    let name = item["accessibilityLabel"] as! String
                    let timeOfDay = item["timeOfDay"] as! String
                    let id = item["id"] as! String
                    let type = item["type"] as! String
                    
                    if type != "video" {
                        continue
                    }
                    
                    let video = AerialVideo(id: id,
                                            name: name,
                                            type: type,
                                            timeOfDay: timeOfDay,
                                            url: url)
                    
                    videos.append(video)
                    
                    checkContentLength(video)
                }
            }
            
            self.loadedManifest = videos
        } catch {
            NSLog("Aerial: Error retrieving content listing.")
            return
        }
    }
    
    func checkContentLength(_ video: AerialVideo) {
        let config = URLSessionConfiguration.default
        let session = URLSession(configuration: config)
        let request = NSMutableURLRequest(url: video.url as URL)
        request.httpMethod = "HEAD"
        
        let task = session.dataTask(with: request as URLRequest,
                                    completionHandler: {
                                        data, response, error in
            video.contentLengthChecked = true
            
            if let error = error {
                NSLog("error fetching content length: \(error)")
                DispatchQueue.main.async(execute: { () -> Void in
                    self.receivedContentLengthResponse()
                })
                return
            }
            
            guard let response = response else {
                return
            }
            
            video.contentLength = Int(response.expectedContentLength)
//            NSLog("content length: \(response.expectedContentLength)")
            DispatchQueue.main.async(execute: { () -> Void in
                self.receivedContentLengthResponse()
            })
        }) 
        
        task.resume()
    }
    
    func receivedContentLengthResponse() {
        // check if content length on all videos has been checked
        for video in loadedManifest {
            if video.contentLengthChecked == false {
                return
            }
        }
        
        filterVideoAndProcessCallbacks()
    }
    
    func filterVideoAndProcessCallbacks() {
        let unfiltered = loadedManifest
        
        var filtered = [AerialVideo]()
        for video in unfiltered {
            // offline? eror? just put it through
            if video.contentLength == 0 {
                filtered.append(video)
                continue
            }
            
            // check to see if we find another video with the same content length
            var isDuplicate = false
            for videoCheck in filtered {
                if videoCheck.id == video.id {
                    isDuplicate = true
                    continue
                }
                
                if videoCheck.name != video.name {
                    continue
                }
                
                if videoCheck.timeOfDay != video.timeOfDay {
                    continue
                }
                
                if videoCheck.contentLength == video.contentLength {
//                    NSLog("removing duplicate video \(videoCheck.name) \(videoCheck.timeOfDay)")
                    isDuplicate = true
                    break
                }
            } // dupe check
            
            if isDuplicate == true {
                continue
            }
            
            filtered.append(video)
        }
        
        loadedManifest = filtered
        
        // callbacks
        for callback in self.callbacks {
            callback(filtered)
        }
        self.callbacks.removeAll()
    }
}
