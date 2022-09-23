//
//  ViewController.swift
//
//  Created by Travis Butcher on 3/23/21.
//  Copyright © 2021 Travis Butcher. All rights reserved.
//

import UIKit
import ArcGIS

class ViewController: UIViewController {
    @IBOutlet weak var mapView: AGSMapView!
    @IBOutlet weak var extentView: UIView!
    @IBOutlet weak var goOfflineButtonItem: UIBarButtonItem!
    
    @IBOutlet weak var smallButtonItem: UIBarButtonItem!
    @IBOutlet weak var mediumButtonItem: UIBarButtonItem!
    @IBOutlet weak var largeButtonItem: UIBarButtonItem!
    @IBOutlet weak var progressView: UIProgressView!
    @IBOutlet weak var progressLabel: UILabel!
    
    private var portal: AGSPortal?
    private var offlineMapTask: AGSOfflineMapTask?
    private var generateOfflineMapJob: AGSGenerateOfflineMapJob?
    private var parameters: AGSGenerateOfflineMapParameters?
    private var parameterOverrides: AGSGenerateOfflineMapParameterOverrides?
    private var progressObservation: NSKeyValueObservation?
    private var portalItem: AGSPortalItem?
    private var portalItem2: AGSPortalItem?
    
    private var small = Array(8...14) as [NSNumber];
    private var medium = Array(8...16) as [NSNumber];
    private var large = Array(8...18) as [NSNumber];
    
    private var docsDirectory: URL?
    private var tlDirectoryName = "Topographic"
    private var tilesDirectory: URL?
    
    private var tileExtension = "jpeg"
    
    //Add full offline to sample
    //Check metadata service for imagery (check area of interest for newer data)
    private var offlineMode: Bool = false
    
    var tileInfo: AGSTileInfo?
    let fileManager = FileManager.default
    
    //Add option for topo maps
    let layerURL = URL(string: "https://ibasemaps-api.arcgis.com/arcgis/rest/services/World_Imagery/MapServer/")
    //let layerURL = URL(string: "https://ibasemaps-api.arcgis.com/arcgis/rest/services/World_Basemap_v2/VectorTileServer/")
    
    let apikey = ""
    let imageryService = AGSArcGISTiledLayer(url:URL(string:"https://ibasemaps-api.arcgis.com/arcgis/rest/services/World_Imagery/MapServer/")!)
    
    override func viewDidLoad() {
        self.mapView.map = AGSMap()
        self.mapView.setViewpoint(
            AGSViewpoint(
                latitude: 47.1595,
                longitude: -122.8071,
                scale: 64_000
            )
        )
        
        self.docsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        self.tilesDirectory = docsDirectory!.appendingPathComponent(self.tlDirectoryName).appendingPathComponent("tile")
        self.setupMap()
        self.imageryService.apiKey = "AAPK30e5f0cb13734af790a9d9ff7d07c384OAsShCo6wE3jTVxPVHgCAihbKPvY8qa-k502j5YhbVkuk_mAFurCHS36FR8x6QCw"
        super.viewDidLoad()
    }
    
    private func setupMap() {
        
        self.imageryService.load { [weak self] (error) in
            guard let self = self else { return }
            
            if let error = error {
                print("Error loading layer: \(error.localizedDescription)")
                return
            }
            if(!self.offlineMode) {
                let tileInfo = self.imageryService.tileInfo
                let fullExtent = self.imageryService.fullExtent
                
                let customLayer = CustomImageTiledLayer(layerURL: self.imageryService.url!,
                                                        tileInfo: tileInfo!,
                                                        fullExtent: fullExtent!,
                                                        offlineMode: self.offlineMode)
                
                // This highlights how tiles are not retrieved
                customLayer.noDataTileBehavior = .blank
                
                let basemap = AGSBasemap(baseLayer: customLayer)
                self.mapView.map = AGSMap(basemap: basemap)
            }
            else {
                do {
                    let tileInfoJSON = self.docsDirectory!.appendingPathComponent(self.tlDirectoryName).appendingPathComponent("tileinfo.json")
                    let jsonData = try String(contentsOfFile: tileInfoJSON.path, encoding: .utf8)
                    let decoder = JSONDecoder()
                    let ti2 = try decoder.decode(TileInfo.self, from: jsonData.data(using: .utf8)!)
                    
                    let customLayer = CustomImageTiledLayer(layerURL: self.imageryService.url!,
                                                            tileInfo: ti2.agsTileInfo,
                                                            fullExtent: self.extentViewFrameToEnvelope(),
                                                            offlineMode: self.offlineMode)
                    
                    let basemap = AGSBasemap(baseLayer: customLayer)
                    self.mapView.map = AGSMap(basemap: basemap)
                } catch {
                    print("Error encoding tile info: \(error)")
                }
            }
            
            self.mapView.setViewpoint(
                AGSViewpoint(
                    latitude: 47.1595,
                    longitude: -122.8071,
                    scale: 64_000
                )
            )
        }
        
        //setup extent view
        extentView.layer.borderColor = UIColor.red.cgColor
        extentView.layer.borderWidth = 3
    }
    
