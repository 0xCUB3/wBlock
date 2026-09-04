// #681 bonus: http and https variants of one list URL are the same list.
import Foundation
import wBlockCoreService

@main
struct Main {
    static func fail(_ message: String) -> Never {
        print("FAIL: \(message)")
        exit(1)
    }

    static func main() {
        let a = URL(string: "http://wblock.goat/list.txt")!
        let b = URL(string: "https://wblock.goat/list.txt")!
        let c = URL(string: "https://WBLOCK.goat:443/list.txt/")!
        let d = URL(string: "https://wblock.goat/other.txt")!
        if !FilterListURLSupport.isSameList(a, b) { fail("http and https variants must match") }
        if !FilterListURLSupport.isSameList(b, c) { fail("host case, default port and trailing slash must not matter") }
        if FilterListURLSupport.isSameList(a, d) { fail("different paths must stay distinct") }
        print("PASS")
    }
}
