import Foundation
import wBlockCoreService

@main struct FilterClassifierTest {
    static func main() {
        func check(_ ok: Bool, _ message: String) { if !ok { fputs("FAIL: \(message)\n", stderr); exit(1) } }
        check(FilterUpdateResponseClassifier.classify(statusCode: 304, responseData: nil, localData: nil) == .notModified, "304")
        check(FilterUpdateResponseClassifier.looksLikeFilterListData(Data("||example.com^".utf8)), "filter data")
        check(!FilterUpdateResponseClassifier.looksLikeFilterListData(Data("<html>challenge".utf8)), "HTML")
        check(!FilterUpdateResponseClassifier.looksLikeFilterListData(Data("404: Not Found".utf8)), "404 body")
        check(FilterUpdateResponseClassifier.isRetryable(statusCode: 403), "403 retry")
        check(FilterUpdateResponseClassifier.isRetryable(statusCode: 429), "429 retry")
        check(FilterUpdateResponseClassifier.isRetryable(statusCode: 500), "500 retry")
        check(FilterUpdateResponseClassifier.classify(statusCode: 200, responseData: Data("<html>challenge</html>".utf8), localData: nil) == .invalidContent, "HTML invalid")
        check(FilterUpdateResponseClassifier.classify(statusCode: 200, responseData: Data("404: Not Found".utf8), localData: nil) == .invalidContent, "404 body invalid")
        check(!FilterUpdateResponseClassifier.looksLikeFilterListData(Data()), "empty")
        print("PASS")
    }
}
