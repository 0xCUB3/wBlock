import SwiftUI
import Combine
import wBlockCoreService
import SafariServices

enum Platform { case iOS, macOS }

struct ContentBlockerTargetInfo: Identifiable {
    let id = UUID()
    let bundleIdentifier: String
    let jsonFileName: String
    let categories: [FilterListCategory]
    let platform: Platform
    let ruleLimit: Int
}

@MainActor
class AppFilterManager: ObservableObject {
    @Published var filterLists: [FilterList] = []
    @Published var isLoading: Bool = false
    @Published var statusDescription: String = "Ready."
    @Published var lastConversionTime: String = "N/A"
    @Published var lastReloadTime: String = "N/A"
    @Published var lastRuleCount: Int = 0
    @Published var hasError: Bool = false
    @Published var progress: Float = 0
    @Published var missingFilters: [FilterList] = []
    @Published var availableUpdates: [FilterList] = []
    @Published var showingUpdatePopup = false
    @Published var showingNoUpdatesAlert = false
    @Published var hasUnappliedChanges = false
    @Published var showMissingFiltersSheet = false
    @Published var showingApplyProgressSheet = false
    @Published var showingDownloadCompleteAlert = false
    @Published var downloadCompleteMessage = ""
    
    @Published var sourceRulesCount: Int = 0
    @Published var conversionStageDescription: String = ""
    @Published var currentFilterName: String = ""
    @Published var processedFiltersCount: Int = 0
    @Published var totalFiltersCount: Int = 0
    @Published var isInConversionPhase: Bool = false
    @Published var isInSavingPhase: Bool = false
    @Published var isInEnginePhase: Bool = false
    @Published var isInReloadPhase: Bool = false
    @Published var overallProgressDescription: String = "Ready."
    
    // @Published properties for per-target limit tracking
    /// Stores the last successfully applied Safari rule count for each target (key: targetInfo.jsonFileName)
    @Published var lastAppliedRuleCountsPerTarget: [String: Int] = [:]
    /// Stores jsonFileNames of targets that exceeded their rule limit in the last `applyChanges`
    @Published var targetsThatExceededLimit: Set<String> = []
    /// For showing a summary alert if any target exceeded its limit during applyChanges
    @Published var showingPostApplyLimitIssuesAlert: Bool = false
    @Published var postApplyLimitIssuesMessage: String = ""

    private let loader: FilterListLoader
    private let updater: FilterListUpdater
    private let logManager: ConcurrentLogManager
    
    var customFilterLists: [FilterList] = []

    public let allContentBlockerTargets: [ContentBlockerTargetInfo] = [
        ContentBlockerTargetInfo(bundleIdentifier: "skula.wBlock.wBlock-Ads-Privacy", jsonFileName: "wBlock_Ads_&_Privacy_rules.json", categories: [.ads, .privacy], platform: .macOS, ruleLimit: 150000),
        ContentBlockerTargetInfo(bundleIdentifier: "skula.wBlock.wBlock-Security-Multipurpose", jsonFileName: "wBlock_Security_&_Multipurpose_rules.json", categories: [.security, .multipurpose], platform: .macOS, ruleLimit: 150000),
        ContentBlockerTargetInfo(bundleIdentifier: "skula.wBlock.wBlock-Annoyances", jsonFileName: "wBlock_Annoyances_rules.json", categories: [.annoyances], platform: .macOS, ruleLimit: 150000),
        ContentBlockerTargetInfo(bundleIdentifier: "skula.wBlock.wBlock-Foreign-Experimental", jsonFileName: "wBlock_Foreign_&_Experimental_rules.json", categories: [.foreign, .experimental], platform: .macOS, ruleLimit: 150000),
        ContentBlockerTargetInfo(bundleIdentifier: "skula.wBlock.wBlock-Custom", jsonFileName: "wBlock_Custom_rules.json", categories: [.custom], platform: .macOS, ruleLimit: 150000),

        ContentBlockerTargetInfo(bundleIdentifier: "skula.wBlock.wBlock-Ads-iOS", jsonFileName: "wBlock_Ads_iOS_rules.json", categories: [.ads], platform: .iOS, ruleLimit: 50000),
        ContentBlockerTargetInfo(bundleIdentifier: "skula.wBlock.wBlock-Privacy-iOS", jsonFileName: "wBlock_Privacy_iOS_rules.json", categories: [.privacy], platform: .iOS, ruleLimit: 50000),
        ContentBlockerTargetInfo(bundleIdentifier: "skula.wBlock.wBlock-Security-iOS", jsonFileName: "wBlock_Security_iOS_rules.json", categories: [.security], platform: .iOS, ruleLimit: 50000),
        ContentBlockerTargetInfo(bundleIdentifier: "skula.wBlock.wBlock-Annoyances-iOS", jsonFileName: "wBlock_Annoyances_iOS_rules.json", categories: [.annoyances], platform: .iOS, ruleLimit: 50000),
        ContentBlockerTargetInfo(bundleIdentifier: "skula.wBlock.wBlock-Multipurpose-iOS", jsonFileName: "wBlock_Multipurpose_iOS_rules.json", categories: [.multipurpose], platform: .iOS, ruleLimit: 50000),
        ContentBlockerTargetInfo(bundleIdentifier: "skula.wBlock.wBlock-Foreign-iOS", jsonFileName: "wBlock_Foreign_iOS_rules.json", categories: [.foreign], platform: .iOS, ruleLimit: 50000),
        ContentBlockerTargetInfo(bundleIdentifier: "skula.wBlock.wBlock-Experimental-iOS", jsonFileName: "wBlock_Experimental_iOS_rules.json", categories: [.experimental], platform: .iOS, ruleLimit: 50000),
        ContentBlockerTargetInfo(bundleIdentifier: "skula.wBlock.wBlock-Custom-iOS", jsonFileName: "wBlock_Custom_iOS_rules.json", categories: [.custom], platform: .iOS, ruleLimit: 50000),
    ]

