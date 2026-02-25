import Foundation
import UIKit
import Contacts
import CoreLocation
import MessageUI
import EventKit
import EventKitUI

@MainActor
final class ActionManager: NSObject, ObservableObject {
    private let contactStore = CNContactStore()
    private let eventStore = EKEventStore()

    private var locationManager: CLLocationManager?
    private var locationAuthContinuation: CheckedContinuation<Bool, Never>?
    private var locationContinuation: CheckedContinuation<CLLocation?, Never>?

    func execute(_ intent: SmartIntent) async {
        switch intent {
        case .addSchedule(let parsed):
            await presentScheduleEditor(with: parsed)
        case .sendMessage(let targetName, let message, let isCurrentLocation):
            await presentMessageComposer(targetName: targetName, message: message, isCurrentLocation: isCurrentLocation)
        case .navigation(let destination):
            await openNavigation(destination: destination)
        case .webSearch(let query, let type):
            openWebSearch(query: query, type: type)
        case .unknown:
            break
        }
    }
}

// MARK: - Navigation
private extension ActionManager {
    struct KakaoLocalResponseDTO: Decodable {
        let documents: [KakaoPlaceDTO]
    }

    struct KakaoPlaceDTO: Decodable {
        let x: String
        let y: String
    }

    func openNavigation(destination: String) async {
        let trimmed = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let encodedName = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed

        if let place = await fetchKakaoCoordinate(for: trimmed),
           let tmapURL = URL(string: "tmap://?rGoName=\(encodedName)&rGoY=\(place.y)&rGoX=\(place.x)") {
            let opened = await openURL(tmapURL)
            if opened { return }
        }

        if let fallbackURL = URL(string: "kakaomap://search?q=\(encodedName)") {
            _ = await openURL(fallbackURL)
        }
    }

    func fetchKakaoCoordinate(for destination: String) async -> KakaoPlaceDTO? {
        let encoded = destination.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? destination
        guard let url = URL(string: "https://dapi.kakao.com/v2/local/search/keyword.json?query=\(encoded)") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("KakaoAK YOUR_REST_API_KEY", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }
            let decoded = try JSONDecoder().decode(KakaoLocalResponseDTO.self, from: data)
            return decoded.documents.first
        } catch {
            return nil
        }
    }
}

// MARK: - Message
private extension ActionManager {
    func presentMessageComposer(targetName: String, message: String, isCurrentLocation: Bool) async {
        guard MFMessageComposeViewController.canSendText() else { return }

        let recipient = await findPhoneNumber(for: targetName)
        var body = message

        if isCurrentLocation, let location = await fetchCurrentLocation() {
            let lat = location.coordinate.latitude
            let lng = location.coordinate.longitude
            body += "\n\n현위치: https://map.kakao.com/link/map/현위치,\(lat),\(lng)"
        }

        let composer = MFMessageComposeViewController()
        composer.messageComposeDelegate = self
        composer.body = body

        if let recipient {
            composer.recipients = [recipient]
        }

        guard let presenter = topViewController() else { return }
        presenter.present(composer, animated: true)
    }

    func findPhoneNumber(for targetName: String) async -> String? {
        let granted = await requestContactsAccessIfNeeded()
        guard granted else { return nil }

        let keys: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor
        ]

        let predicate = CNContact.predicateForContacts(matchingName: targetName)

        do {
            let contacts = try contactStore.unifiedContacts(matching: predicate, keysToFetch: keys)
            for contact in contacts {
                if let mobile = contact.phoneNumbers.first(where: { $0.label == CNLabelPhoneNumberMobile }) {
                    return mobile.value.stringValue
                }
                if let first = contact.phoneNumbers.first {
                    return first.value.stringValue
                }
            }
            return nil
        } catch {
            return nil
        }
    }

    func requestContactsAccessIfNeeded() async -> Bool {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                contactStore.requestAccess(for: .contacts) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }

    func fetchCurrentLocation() async -> CLLocation? {
        guard CLLocationManager.locationServicesEnabled() else { return nil }

        let manager = locationManager ?? CLLocationManager()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager = manager

        let authorized = await ensureLocationAuthorization(with: manager)
        guard authorized else { return nil }

        return await withCheckedContinuation { continuation in
            self.locationContinuation = continuation
            manager.requestLocation()
        }
    }

    func ensureLocationAuthorization(with manager: CLLocationManager) async -> Bool {
        let status = manager.authorizationStatus
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                self.locationAuthContinuation = continuation
                manager.requestWhenInUseAuthorization()
            }
        @unknown default:
            return false
        }
    }
}

