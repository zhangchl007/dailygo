import Foundation

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("Usage: select-ios-simulator.swift <simulator-sdk-version>\n".utf8))
    exit(1)
}
let version = CommandLine.arguments[1]
let runtime = "com.apple.CoreSimulator.SimRuntime.iOS-" + version.replacingOccurrences(of: ".", with: "-")
let data = FileHandle.standardInput.readDataToEndOfFile()
let document = try JSONSerialization.jsonObject(with: data) as! [String: Any]
let devices = document["devices"] as! [String: [[String: Any]]]
let phones = (devices[runtime] ?? []).filter {
    ($0["isAvailable"] as? Bool == true) && ($0["name"] as? String)?.hasPrefix("iPhone") == true
}
guard let identifier = phones.first?["udid"] as? String else {
    FileHandle.standardError.write(Data("No available iPhone simulator for SDK \(version). Install its runtime or set IOS_SIMULATOR_UDID explicitly.\n".utf8))
    exit(1)
}
print(identifier)