    init() {
        self.logManager = ConcurrentLogManager.shared
        self.loader = FilterListLoader(logManager: self.logManager)
        self.updater = FilterListUpdater(loader: self.loader, logManager: self.logManager)
        setup()
    }

    private func setup() {
        updater.filterListManager = self
        loader.checkAndCreateGroupFolder()
        filterLists = loader.loadFilterLists()
        customFilterLists = loader.loadCustomFilterLists()
        
        let customListIDsInMain = Set(filterLists.filter { $0.category == .custom }.map { $0.id })
        for customList in customFilterLists {
            if !customListIDsInMain.contains(customList.id) {
                filterLists.append(customList)
            }
        }

        loader.loadSelectedState(for: &filterLists)
        // Load previously applied rule counts if persisted
        if let savedCountsData = UserDefaults.standard.data(forKey: "lastAppliedRuleCountsPerTarget"),
           let savedCounts = try? JSONDecoder().decode([String: Int].self, from: savedCountsData) {
            self.lastAppliedRuleCountsPerTarget = savedCounts
        }
        if let savedExceededData = UserDefaults.standard.data(forKey: "targetsThatExceededLimit"),
            let savedExceeded = try? JSONDecoder().decode(Set<String>.self, from: savedExceededData) {
            self.targetsThatExceededLimit = savedExceeded
        }

        statusDescription = "Initialized."
        Task { await updateVersionsAndCounts() }
    }
    
    private func persistTargetRuleStates() {
        if let data = try? JSONEncoder().encode(lastAppliedRuleCountsPerTarget) {
            UserDefaults.standard.set(data, forKey: "lastAppliedRuleCountsPerTarget")
        }
        if let data = try? JSONEncoder().encode(targetsThatExceededLimit) {
            UserDefaults.standard.set(data, forKey: "targetsThatExceededLimit")
        }
    }
    
    func saveFilterLists() {
        loader.saveFilterLists(filterLists)
    }

    func updateVersionsAndCounts() async {
        let initiallyLoadedLists = self.filterLists
        let updatedListsFromServer = await updater.updateMissingVersionsAndCounts(filterLists: initiallyLoadedLists)
        
        var newFilterLists = self.filterLists
        for updatedListFromServer in updatedListsFromServer {
            if let index = newFilterLists.firstIndex(where: { $0.id == updatedListFromServer.id }) {
                let currentSelectionState = newFilterLists[index].isSelected
                newFilterLists[index] = updatedListFromServer
                newFilterLists[index].isSelected = currentSelectionState
            } else {
                 await logManager.log("Warning: updatedListFromServer not found in current filterLists during version/count update: \(updatedListFromServer.name)")
            }
        }
        self.filterLists = newFilterLists
        saveFilterLists()
    }

