import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let ios = root.appendingPathComponent("mobile/ios")
let project = try Data(contentsOf: ios.appendingPathComponent("DailyGo.xcodeproj/project.pbxproj"))
let document = try PropertyListSerialization.propertyList(from: project, options: [], format: nil) as! [String: Any]
let objects = document["objects"] as! [String: [String: Any]]
let projectObject = objects[document["rootObject"] as! String]!
let targetIDs = projectObject["targets"] as! [String]
let names = targetIDs.map { objects[$0]!["name"] as! String }
precondition(Set(names) == Set(["DailyGo", "DailyGoTests", "DailyGoUITests"]))

let configurationList = objects[projectObject["buildConfigurationList"] as! String]!
let configurations = (configurationList["buildConfigurations"] as! [String]).map { objects[$0]! }
let debug = configurations.first { $0["name"] as? String == "Debug" }!
precondition((debug["buildSettings"] as! [String: Any])["ONLY_ACTIVE_ARCH"] as? String == "YES",
             "Debug must use the selected simulator architecture to match Swift package builds")
let release = configurations.first { $0["name"] as? String == "Release" }!
precondition((release["buildSettings"] as! [String: Any])["ONLY_ACTIVE_ARCH"] as? String != "YES",
             "Release must retain all supported architectures")

func validateSources(_ groupID: String, directory: URL) throws {
    let group = objects[groupID]!
    let directory = (group["path"] as? String).map { directory.appendingPathComponent($0) } ?? directory
    for child in group["children"] as! [String] {
        let reference = objects[child]!
        if reference["isa"] as? String == "PBXGroup" {
            try validateSources(child, directory: directory)
        } else if reference["sourceTree"] as? String == "<group>", let file = reference["path"] as? String {
            let url = directory.appendingPathComponent(file)
            precondition(FileManager.default.fileExists(atPath: url.path), "Missing project source: \(url.path)")
            if url.pathExtension == "swift" {
                let source = try String(contentsOf: url, encoding: .utf8)
                precondition(!source.contains("uniffi") && !source.contains("DailyGoEngineFfi"))
            }
        }
    }
}
try validateSources(projectObject["mainGroup"] as! String, directory: ios)

let packages = objects.values.filter { $0["isa"] as? String == "XCLocalSwiftPackageReference" }
precondition(packages.count == 1)
precondition(packages.first!["relativePath"] as? String == "Packages/DailyGoDomain")
for path in ["Info.plist", "DailyGo.entitlements", "PrivacyInfo.xcprivacy"] {
    let data = try Data(contentsOf: ios.appendingPathComponent("Configuration/\(path)"))
    _ = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
}

final class SchemeReferences: NSObject, XMLParserDelegate {
    var identifiers: [String] = []
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        if name == "BuildableReference", let identifier = attributes["BlueprintIdentifier"] {
            identifiers.append(identifier)
        }
    }
}
let parser = XMLParser(contentsOf: ios.appendingPathComponent("DailyGo.xcodeproj/xcshareddata/xcschemes/DailyGo.xcscheme"))!
let references = SchemeReferences()
parser.delegate = references
precondition(parser.parse())
precondition(Set(references.identifiers) == Set(targetIDs))
print("Native Xcode app/test graph, source paths, local package, plists and shared scheme validated")