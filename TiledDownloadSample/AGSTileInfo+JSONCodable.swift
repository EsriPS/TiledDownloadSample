// Copyright 2021 Esri.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//   http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import ArcGIS

// MARK: Codable classes

struct TileInfo {
    let dpi: Int
    let tileWidth: Int
    let tileHeight: Int
    let format: AGSTileImageFormat
    let compressionQuality: Int

    let origin: AGSPoint
    var spatialReference: AGSSpatialReference {
        return origin.spatialReference ?? AGSSpatialReference.webMercator()
    }

    let lods: [AGSLevelOfDetail]
    
    var agsTileInfo: AGSTileInfo {
        let agsTI = AGSTileInfo(
            dpi: dpi,
            format: format,
            levelsOfDetail: lods,
            origin: origin,
            spatialReference: spatialReference,
            tileHeight: tileHeight,
            tileWidth: tileWidth
        )
        return agsTI
    }
}

extension TileInfo: Codable {
    enum CodingKeys: String, CodingKey {
        case dpi
        case tileWidth = "cols"
        case tileHeight = "rows"
        case format
        case compressionQuality
        case origin
        case spatialReference
        case lods
    }
    
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        
        dpi = try values.decode(Int.self, forKey: .dpi)
        tileWidth = try values.decode(Int.self, forKey: .tileWidth)
        tileHeight = try values.decode(Int.self, forKey: .tileHeight)
        let formatStr = try values.decode(String.self, forKey: .format)
        format = AGSTileImageFormat.tileFormatFrom(string: formatStr)
        compressionQuality = try values.decode(Int.self, forKey: .compressionQuality)

        let parsedOrigin = try values.decode(Point.self, forKey: .origin)
        let parsedSR = try values.decode(SpatialReference.self, forKey: .spatialReference)
        origin = parsedOrigin.agsPoint(spatialReference: parsedSR.agsSpatialReference)

        let lodStructs = try values.decode([LODLevel].self, forKey: .lods)
        lods = lodStructs.map({ $0.agsLevelOfDetail })
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(dpi, forKey: .dpi)
        try container.encode(tileWidth, forKey: .tileWidth)
        try container.encode(tileHeight, forKey: .tileHeight)
        try container.encode(format.encodable, forKey: .format)
        try container.encode(compressionQuality, forKey: .compressionQuality)

        try container.encode(origin.encodable, forKey: .origin)
        try container.encode(origin.spatialReference?.encodable, forKey: .spatialReference)
        
        try container.encode(lods.map({ $0.encodable }), forKey: .lods)
    }
}

struct TileFormat: Codable {
    let format: AGSTileImageFormat
    
    init(from decoder: Decoder) throws {
        let formatString = try decoder.singleValueContainer().decode(String.self)
        format = AGSTileImageFormat.tileFormatFrom(string: formatString)
    }
    
    func encode(to encoder: Encoder) throws {
        var e = encoder.singleValueContainer()
        try e.encode(format.encodable)
    }
}

struct LODLevel: Codable {
    let level: Int
    let resolution: Double
    let scale: Double

    init(from agsLod: AGSLevelOfDetail) {
        level = agsLod.level
        resolution = agsLod.resolution
        scale = agsLod.scale
    }

    var agsLevelOfDetail: AGSLevelOfDetail {
        return AGSLevelOfDetail(
            level: level,
            resolution: resolution,
            scale: scale)
    }
}

struct Point: Codable {
    let x: Double
    let y: Double
    let z: Double?
    let m: Double?
    let spatialReference: SpatialReference?
    
    init(x: Double, y: Double, z: Double?, m: Double?, spatialReference: SpatialReference?) {
        self.x = x
        self.y = y
        self.z = z
        self.m = m
        self.spatialReference = spatialReference
    }
    
