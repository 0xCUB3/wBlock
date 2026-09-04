"""Exercise the production refresh method and merge helpers on an isolated disk double."""
import os
from pathlib import Path
import subprocess
import tempfile

source = Path('wBlockCoreService/ProtobufDataManager.swift').read_text()
helpers = source[source.index('private func mergeField'):source.index('// MARK: - Disk I/O')]
start = source.index('    public func refreshFromDiskIfModified(')
end = source.index('    // File URLs', start)
method = source[start:end]
cloud = Path('wBlock/CloudSyncManager.swift').read_text().split('private func buildPayloadContent()', 1)[1]
assert cloud.index('saveDataImmediately()') < cloud.index('refreshFromDiskIfModified()') < cloud.index('let settings')
assert 'whitelistDomains: content.whitelistDomains' in Path('wBlock/CloudSyncManager.swift').read_text()
products = Path(os.environ['WBLOCK_CORE_PRODUCTS'])
harness = r'''
import Foundation
internal import SwiftProtobuf

struct Loaded {
    var appData: Wblock_Data_AppData
    var rawData: Data
    var modificationDate: Date? = Date(timeIntervalSince1970: 1)
}
actor Disk {
    var data = Wblock_Data_AppData()
    var version = 1
    func put(_ next: Wblock_Data_AppData) { data = next; version += 1 }
    func modificationDate(for url: URL) -> Date? { Date(timeIntervalSince1970: 1) }
    func dataVersion(for url: URL) -> Int { version }
    func readAppData(from url: URL) throws -> Loaded { Loaded(appData: data, rawData: try data.serializedData()) }
}
struct Log { func error(_ text: String) {} }
@MainActor final class Signal {
    var count = 0
    func send() { count += 1 }
}
@MainActor final class Harness {
    let diskStore = Disk()
    let dataFileURL = URL(fileURLWithPath: "/unused")
    let dataVersionFileURL = URL(fileURLWithPath: "/unused")
    var appData = Wblock_Data_AppData()
    var lastSavedData: Data? = try! Wblock_Data_AppData().serializedData()
    var lastLoadedDataFileModificationDate: Date? = Date(timeIntervalSince1970: 1)
    var lastLoadedDataVersion = 1
    var lastError: Error?
    let logger = Log()
    let didSaveDataSubject = Signal()
    METHOD
}
@main struct Main {
    @MainActor static func main() async throws {
        let manager = Harness()
        // Local unsaved change must survive the popup's unrelated disk write.
        manager.appData.whitelist.filterDisabledSites = ["local.example"]
        var popup = Wblock_Data_AppData()
        popup.whitelist.disabledSites = ["disabled.example"]
        await manager.diskStore.put(popup)
        let changed = await manager.refreshFromDiskIfModified()
        precondition(changed)
        precondition(manager.appData.whitelist.disabledSites == ["disabled.example"])
        precondition(manager.appData.whitelist.filterDisabledSites == ["local.example"])
        precondition(manager.didSaveDataSubject.count == 1, "extension save must schedule cloud upload")
        let unchanged = await manager.refreshFromDiskIfModified()
        precondition(!unchanged && manager.didSaveDataSubject.count == 1, "no notification loop")
        popup.whitelist.disabledSites = []
        await manager.diskStore.put(popup)
        let removed = await manager.refreshFromDiskIfModified()
        precondition(removed && manager.appData.whitelist.disabledSites.isEmpty)
        precondition(manager.appData.whitelist.filterDisabledSites == ["local.example"])
        precondition(manager.didSaveDataSubject.count == 2, "re-enabling must sync too")
        print("PASS #684 external additions/removals notify sync and preserve pending local edits")
    }
}
'''.replace('    METHOD', method)
with tempfile.TemporaryDirectory() as temp:
    test = Path(temp) / 'refresh.swift'
    test.write_text(harness + '\n' + helpers)
    binary = str(Path(temp) / 'test')
    subprocess.run(['swiftc', '-parse-as-library', '-I', str(products), str(products / 'SwiftProtobuf.o'),
                    'wBlockCoreService/DataModels.pb.swift', 'wBlockCoreService/UserScriptPersistence.swift', str(test), '-o', binary], check=True)
    subprocess.run([binary], check=True)