    func applyChanges() async {
        isLoading = true
        hasError = false
        progress = 0
        overallProgressDescription = "Starting to apply filter changes..."
        statusDescription = "Preparing to apply selected filters..."
        showingApplyProgressSheet = true
        targetsThatExceededLimit.removeAll() // Clear previous limit errors for this run
        var localTargetsExceededThisRun: Set<String> = []


        sourceRulesCount = 0
        conversionStageDescription = ""
        currentFilterName = ""
        processedFiltersCount = 0
        isInConversionPhase = false
        isInSavingPhase = false
        isInEnginePhase = false
        isInReloadPhase = false

        let currentPlatform: Platform = {
            #if os(macOS)
            return .macOS
            #else
            return .iOS
            #endif
        }()

        let platformSpecificTargets = allContentBlockerTargets.filter { $0.platform == currentPlatform }
        totalFiltersCount = platformSpecificTargets.count

        if platformSpecificTargets.isEmpty {
            statusDescription = "No content blocker targets defined for this platform."
            await logManager.log("ApplyChanges: No targets for platform \(currentPlatform).")
            isLoading = false
            return
        }
        
        var reloadedIdentifiers = Set<String>()
        var totalSafariRulesAppliedThisSession = 0
        // var ruleLimitErrors: [String] = [] // Replaced by targetsThatExceededLimit

        for (index, targetInfo) in platformSpecificTargets.enumerated() {
            processedFiltersCount = index + 1
            currentFilterName = targetInfo.bundleIdentifier
            let baseProgress = Float(index) / Float(platformSpecificTargets.count)
            progress = baseProgress

            await logManager.log("Processing target: \(targetInfo.jsonFileName) for categories: \(targetInfo.categories.map { $0.rawValue })")

            var rulesForThisTargetString = ""
            var sourceRulesForThisTargetCount = 0

            let selectedStandardFilters = filterLists.filter { list in
                list.isSelected && targetInfo.categories.contains(list.category)
            }
            
            var selectedCustomFiltersForTarget: [FilterList] = []
            if targetInfo.categories.contains(.custom) {
                selectedCustomFiltersForTarget = customFilterLists.filter { $0.isSelected }
            }
            
            let allSelectedFiltersForTarget = (selectedStandardFilters + selectedCustomFiltersForTarget).reduce(into: [FilterList]()) { result, filter in
                if !result.contains(where: { $0.id == filter.id }) {
                    result.append(filter)
                }
            }

            conversionStageDescription = "Reading rules for \(targetInfo.jsonFileName)..."
            progress = baseProgress + (0.2 / Float(platformSpecificTargets.count))
            await Task.yield()

            for filter in allSelectedFiltersForTarget {
                guard let containerURL = loader.getSharedContainerURL() else {
                    await logManager.log("Error: Unable to access shared container for \(filter.name)")
                    continue
                }
                let fileURL = containerURL.appendingPathComponent("\(filter.name).txt")
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    do {
                        let content = try String(contentsOf: fileURL, encoding: .utf8)
                        rulesForThisTargetString += content + "\n"
                        let rulesInThisFile = filter.sourceRuleCount ?? content.components(separatedBy: .newlines).filter { !$0.isEmpty && !$0.hasPrefix("!") && !$0.hasPrefix("[") && !$0.hasPrefix("#")}.count
                        sourceRulesForThisTargetCount += rulesInThisFile
                    } catch {
                        await logManager.log("Error reading \(filter.name): \(error.localizedDescription)")
                    }
                } else {
                    await logManager.log("Warning: Filter file not found for selected filter: \(filter.name) at \(fileURL.path)")
                }
            }
            sourceRulesCount += sourceRulesForThisTargetCount

            if rulesForThisTargetString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                await logManager.log("No rules to apply for \(targetInfo.jsonFileName). Saving empty list.")
                _ = ContentBlockerService.saveContentBlocker(
                    jsonRules: "[]",
                    groupIdentifier: GroupIdentifier.shared.value,
                    fileName: targetInfo.jsonFileName
                )
                lastAppliedRuleCountsPerTarget[targetInfo.jsonFileName] = 0 // Record 0 rules
                reloadedIdentifiers.insert(targetInfo.bundleIdentifier)
                continue
            }