    enum CodingKeys: String, CodingKey {
        case x
        case y
    }
    
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        
        x = try values.decode(Double.self, forKey: .x)
        y = try values.decode(Double.self, forKey: .y)
        z = nil
        m = nil
        spatialReference = nil
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(x, forKey: .x)
        try container.encode(y, forKey: .y)
    }

    func agsPoint(spatialReference sr: AGSSpatialReference? = nil) -> AGSPoint {
        return AGSPoint(x: x, y: y, spatialReference: sr ?? spatialReference?.agsSpatialReference)
    }
}

struct SpatialReference: Codable {
    let wkid: Int
    let latestWKID: Int?
    let verticalWKID: Int?
    let wkText: String?

    enum CodingKeys: String, CodingKey {
        case wkid
        case latestWKID = "latestWkid"
        case verticalWKID = "verticalWkid"
        case wkText
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        
        wkid = try values.decodeIfPresent(Int.self, forKey: .wkid) ?? 0
        latestWKID = try values.decodeIfPresent(Int.self, forKey: .latestWKID)
        verticalWKID = try values.decodeIfPresent(Int.self, forKey: .verticalWKID)
        if wkid == 0 {
            wkText = try values.decodeIfPresent(String.self, forKey: .wkText)
        } else {
            wkText = nil
        }
    }

    init(from sr: AGSSpatialReference) {
        wkid = sr.wkid
        verticalWKID = sr.hasVertical ? sr.verticalWKID : nil
        if wkid == 102100 {
            latestWKID = 3857
        } else {
            latestWKID = nil
        }
        
        if wkid == 0 {
            wkText = sr.wkText
        } else {
            wkText = nil
        }
    }
    
    var agsSpatialReference: AGSSpatialReference {
        let bestSR: AGSSpatialReference? = {
            if let wkText = wkText, !wkText.isEmpty {
                return AGSSpatialReference(wkText: wkText)
            } else {
                if let verticalWKID = verticalWKID {
                    return AGSSpatialReference(wkid: wkid, verticalWKID: verticalWKID)
                } else {
                    return AGSSpatialReference(wkid: wkid)
                }
            }
        }()
        
        return bestSR ?? AGSSpatialReference.wgs84()
    }
    
}


// MARK: AGS Encodable Extensions

extension AGSTileInfo {
    var encodable: TileInfo {
        return TileInfo(
            dpi: self.dpi,
            tileWidth: self.tileWidth,
            tileHeight: self.tileHeight,
            format: self.format,
            compressionQuality: 75,
            origin: self.origin,
            lods: self.levelsOfDetail)
    }
}

extension AGSTileImageFormat {
    var encodable: String {
        switch self {
            case .JPG:
                return "JPEG"
            case .PNG:
                return "PNG"
            case .PNG8:
                return "PNG8"
            case .PNG24:
                return "PNG24"
            case .PNG32:
                return "PNG32"
            case .MIXED:
                return "MIXED"
            case .LERC:
                return "LERC"
            default:
                return "BMP"
        }
    }
}

extension AGSPoint {
    var encodable: Point {
        let encodableSR = spatialReference?.encodable
        if hasZ {
            if hasM {
                return Point(x: x, y: y, z: z, m: m, spatialReference: encodableSR)
            } else {
                return Point(x: x, y: y, z: z, m: nil, spatialReference: encodableSR)
            }
        } else if hasM {
            return Point(x: x, y: y, z: nil, m: m, spatialReference: encodableSR)
        } else {
            return Point(x: x, y: y, z: nil, m: nil, spatialReference: encodableSR)
        }
    }
}

extension AGSSpatialReference {
    var encodable: SpatialReference {
        return SpatialReference(from: self)
    }
}

extension AGSLevelOfDetail {
    var encodable: LODLevel {
        return LODLevel(from: self)
    }
}

// MARK: Decoding Helpers