// MARK: - Schedule
private extension ActionManager {
    func presentScheduleEditor(with parsed: ParsedSchedule) async {
        let granted = await requestCalendarAccessIfNeeded()
        guard granted else { return }

        let event = EKEvent(eventStore: eventStore)
        event.title = parsed.title
        event.startDate = parsed.start
        event.endDate = parsed.end ?? parsed.start.addingTimeInterval(3600)
        event.isAllDay = parsed.allDay
        event.location = parsed.location
        event.calendar = eventStore.defaultCalendarForNewEvents

        let editor = EKEventEditViewController()
        editor.eventStore = eventStore
        editor.event = event
        editor.editViewDelegate = self

        guard let presenter = topViewController() else { return }
        presenter.present(editor, animated: true)
    }

    func requestCalendarAccessIfNeeded() async -> Bool {
        if #available(iOS 17.0, *) {
            do {
                return try await eventStore.requestFullAccessToEvents()
            } catch {
                return false
            }
        } else {
            return await withCheckedContinuation { continuation in
                eventStore.requestAccess(to: .event) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
        }
    }
}

// MARK: - Web Search
private extension ActionManager {
    func openWebSearch(query: String, type: SearchType) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return
        }

        let urlString: String
        switch type {
        case .naver:
            urlString = "https://m.search.naver.com/search.naver?sm=mtp_hty.top&where=m&query=\(encoded)"
        case .youtube:
            urlString = "https://www.youtube.com/results?search_query=\(encoded)"
        case .netflix:
            urlString = "https://www.netflix.com/search?q=\(encoded)"
        case .tmdb:
            urlString = "https://www.themoviedb.org/search?language=ko&query=\(encoded)"
        case .appstore:
            urlString = "itms-apps://search.itunes.apple.com/WebObjects/MZSearch.woa/wa/search?media=software&term=\(encoded)"
        case .dictionary:
            urlString = "https://m.search.naver.com/search.naver?where=m_ldic&sm=mtb_jum&query=\(encoded)"
        }

        guard let url = URL(string: urlString) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - Presentation / URL
private extension ActionManager {
    func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }

        guard let root = scenes
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow })?
            .rootViewController else {
            return nil
        }

        var top = root
        while true {
            if let presented = top.presentedViewController {
                top = presented
                continue
            }
            if let nav = top as? UINavigationController, let visible = nav.visibleViewController {
                top = visible
                continue
            }
            if let tab = top as? UITabBarController, let selected = tab.selectedViewController {
                top = selected
                continue
            }
            break
        }
        return top
    }

    func openURL(_ url: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            UIApplication.shared.open(url, options: [:]) { success in
                continuation.resume(returning: success)
            }
        }
    }
}

// MARK: - CLLocationManagerDelegate
extension ActionManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        Task { @MainActor in
            switch status {
            case .authorizedAlways, .authorizedWhenInUse:
                locationAuthContinuation?.resume(returning: true)
                locationAuthContinuation = nil
            case .denied, .restricted:
                locationAuthContinuation?.resume(returning: false)
                locationAuthContinuation = nil
            case .notDetermined:
                break
            @unknown default:
                locationAuthContinuation?.resume(returning: false)
                locationAuthContinuation = nil
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            locationContinuation?.resume(returning: locations.last)
            locationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            locationContinuation?.resume(returning: nil)
            locationContinuation = nil
        }
    }
}

// MARK: - MFMessageComposeViewControllerDelegate
extension ActionManager: MFMessageComposeViewControllerDelegate {
    nonisolated func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
        Task { @MainActor in
            controller.dismiss(animated: true)
        }
    }
}

// MARK: - EKEventEditViewDelegate
extension ActionManager: EKEventEditViewDelegate {
    nonisolated func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
        Task { @MainActor in
            controller.dismiss(animated: true)
        }
    }
}
