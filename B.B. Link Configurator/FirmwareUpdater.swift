import CoreBluetooth
import Foundation
import UIKit
import CryptoKit

extension Notification.Name {
  static let firmwareUpdateAvailabilityChanged = Notification.Name(
    "firmwareUpdateAvailabilityChanged")
}

class FirmwareUpdater: NSObject, CBPeripheralDelegate {
  static let shared = FirmwareUpdater()

  var localVersion: String = ""
  var newVersionAvailable: Bool = false
  var newVersionURL: URL?
  var newVersion: String?
  var newVersionSha256: String?
  var progress: Progress?

  // Return firmware version check url for the given board
  // If the application preference is set to use the beta channel, return the beta url
  func urlForBoard(boardId: UInt8) -> URL? {
      var channel :String
    if UserDefaults.standard.bool(forKey: "useBetaChannel") {
      channel = "beta"
    } else {
      channel = "latest"
    }

    switch boardId {
    case 0x01:
      print("TinyPICO board detected")
      return URL(string: "https://islandmagic.github.io/bb-link/tinypico/\(channel).json")

    case 0x02:
      print("ESP32 PICO board detected")
      return URL(string: "https://islandmagic.github.io/bb-link/pico32/\(channel).json")

    default:
      print("Unknown board type")
      return nil
    }
  }

  func reset() {
    localVersion = ""
    newVersionAvailable = false
    newVersionURL = nil
    newVersion = nil
    progress = nil
  }

  func checkForFirmwareUpdate(url: URL, localVersion: String) {
    self.localVersion = localVersion
    self.newVersionAvailable = false
    self.newVersionURL = nil
    self.newVersion = nil
    self.newVersionSha256 = nil
    print("Checking for firmware update...")
    fetchAndCompareVersion(url: url)
  }

  func fetchAndCompareVersion(url: URL) {
    let task = URLSession.shared.dataTask(with: url) { data, response, error in
      guard let data = data, error == nil else {
        print("Error fetching JSON: \(error?.localizedDescription ?? "Unknown error")")
        return
      }

      do {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: String]
        // check if json is present
        if json != nil {
          self.newVersionURL = URL(string: json?["url"] ?? "")
          self.newVersion = json?["version"]
          self.newVersionSha256 = json?["sha256"]

          print("Remote version: \(self.newVersion ?? "nil")")
          print("Remote version URL: \(self.newVersionURL?.absoluteString ?? "nil")")
          print("Remote version SHA256: \(self.newVersionSha256 ?? "nil")")

          if !self.isSameVersion(localVersion: self.localVersion, remoteVersion: self.newVersion!) {
            print("New version available: \(self.newVersion!)")
            self.newVersionAvailable = true

            NotificationCenter.default.post(
              name: .firmwareUpdateAvailabilityChanged,
              object: nil)
          } else {
            print("No new version available")
          }
        }
      } catch {
        print("Error parsing JSON: \(error.localizedDescription)")
      }
    }
    task.resume()
  }

  private func isSameVersion(localVersion: String, remoteVersion: String) -> Bool {
    return localVersion.compare(remoteVersion, options: .numeric) == .orderedSame
  }

  func performUpdate(peripheral: CBPeripheral, characteristic: CBCharacteristic, progress: Progress)
  {
    guard newVersionAvailable, let url = newVersionURL else { return }
    self.progress = progress
    downloadAndWriteBinary(url: url, peripheral: peripheral, characteristic: characteristic)
  }

  private func downloadAndWriteBinary(
    url: URL, peripheral: CBPeripheral, characteristic: CBCharacteristic
  ) {
    let task = URLSession.shared.downloadTask(with: url) { localURL, response, error in
      guard let localURL = localURL, error == nil else {
        print("Error downloading binary: \(error?.localizedDescription ?? "Unknown error")")
        self.progress?.cancel()
        self.progress?.completedUnitCount += 1
        return
      }

      do {
        let data = try Data(contentsOf: localURL)
        self.progress?.totalUnitCount = Int64(data.count)
        self.progress?.completedUnitCount = 0
        print("Downloaded binary: \(self.progress?.totalUnitCount) bytes")

        // Verify sha256 hash of the downloaded binary
        let computedSha256 = try SHA256.hash(data: data)
          .compactMap { String(format: "%02x", $0) }
          .joined()
        print("SHA256: \(computedSha256)")

        if computedSha256 != self.newVersionSha256 {
          print("Expected SHA256: \(self.newVersionSha256 ?? "nil")")
          print("SHA256 hash mismatch")
          self.progress?.cancel()
          self.progress?.completedUnitCount += 1
          return
        }

        // Make sure phone does not sleep or lock
          DispatchQueue.main.async {
              UIApplication.shared.isIdleTimerDisabled = true
          }
        self.writeToFirmwareCharacteristic(
          peripheral: peripheral, characteristic: characteristic, data: data)
          DispatchQueue.main.async {
              UIApplication.shared.isIdleTimerDisabled = false
          }
      } catch {
        print("Error reading downloaded binary: \(error.localizedDescription)")
      }
    }
    task.resume()
  }

  private func writeToFirmwareCharacteristic(
    peripheral: CBPeripheral, characteristic: CBCharacteristic, data: Data
  ) {
    peripheral.delegate = self
    let mtu = peripheral.maximumWriteValueLength(for: .withResponse)

    // Iterate over the data in chunks of mtu bytes
    print("Flashing firmware...")
    print("MTU: \(mtu)")
    for i in stride(from: 0, to: data.count, by: mtu) {
      let chunk = data.subdata(in: i..<min(i + mtu, data.count))
      // Write the chunk to the characteristic with response type
      progress?.pause()
      progress?.completedUnitCount += Int64(chunk.count)
      peripheral.writeValue(chunk, for: characteristic, type: .withResponse)

      // Wait for the write to complete before writing the next chunk
      while let progress = progress, progress.isPaused && !progress.isCancelled 
      {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
      }
    }

    // Signal end of update by writing an empty chunk
    peripheral.writeValue(Data(), for: characteristic, type: .withResponse)
    print("Firmware update complete")
  }

  // MARK: - CBPeripheralDelegate methods

  func peripheral(
    _ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?
  ) {
    if let error = error {
      print("Error writing to characteristic: \(error.localizedDescription)")
      // Abort the update process
      progress?.cancel()
      progress?.completedUnitCount += 1
    } else {
      print("Flashed \(progress?.completedUnitCount) bytes")
      progress?.resume()
    }
  }
}