            isInConversionPhase = true
            conversionStageDescription = "Converting \(sourceRulesForThisTargetCount) rules for \(targetInfo.jsonFileName)..."
            progress = baseProgress + (0.5 / Float(platformSpecificTargets.count))
            await Task.yield()
            
            let conversionResultTuple = ContentBlockerService.convertRules(rules: rulesForThisTargetString)
            isInConversionPhase = false

            if conversionResultTuple.safariRulesCount > targetInfo.ruleLimit {
                await logManager.log("ERROR: \(targetInfo.jsonFileName) exceeded rule limit of \(targetInfo.ruleLimit). Has \(conversionResultTuple.safariRulesCount) rules. Saving empty list.")
                _ = ContentBlockerService.saveContentBlocker(
                    jsonRules: "[]",
                    groupIdentifier: GroupIdentifier.shared.value,
                    fileName: targetInfo.jsonFileName
                )
                localTargetsExceededThisRun.insert(targetInfo.jsonFileName) // Track exceeded target
                lastAppliedRuleCountsPerTarget[targetInfo.jsonFileName] = 0 // Record 0 for exceeded
                hasError = true // General error state
                reloadedIdentifiers.insert(targetInfo.bundleIdentifier)
                continue
            }
            
            isInSavingPhase = true
            conversionStageDescription = "Saving rules for \(targetInfo.jsonFileName)..."
            progress = baseProgress + (0.8 / Float(platformSpecificTargets.count))
            await Task.yield()

