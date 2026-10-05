import Foundation

/// One station from `GET /api/stations/nearest` (a GeoJSON feature, flattened).
struct Station: Equatable, Sendable {
    let id: String
    let externalId: String
    let country: String
    let name: String
    let brand: String?
    let city: String
    let latitude: Double
    let longitude: Double
    let price: Double?
    let currency: String
    let distanceKm: Double
    let powerKw: Double?
}

private struct FeatureCollection: Decodable {
    struct Feature: Decodable {
        struct Geometry: Decodable { let coordinates: [Double] }
        struct Properties: Decodable {
            let id: String
            let externalId: String
            let country: String
            let name: String
            let brand: String?
            let city: String
            let price: Double?
            let currency: String
            let distanceKm: Double
            let powerKw: Double?
        }
        let geometry: Geometry
        let properties: Properties
    }
    let features: [Feature]
}

enum StationsAPI {
    static let radiusKm = 10.0
    static let limit = 20

    /// Rounds a coordinate to 3 decimals (about 110 m) before it leaves the device.
    static func round(_ value: Double) -> Double {
        (value * 1000).rounded() / 1000
    }

    static func nearestURL(latitude: Double, longitude: Double, fuel: FuelType,
                           base: URL = AppConfig.baseURL) -> URL {
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        components.path = "/api/stations/nearest"
        components.queryItems = [
            URLQueryItem(name: "lat", value: String(round(latitude))),
            URLQueryItem(name: "lon", value: String(round(longitude))),
            URLQueryItem(name: "radius_km", value: String(Int(radiusKm))),
            URLQueryItem(name: "fuel", value: fuel.rawValue),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        return components.url!
    }

    static func decode(_ data: Data) throws -> [Station] {
        try JSONDecoder().decode(FeatureCollection.self, from: data).features.compactMap { feature in
            let coords = feature.geometry.coordinates
            guard coords.count >= 2 else { return nil }
            let p = feature.properties
            return Station(id: p.id, externalId: p.externalId, country: p.country, name: p.name,
                           brand: p.brand, city: p.city, latitude: coords[1], longitude: coords[0],
                           price: p.price, currency: p.currency, distanceKm: p.distanceKm, powerKw: p.powerKw)
        }
    }

    static func fetchNearest(latitude: Double, longitude: Double, fuel: FuelType,
                             session: URLSession = .shared) async throws -> [Station] {
        var request = URLRequest(url: nearestURL(latitude: latitude, longitude: longitude, fuel: fuel))
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(UserAgent.widgetUserAgent(version: AppConfig.appVersion), forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try decode(data)
    }

    /// The station's page on the site: `/?station=CC:externalId&lat=..&lng=..`
    /// (the share format in GeiserX/Pumperly `src/lib/share-url.ts`).
    static func pageURL(for station: Station, base: URL = AppConfig.baseURL) -> URL {
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        components.path = "/"
        components.queryItems = [
            URLQueryItem(name: "station", value: "\(station.country.uppercased()):\(station.externalId)"),
            URLQueryItem(name: "lat", value: String((station.latitude * 1e5).rounded() / 1e5)),
            URLQueryItem(name: "lng", value: String((station.longitude * 1e5).rounded() / 1e5)),
        ]
        return components.url!
    }
}