    func downloadImageryTiles(for tileKeys: [AGSTileKey], completion: @escaping (Error?) -> Void) {
        imageryService.load { [weak self] (error) in
            guard let self = self else { return }
            
            if let error = error {
                completion(error)
                return
            }
            
            do {
                try self._downloadImageryTiles(for: tileKeys) { (error) in
                    completion(error)
                }
            } catch {
                print("Error downloading elevation tiles: \(error)")
                completion(error)
            }
        }
    }
    
    func _downloadImageryTiles(for tileKeys: [AGSTileKey], completion: @escaping (Error?) -> Void) throws {
        guard let url = imageryService.url else {
            completion(nil)
            return
        }
        
        try FileManager.default.createDirectory(
            at: self.tilesDirectory!,
            withIntermediateDirectories: true,
            attributes: nil
        )
        
        if let rc = AGSRequestConfiguration.global().copy() as? AGSRequestConfiguration {
            rc.debugLogResponses = true
            imageryService.requestConfiguration = rc
        }
        
        var downloadMessage = "Downloading " + String(tileKeys.count)
        var downloadedCount = 0
        progressLabel.text = downloadMessage
        progressView.progress = 0.0
        
        for tileKey in tileKeys {
            let operation = AGSRequestOperation(
                remoteResource: imageryService,
                url: url
                    .appendingPathComponent("tile")
                    .appendingPathComponent("\(tileKey.level)")
                    .appendingPathComponent("\(tileKey.row)")
                    .appendingPathComponent("\(tileKey.column)"),
                queryParameters: ["token": apikey])
            
            let lodDirectoryName = tileKey.level < 10 ? "L0\(tileKey.level)" : "L\(tileKey.level)"
            let lodDirectory = self.tilesDirectory!.appendingPathComponent(lodDirectoryName)
            try FileManager.default.createDirectory(
                at: lodDirectory,
                withIntermediateDirectories: true,
                attributes: nil
            )
            
            operation.outputFileURL = lodDirectory.appendingPathComponent("\(tileKey.row)_\(tileKey.column).jpeg")
            //Do we have this tile
            if(!fileManager.fileExists(atPath: operation.outputFileURL!.path)){
                print("fetching tile")
                operation.registerListener(self) { [self, tileKey] (_, error) in
                    if let error = error {
                        print("Error getting tile for key \(tileKey): \(error)")
                        return
                    }
                    print("Got tile data for \(tileKey)")
                    
                    downloadedCount = downloadedCount + 1
                    downloadMessage = "Downloaded " + String(downloadedCount) + " out of " + String(tileKeys.count)
                    self.progressLabel.text = downloadMessage
                    self.progressView.progress = Float(downloadedCount / tileKeys.count)
                }
                
                AGSOperationQueue.shared().addOperation(operation)
            } else {
                downloadedCount = downloadedCount + 1
                downloadMessage = "Downloaded " + String(downloadedCount) + " out of " + String(tileKeys.count)
                self.progressLabel.text = downloadMessage
                self.progressView.progress = Float(downloadedCount / tileKeys.count)
            }
        }
    }
    
    @IBAction func generateSmallOfflineMapAction() {
        //generateOverrides(levels: self.small)
        let areaOfInterest = extentViewFrameToEnvelope()
        let tileEnvelopes = self.calculateTiles(for: areaOfInterest, level: 16)
        
        try? self.downloadImageryTiles(for: Array(tileEnvelopes!.keys)) { (error) in
            if let error = error {
                print("Error downloading tiles: \(error.localizedDescription)")
                return
            }
        }
    }
    
    @IBAction func goOfflineMapAction() {
        //toggle the offline mode
        self.offlineMode = !self.offlineMode
        self.goOfflineButtonItem.title = self.offlineMode ? "Go Online" : "Go Offline"
        self.setupMap()
    }
    
    private func extentViewFrameToEnvelope() -> AGSEnvelope {
        let frame = mapView.convert(extentView.frame, from: view)
        
        //the lower-left corner
        let minPoint = mapView.screen(toLocation: frame.origin)
        
        //the upper-right corner
        let maxPoint = mapView.screen(toLocation: CGPoint(x: frame.maxX, y: frame.maxY))
        
        //return the envenlope covering the entire extent frame
        return AGSEnvelope(min: minPoint, max: maxPoint)
    }
    
    func overrideEnable(enabled: Bool){
        self.smallButtonItem.isEnabled = enabled
        self.mediumButtonItem.isEnabled = enabled
        self.largeButtonItem.isEnabled = enabled
    }
    
