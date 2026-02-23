import Foundation
import wBlockCoreService

public class ContentBlockerRequestHandler: NSObject, NSExtensionRequestHandling {
    public func beginRequest(with context: NSExtensionContext) {
        ContentBlockerExtensionRequestHandler.handleRequest(with: context)
    }
}