            let savedRuleCount = ContentBlockerService.saveContentBlocker(
                jsonRules: conversionResultTuple.safariRulesJSON,
                groupIdentifier: GroupIdentifier.shared.value,
                fileName: targetInfo.jsonFileName
            )
            lastAppliedRuleCountsPerTarget[targetInfo.jsonFileName] = savedRuleCount // Record successful count
            totalSafariRulesAppliedThisSession += savedRuleCount
            reloadedIdentifiers.insert(targetInfo.bundleIdentifier)
            isInSavingPhase = false
            await logManager.log("Successfully converted and saved \(savedRuleCount) rules for \(targetInfo.jsonFileName).")
        }
        
        self.targetsThatExceededLimit = localTargetsExceededThisRun // Update the published property
        
        progress = 0.9
        isInReloadPhase = true
        conversionStageDescription = "Reloading Safari content blockers..."
        await Task.yield()

        var allReloadsSuccessful = true
        var successfullyReloadedIdentifiers: [String] = []
        var failedToReloadIdentifiers: [String] = []

        for (idx, identifier) in reloadedIdentifiers.enumerated() {
            let reloadProgressStep = 0.1 / Float(max(1, reloadedIdentifiers.count)) // Avoid division by zero
            progress = 0.9 + (Float(idx) * reloadProgressStep)
            conversionStageDescription = "Reloading \(identifier)..."
            await Task.yield()

            let reloadResult = ContentBlockerService.reloadContentBlocker(withIdentifier: identifier)
            switch reloadResult {
            case .success:
                successfullyReloadedIdentifiers.append(identifier)
                await logManager.log("Successfully reloaded \(identifier).")
            case .failure(let error):
                allReloadsSuccessful = false
                failedToReloadIdentifiers.append(identifier)
                await logManager.log("Failed to reload \(identifier): \(error.localizedDescription)")
            }
        }
        
        progress = 1.0
        isInReloadPhase = false
        conversionStageDescription = "Process complete."
        lastRuleCount = totalSafariRulesAppliedThisSession

        if !targetsThatExceededLimit.isEmpty {
            postApplyLimitIssuesMessage = "One or more filter categories exceeded Safari's rule limit and an empty list was applied for them: \(targetsThatExceededLimit.joined(separator: ", ")). Please review their selections."
            showingPostApplyLimitIssuesAlert = true
            statusDescription = "Some categories exceeded rule limits."
            await logManager.log("ApplyChanges: Finished with rule limit errors for: \(targetsThatExceededLimit.joined(separator: ", "))")
        } else if allReloadsSuccessful {
            statusDescription = "Successfully applied changes to \(successfullyReloadedIdentifiers.count) Safari extension(s)."
            hasUnappliedChanges = false
            await logManager.log("ApplyChanges: SUCCESS - All \(successfullyReloadedIdentifiers.count) extensions reloaded.")
        } else {
            statusDescription = "Some extensions failed to reload: \(failedToReloadIdentifiers.joined(separator: ", "))."
            await logManager.log("ApplyChanges: PARTIAL FAILURE - Failed to reload: \(failedToReloadIdentifiers.joined(separator: ", "))")
        }
        
        isLoading = false
        persistTargetRuleStates()
        saveFilterLists()
    }
    
    func resetFiltersForCategory(_ categoryToReset: FilterListCategory) async {
        await logManager.log("Resetting filters for category: \(categoryToReset.rawValue)")
        var modified = false
        for index in filterLists.indices {
            if filterLists[index].category == categoryToReset && filterLists[index].isSelected {
                filterLists[index].isSelected = false
                modified = true
            }
        }
        // Also handle custom lists if they are managed separately and can belong to the category
        // or if the category is .custom itself
        if categoryToReset == .custom {
            for index in customFilterLists.indices {
                if customFilterLists[index].isSelected {
                    customFilterLists[index].isSelected = false
                    // Ensure the main filterLists (if it mirrors custom) is also updated
                    if let mainIndex = filterLists.firstIndex(where: { $0.id == customFilterLists[index].id}) {
                        filterLists[mainIndex].isSelected = false
                    }
                    modified = true
                }
            }
        }

        if modified {
            loader.saveSelectedState(for: filterLists)
            if categoryToReset == .custom && !customFilterLists.isEmpty {
                 loader.saveSelectedState(for: customFilterLists) // If selection stored separately
            }
            hasUnappliedChanges = true
            statusDescription = "Filters for \(categoryToReset.rawValue) reset. Please apply changes."
            await logManager.log("Category \(categoryToReset.rawValue) filters deselected. Pending applyChanges.")
            
            // Remove the category's targets from the "exceeded limit" list locally,
            // as the user is taking action to fix it.
            // The true fix happens on the next applyChanges.
            let currentPlatform: Platform = {
                #if os(macOS)
                    return .macOS
                #else
                    return .iOS
                #endif
            }()
            let targetsForCategory = allContentBlockerTargets.filter { $0.platform == currentPlatform && $0.categories.contains(categoryToReset) }
            for target in targetsForCategory {
                targetsThatExceededLimit.remove(target.jsonFileName)
                lastAppliedRuleCountsPerTarget[target.jsonFileName] = 0 // Assume 0 until next apply
            }
            persistTargetRuleStates()

        } else {
            await logManager.log("No selected filters found to reset for category: \(categoryToReset.rawValue)")
        }
        // The UI should prompt the user to "Apply Changes" after this.
    }

    func checkAndEnableFilters() {
        missingFilters.removeAll()
        for filter in filterLists where filter.isSelected {
            if !loader.filterFileExists(filter) {
                missingFilters.append(filter)
            }
        }
        if !missingFilters.isEmpty {
            showMissingFiltersSheet = true
        } else {
            showingApplyProgressSheet = true
            Task {
                await applyChanges()
            }
        }
    }

    func toggleFilterListSelection(id: UUID) {
        if let index = filterLists.firstIndex(where: { $0.id == id }) {
            filterLists[index].isSelected.toggle()
            loader.saveSelectedState(for: filterLists)
            hasUnappliedChanges = true
        }
        if let index = customFilterLists.firstIndex(where: { $0.id == id}) {
             customFilterLists[index].isSelected.toggle()
             loader.saveSelectedState(for: customFilterLists)
             hasUnappliedChanges = true
        }
    }

    func filterLists(for category: FilterListCategory) -> [FilterList] {
        category == .all ? filterLists : filterLists.filter { $0.category == category }
    }
    
    func doesFilterFileExist(_ filter: FilterList) -> Bool {
        return loader.filterFileExists(filter)
    }

    func updateMissingFilters() async {
        isLoading = true
        progress = 0
        overallProgressDescription = "Downloading missing filters..."

        let totalSteps = Float(missingFilters.count)
        var completedSteps: Float = 0
        var tempMissingFilters = self.missingFilters

        for filter in tempMissingFilters {
            let success = await updater.fetchAndProcessFilter(filter)
            if success {
                await MainActor.run {
                    self.missingFilters.removeAll { $0.id == filter.id }
                }
            }
            completedSteps += 1
            await MainActor.run {
                self.progress = completedSteps / totalSteps
            }
        }
        
        saveFilterLists()

        await MainActor.run {
            showingApplyProgressSheet = true
        }
        
        await applyChanges()
        isLoading = false
        progress = 0
        overallProgressDescription = "Finished downloading missing filters and applied changes."
    }

    func checkForUpdates() async {
        isLoading = true
        statusDescription = "Checking for updates..."
        overallProgressDescription = "Checking for filter updates..."
        await updateVersionsAndCounts()
        
        let enabledFilters = filterLists.filter { $0.isSelected } + customFilterLists.filter { $0.isSelected }
        let uniqueEnabledFilters = enabledFilters.reduce(into: [FilterList]()) { result, filter in
            if !result.contains(where: { $0.id == filter.id }) {
                result.append(filter)
            }
        }
        
        let updatedFilters = await updater.checkForUpdates(filterLists: uniqueEnabledFilters)

        availableUpdates = updatedFilters

        if !availableUpdates.isEmpty {
            showingUpdatePopup = true
            statusDescription = "Found \(availableUpdates.count) update(s) available."
        } else {
            showingNoUpdatesAlert = true
            statusDescription = "No updates available."
            await ConcurrentLogManager.shared.log("No updates available.")
        }
        
        isLoading = false
        overallProgressDescription = "Update check complete."
    }

    func autoUpdateFilters() async -> [FilterList] {
        isLoading = true
        progress = 0
        overallProgressDescription = "Automatically updating filters..."
        
        await updateVersionsAndCounts()

        let allSelectedFilters = (filterLists.filter { $0.isSelected } + customFilterLists.filter { $0.isSelected }).reduce(into: [FilterList]()) { result, filter in
            if !result.contains(where: { $0.id == filter.id }) {
                result.append(filter)
            }
        }

        let updatedFilters = await updater.autoUpdateFilters(
            filterLists: allSelectedFilters,
            progressCallback: { newProgress in
                Task { @MainActor in
                    self.progress = newProgress
                }
            }
        )
        
        saveFilterLists()

        if !updatedFilters.isEmpty {
            await applyChanges()
        }

        isLoading = false
        progress = 0
        overallProgressDescription = "Auto-update process finished."
        return updatedFilters
    }

    func updateSelectedFilters(_ selectedFilters: [FilterList]) async {
        isLoading = true
        progress = 0
        overallProgressDescription = "Downloading selected filter updates..."

        let updatedSuccessfullyFilters = await updater.updateSelectedFilters(
            selectedFilters,
            progressCallback: { newProgress in
                Task { @MainActor in
                    self.progress = newProgress
                }
            }
        )
        
        await MainActor.run {
            for filter in updatedSuccessfullyFilters {
                 self.availableUpdates.removeAll { $0.id == filter.id }
            }
        }
        
        saveFilterLists()

        await applyChanges()
        isLoading = false
        progress = 0
        overallProgressDescription = "Finished updating selected filters."
    }

    func downloadSelectedFilters(_ selectedFiltersToDownload: [FilterList]) async {
        isLoading = true
        progress = 0
        overallProgressDescription = "Downloading filter updates..."

        let successfullyUpdatedFilters = await updater.updateSelectedFilters(
            selectedFiltersToDownload,
            progressCallback: { newProgress in
                Task { @MainActor in
                    self.progress = newProgress
                }
            }
        )
        
        saveFilterLists()
        
        await MainActor.run {
            for filter in successfullyUpdatedFilters {
                self.availableUpdates.removeAll { $0.id == filter.id }
            }
        }

        isLoading = false
        progress = 0
        
        await MainActor.run {
            showingUpdatePopup = false
            downloadCompleteMessage = "Downloaded \(successfullyUpdatedFilters.count) filter update(s). Would you like to apply them now?"
            showingDownloadCompleteAlert = true
            overallProgressDescription = "Download complete. Ready to apply."
        }
    }
    
    func downloadMissingFilters() async {
        isLoading = true
        progress = 0
        overallProgressDescription = "Downloading missing filters..."

        let totalSteps = Float(missingFilters.count)
        var completedSteps: Float = 0
        var downloadedCount = 0
        
        var tempMissingFilters = self.missingFilters

        for filter in tempMissingFilters {
            let success = await updater.fetchAndProcessFilter(filter)
            if success {
                await MainActor.run {
                    self.missingFilters.removeAll { $0.id == filter.id }
                }
                downloadedCount += 1
            }
            completedSteps += 1
            await MainActor.run {
                self.progress = completedSteps / totalSteps
            }
        }
        
        saveFilterLists()

        isLoading = false
        progress = 0
        
        await MainActor.run {
            showMissingFiltersSheet = false
            downloadCompleteMessage = "Downloaded \(downloadedCount) missing filter(s). Would you like to apply them now?"
            showingDownloadCompleteAlert = true
            overallProgressDescription = "Missing filters downloaded. Ready to apply."
        }
    }
    
    func applyDownloadedChanges() async {
        overallProgressDescription = "Applying downloaded changes..."
        await MainActor.run {
            showingApplyProgressSheet = true
        }
        await applyChanges()
        overallProgressDescription = "Changes applied."
    }

    func addFilterList(name: String, urlString: String) {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            statusDescription = "Invalid URL provided: \(urlString)"
            hasError = true
            Task { await ConcurrentLogManager.shared.log("Error: Invalid URL provided for new filter list - \(urlString)") }
            return
        }
        
        if filterLists.contains(where: { $0.url == url }) || customFilterLists.contains(where: { $0.url == url }) {
            statusDescription = "Filter list with this URL already exists: \(url.absoluteString)"
            hasError = true
            Task { await ConcurrentLogManager.shared.log("Error: Filter list with URL \(url.absoluteString) already exists.") }
            return
        }
        
        let newName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var newFilter = FilterList(id: UUID(),
                                   name: newName.isEmpty ? (url.host ?? "Custom Filter") : newName,
                                   url: url,
                                   category: .custom,
                                   isSelected: true,
                                   description: "User-added filter list.",
                                   sourceRuleCount: nil)
        
        customFilterLists.append(newFilter)
        loader.saveCustomFilterLists(customFilterLists)

        if !filterLists.contains(where: { $0.id == newFilter.id}) {
             filterLists.append(newFilter)
        }
            
        Task {
            await ConcurrentLogManager.shared.log("Added custom filter: \(newFilter.name)")
        }

        Task {
            let success = await updater.fetchAndProcessFilter(newFilter)
            if success {
                if let index = self.filterLists.firstIndex(where: { $0.id == newFilter.id }) {
                    self.filterLists[index].sourceRuleCount = newFilter.sourceRuleCount
                    self.filterLists[index].version = newFilter.version
                }
                if let custIndex = self.customFilterLists.firstIndex(where: { $0.id == newFilter.id }) {
                    self.customFilterLists[custIndex].sourceRuleCount = newFilter.sourceRuleCount
                    self.customFilterLists[custIndex].version = newFilter.version
                }
                await ConcurrentLogManager.shared.log("Successfully downloaded custom filter: \(newFilter.name)")
                hasUnappliedChanges = true
                saveFilterLists()
            } else {
                await ConcurrentLogManager.shared.log("Failed to download custom filter: \(newFilter.name)")
                await MainActor.run {
                    removeCustomFilterList(newFilter)
                }
            }
        }
    }
    
    func removeFilterList(at offsets: IndexSet, fromCategory category: FilterListCategory? = nil) {
        var namesToRemove: [String] = []
        var idsToRemove: [UUID] = []

        offsets.forEach { index in
            if let cat = category, cat != .all, cat != .custom {
                let categoryLists = filterLists.filter { $0.category == cat }
                if index < categoryLists.count {
                    let filterToRemove = categoryLists[index]
                    idsToRemove.append(filterToRemove.id)
                    namesToRemove.append(filterToRemove.name)
                }
            } else if category == .custom {
                let customCategoryLists = filterLists.filter { $0.category == .custom }
                 if index < customCategoryLists.count {
                    let filterToRemove = customCategoryLists[index]
                    idsToRemove.append(filterToRemove.id)
                    namesToRemove.append(filterToRemove.name)
                }
            }
            else { // Removing from 'all' or undifferentiated list
                if index < filterLists.count {
                    let filterToRemove = filterLists[index]
                    idsToRemove.append(filterToRemove.id)
                    namesToRemove.append(filterToRemove.name)
                }
            }
        }

        for id in idsToRemove {
            if let filterToRemove = filterLists.first(where: { $0.id == id }) {
                 removeFilterList(filterToRemove)
            }
        }
        statusDescription = "Removed filter(s): \(namesToRemove.joined(separator: ", "))"
        Task { await ConcurrentLogManager.shared.log("Removed filter(s): \(namesToRemove.joined(separator: ", "))") }
    }

    func removeFilterList(_ listToRemove: FilterList) {
        if listToRemove.category == .custom {
            customFilterLists.removeAll { $0.id == listToRemove.id }
            loader.saveCustomFilterLists(customFilterLists)
        }
        
        filterLists.removeAll { $0.id == listToRemove.id }
        loader.saveFilterLists(filterLists)

        if let containerURL = loader.getSharedContainerURL() {
            let fileURL = containerURL.appendingPathComponent("\(listToRemove.name).txt")
            try? FileManager.default.removeItem(at: fileURL)
            Task { await ConcurrentLogManager.shared.log("Attempted to remove local file: \(fileURL.path)")}
        }
        hasUnappliedChanges = true
        Task { await ConcurrentLogManager.shared.log("Removed filter list: \(listToRemove.name)")}
    }

    func toggleFilter(list: FilterList) {
        toggleFilterListSelection(id: list.id)
    }

    func addCustomFilterList(_ filter: FilterList) {
        if !customFilterLists.contains(where: { $0.url == filter.url }) {
            var newFilterToAdd = filter
            newFilterToAdd.isSelected = true

            customFilterLists.append(newFilterToAdd)
            loader.saveCustomFilterLists(customFilterLists)

            if !filterLists.contains(where: { $0.id == newFilterToAdd.id }) {
                filterLists.append(newFilterToAdd)
            } else {
                if let index = filterLists.firstIndex(where: { $0.id == newFilterToAdd.id }) {
                    filterLists[index].isSelected = true
                }
            }
            
            Task {
                await ConcurrentLogManager.shared.log("Added custom filter: \(newFilterToAdd.name)")
                let success = await updater.fetchAndProcessFilter(newFilterToAdd)
                if success {
                    if let index = self.filterLists.firstIndex(where: { $0.id == newFilterToAdd.id }) {
                       self.filterLists[index] = newFilterToAdd // Ensure the main list has the updated version/count
                    }
                    if let custIndex = self.customFilterLists.firstIndex(where: { $0.id == newFilterToAdd.id }) {
                       self.customFilterLists[custIndex] = newFilterToAdd
                    }
                    await ConcurrentLogManager.shared.log("Successfully downloaded custom filter: \(newFilterToAdd.name)")
                    hasUnappliedChanges = true
                    saveFilterLists()
                } else {
                    await ConcurrentLogManager.shared.log("Failed to download custom filter: \(newFilterToAdd.name)")
                    await MainActor.run {
                        removeCustomFilterList(newFilterToAdd)
                    }
                }
            }
        } else {
            Task {
                await ConcurrentLogManager.shared.log("Custom filter with URL \(filter.url) already exists")
            }
        }
    }

    func removeCustomFilterList(_ filter: FilterList) {
        customFilterLists.removeAll { $0.id == filter.id }
        loader.saveCustomFilterLists(customFilterLists)

        filterLists.removeAll { $0.id == filter.id }
        
        if let containerURL = loader.getSharedContainerURL() {
            let fileURL = containerURL.appendingPathComponent("\(filter.name).txt")
            do {
                try FileManager.default.removeItem(at: fileURL)
                Task { await ConcurrentLogManager.shared.log("Successfully removed local file: \(fileURL.path)")}
            } catch {
                Task { await ConcurrentLogManager.shared.log("Error removing local file \(fileURL.path): \(error.localizedDescription)")}
            }
        }
        saveFilterLists()
        Task {
            await ConcurrentLogManager.shared.log("Removed custom filter: \(filter.name)")
        }
        hasUnappliedChanges = true
    }
}