    func calculateTiles(for sourceExtent: AGSEnvelope, level: Int) -> [AGSTileKey: AGSEnvelope]? {
        var result = [AGSTileKey:AGSEnvelope]()
        let lods = [0,2,4,6,8,10,12,14,16,18]
        
        for lod in lods {
            guard let ti = self.imageryService.tileInfo,
                  let lod = ti.levelsOfDetail[lod] as? AGSLevelOfDetail,
                  let extent = AGSGeometryEngine.projectGeometry(
                    sourceExtent,
                    to: ti.spatialReference
                  ) as? AGSEnvelope else {
                return nil
            }
            
            let tileWidth = Double(ti.tileWidth) * lod.resolution
            let tileHeight = Double(ti.tileHeight) * lod.resolution
            
            let minCol = Int(floor((extent.xMin - ti.origin.x) / tileWidth)),
                minRow = Int(floor(-(extent.yMax - ti.origin.y) / tileHeight)),
                maxCol = Int(ceil((extent.xMax - ti.origin.x) / tileWidth))-1,
                maxRow = Int(ceil(-(extent.yMin - ti.origin.y) / tileHeight))-1
            
            for col in minCol...maxCol {
                for row in minRow...maxRow {
                    let env = AGSEnvelope(
                        xMin: ti.origin.x + (Double(col) * tileWidth),
                        yMin: ti.origin.y - (Double(row + 1) * tileHeight),
                        xMax: ti.origin.x + (Double(col + 1) * tileWidth),
                        yMax: ti.origin.y - (Double(row) * tileHeight),
                        spatialReference: ti.spatialReference
                    )
                    result[AGSTileKey(
                            level: lod.level,
                            column: col,
                            row: row)] = env
                }
            }
        }
        
        return result
    }
}


class CustomImageTiledLayer: AGSImageTiledLayer {
    let layerURL: URL
    let offlineMode:  Bool
    let apikey = "AAPK30e5f0cb13734af790a9d9ff7d07c384OAsShCo6wE3jTVxPVHgCAihbKPvY8qa-k502j5YhbVkuk_mAFurCHS36FR8x6QCw"
    
    private var docsDirectory: URL?
    private var tlDirectoryName = "Imagery"
    private var tilesDirectory: URL?
    
    private var tileCount = 0
    override var tileRequestHandler: ((AGSTileKey) -> Void)? {
        set {
            super.tileRequestHandler = newValue
        }
        get {
            return super.tileRequestHandler
        }
    }
    
    init(layerURL: URL, tileInfo: AGSTileInfo, fullExtent: AGSEnvelope, offlineMode: Bool) {
        self.layerURL = layerURL
        self.offlineMode = offlineMode
        
        super.init(tileInfo: tileInfo, fullExtent: fullExtent)
        
        docsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        tilesDirectory = docsDirectory!.appendingPathComponent(tlDirectoryName).appendingPathComponent("tile")
        
        tileRequestHandler = { [weak self] tileKey in
            self?.customHandler(tileKey: tileKey)
        }
    }
    
    private func customHandler(tileKey: AGSTileKey) -> Void {
        let lodDirectoryName = tileKey.level < 10 ? "L0\(tileKey.level)" : "L\(tileKey.level)"
        let lodDirectory = self.tilesDirectory!.appendingPathComponent(lodDirectoryName)
        let outTile = lodDirectory.appendingPathComponent("\(tileKey.row)_\(tileKey.column).jpeg")
        
        do {
            try FileManager.default.createDirectory(
                at: lodDirectory,
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            print("Error downloading tiles: \(error)")
        }
        
        let tileUrl = layerURL
            .appendingPathComponent("tile")
            .appendingPathComponent("\(tileKey.level)")
            .appendingPathComponent("\(tileKey.row)")
            .appendingPathComponent("\(tileKey.column)")
        
        if FileManager.default.fileExists(atPath: outTile.path) {
            print("tile exists at local source")
            do{
                let tileData = try Data(contentsOf: outTile)
                self.respond(with: tileKey, data: tileData, error: nil)
            } catch {
                print(error)
            }
        } else {
            if(!self.offlineMode) {
                print("downloading tile", outTile.absoluteString)
                // Piggy back on ArcGIS Authentication with AGSRequestOperation
                let tileOp = AGSRequestOperation(remoteResource: self.layerURL as? AGSRemoteResource, url: tileUrl, queryParameters: ["token": self.apikey])
                tileOp.outputFileURL = outTile
                
                tileOp.registerListener(self) { [weak self] (tileData, error) in
                    guard let self = self else { return }
                    do{
                        let tileData = try Data(contentsOf: tileOp.outputFileURL!)
                        self.respond(with: tileKey, data: tileData, error: nil)
                    } catch {
                        print(error)
                    }
                }
                AGSOperationQueue.shared().addOperation(tileOp)
            }
        }
    }
}



