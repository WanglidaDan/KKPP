import CoreLocation
import Foundation

@MainActor
final class LocationWeatherManager: NSObject, ObservableObject {
    struct CurrentWeather: Decodable {
        let time: String
        let temperature_2m: Double
        let apparent_temperature: Double
        let weather_code: Int
        let is_day: Int
    }

    struct DailyWeather: Decodable {
        let time: [String]
        let weather_code: [Int]
        let temperature_2m_max: [Double]
        let temperature_2m_min: [Double]
    }

    struct WeatherResponse: Decodable {
        let current: CurrentWeather
        let daily: DailyWeather?
    }

    struct DayForecast: Identifiable, Equatable {
        let id: String
        let date: Date
        let weatherCode: Int
        let maxTemperature: Double
        let minTemperature: Double
    }

    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var cityName = "未定位"
    @Published private(set) var districtName = ""
    @Published private(set) var weatherSummary = "天气待获取"
    @Published private(set) var temperatureText = "--"
    @Published private(set) var isLoading = false
    @Published private(set) var lastUpdatedAt: Date?
    @Published private(set) var latitude: Double?
    @Published private(set) var longitude: Double?
    @Published private(set) var forecasts: [DayForecast] = []

    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private let session = URLSession.shared

    override init() {
        authorizationStatus = locationManager.authorizationStatus
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    var hasLocationAccess: Bool {
        authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse
    }

    var locationSummary: String {
        let parts = [cityName, districtName].filter { !$0.isEmpty && $0 != "未定位" }
        return parts.isEmpty ? "未定位" : parts.joined(separator: " · ")
    }

    func refresh() {
        authorizationStatus = locationManager.authorizationStatus
        guard hasLocationAccess else { return }
        isLoading = true
        locationManager.requestLocation()
    }

    func requestWhenInUseAccess() {
        locationManager.requestWhenInUseAuthorization()
    }

    func ensureAccessAndRefresh() {
        authorizationStatus = locationManager.authorizationStatus
        switch authorizationStatus {
        case .notDetermined:
            requestWhenInUseAccess()
        case .authorizedAlways, .authorizedWhenInUse:
            refresh()
        default:
            break
        }
    }

    func formattedTimeString(for date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "M月d日 EEEE HH:mm"
        return formatter.string(from: date)
    }

    func forecast(for date: Date) -> DayForecast? {
        let calendar = Calendar(identifier: .gregorian)
        return forecasts.first { calendar.isDate($0.date, inSameDayAs: date) }
    }

    private func reverseGeocode(_ location: CLLocation) async {
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            guard let placemark = placemarks.first else { return }
            cityName = placemark.locality ?? placemark.administrativeArea ?? "当前位置"
            districtName = placemark.subLocality ?? placemark.subAdministrativeArea ?? ""
        } catch {
            cityName = "当前位置"
            districtName = ""
        }
    }

    private func fetchWeather(for location: CLLocation) async {
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude

        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(location.coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(location.coordinate.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,weather_code,is_day"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "timezone", value: "auto")
        ]

        guard let url = components?.url else {
            isLoading = false
            return
        }

        do {
            let (data, _) = try await session.data(from: url)
            let response = try JSONDecoder().decode(WeatherResponse.self, from: data)
            temperatureText = "\(Int(response.current.temperature_2m.rounded()))°"
            weatherSummary = Self.weatherDescription(code: response.current.weather_code, isDay: response.current.is_day == 1)
            forecasts = Self.buildForecasts(from: response.daily)
            lastUpdatedAt = Date()
        } catch {
            weatherSummary = "天气获取失败"
        }

        isLoading = false
    }

    private static func weatherDescription(code: Int, isDay: Bool) -> String {
        switch code {
        case 0: return isDay ? "晴朗" : "晴夜"
        case 1, 2: return isDay ? "晴间多云" : "少云"
        case 3: return "阴天"
        case 45, 48: return "有雾"
        case 51, 53, 55: return "毛毛雨"
        case 56, 57: return "冻毛雨"
        case 61, 63, 65: return "下雨"
        case 66, 67: return "冻雨"
        case 71, 73, 75, 77: return "下雪"
        case 80, 81, 82: return "阵雨"
        case 85, 86: return "阵雪"
        case 95: return "雷暴"
        case 96, 99: return "强雷暴"
        default: return "天气稳定"
        }
    }

    private static func buildForecasts(from daily: DailyWeather?) -> [DayForecast] {
        guard let daily else { return [] }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]

        return daily.time.enumerated().compactMap { index, value in
            guard let date = formatter.date(from: value),
                  daily.weather_code.indices.contains(index),
                  daily.temperature_2m_max.indices.contains(index),
                  daily.temperature_2m_min.indices.contains(index) else {
                return nil
            }

            return DayForecast(
                id: value,
                date: date,
                weatherCode: daily.weather_code[index],
                maxTemperature: daily.temperature_2m_max[index],
                minTemperature: daily.temperature_2m_min[index]
            )
        }
    }
}

extension LocationWeatherManager: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus
            if hasLocationAccess {
                refresh()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            isLoading = false
            weatherSummary = "定位失败"
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            Task { @MainActor in
                isLoading = false
            }
            return
        }

        Task { @MainActor in
            await reverseGeocode(location)
            await fetchWeather(for: location)
        }
    }
}