extension AGSTileImageFormat {
    static func tileFormatFrom(string: String) -> AGSTileImageFormat {
        switch string.uppercased() {
            case "JPEG", "JPG":
                return .JPG
            case "PNG32":
                return .PNG32
            case "PNG24":
                return .PNG24
            case "PNG8":
                return .PNG8
            case "PNG":
                return .PNG
            case "MIXED":
                return .MIXED
            case "LERC":
                return .LERC
            default:
                return .unknown
        }
    }
}

// MARK: Test data

public func testDecodeEncode() {
    let decoder = JSONDecoder()
    let data = tileInfoJSONSample.data(using: .utf8)!
    do {
        let ti2 = try decoder.decode(TileInfo.self, from: data)
        print(ti2)
        let ti3 = ti2.agsTileInfo
        print(ti3)
        
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        let encoded = try enc.encode(ti3.encodable)
        let encodedStr = String(data: encoded, encoding: .utf8)
        print(encodedStr)
    } catch {
        print("Error decoding: \(error)")
    }
    print("Did a decode")
}

public let tileInfoJSONSample = """
{
    "rows": 256,
    "cols": 256,
    "dpi": 96,
    "format": "JPEG",
    "compressionQuality": 75,
    "origin": {
      "x": -20037508.342787,
      "y": 20037508.342787
    },
    "spatialReference": {
      "wkid": 102100,
      "latestWkid": 3857
    },
    "lods": [
      {
        "level": 0,
        "resolution": 156543.03392800014,
        "scale": 591657527.591555
      },
      {
        "level": 1,
        "resolution": 78271.51696399994,
        "scale": 295828763.795777
      },
      {
        "level": 2,
        "resolution": 39135.75848200009,
        "scale": 147914381.897889
      },
      {
        "level": 3,
        "resolution": 19567.87924099992,
        "scale": 73957190.948944
      },
      {
        "level": 4,
        "resolution": 9783.93962049996,
        "scale": 36978595.474472
      },
      {
        "level": 5,
        "resolution": 4891.96981024998,
        "scale": 18489297.737236
      },
      {
        "level": 6,
        "resolution": 2445.98490512499,
        "scale": 9244648.868618
      },
      {
        "level": 7,
        "resolution": 1222.992452562495,
        "scale": 4622324.434309
      },
      {
        "level": 8,
        "resolution": 611.4962262813797,
        "scale": 2311162.217155
      },
      {
        "level": 9,
        "resolution": 305.74811314055756,
        "scale": 1155581.108577
      },
      {
        "level": 10,
        "resolution": 152.87405657041106,
        "scale": 577790.554289
      },
      {
        "level": 11,
        "resolution": 76.43702828507324,
        "scale": 288895.277144
      },
      {
        "level": 12,
        "resolution": 38.21851414253662,
        "scale": 144447.638572
      },
      {
        "level": 13,
        "resolution": 19.10925707126831,
        "scale": 72223.819286
      },
      {
        "level": 14,
        "resolution": 9.554628535634155,
        "scale": 36111.909643
      },
      {
        "level": 15,
        "resolution": 4.77731426794937,
        "scale": 18055.954822
      },
      {
        "level": 16,
        "resolution": 2.388657133974685,
        "scale": 9027.977411
      },
      {
        "level": 17,
        "resolution": 1.1943285668550503,
        "scale": 4513.988705
      },
      {
        "level": 18,
        "resolution": 0.5971642835598172,
        "scale": 2256.994353
      },
      {
        "level": 19,
        "resolution": 0.29858214164761665,
        "scale": 1128.497176
      },
      {
        "level": 20,
        "resolution": 0.14929107082380833,
        "scale": 564.248588
      },
      {
        "level": 21,
        "resolution": 0.07464553541190416,
        "scale": 282.124294
      },
      {
        "level": 22,
        "resolution": 0.03732276770595208,
        "scale": 141.062147
      },
      {
        "level": 23,
        "resolution": 0.01866138385297604,
        "scale": 70.5310735
      }
    ]
}
"""
