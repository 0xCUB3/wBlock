import Foundation

@main
struct TestZapperNativeRuleGenerator {
    static func main() {
        let generated = ZapperContentBlockerRuleGenerator.generatedRules(
            from: [
                "www.clubic.com": [
                    "div.sc-1mdokif-0.fwJpDj",
                    "form.sc-179azgf-0.boJzlO",
                    "div.sc-1mdokif-0.fwJpDj",
                    "   "
                ],
                "": [
                    ".ignored"
                ]
            ]
        )

        let expected = [
            "www.clubic.com##div.sc-1mdokif-0.fwJpDj",
            "www.clubic.com##form.sc-179azgf-0.boJzlO"
        ]

        guard generated == expected else {
            fputs("Expected generated rules to equal:\n\(expected)\nGot:\n\(generated)\n", stderr)
            exit(1)
        }

        let emptyGenerated = ZapperContentBlockerRuleGenerator.generatedRules(
            from: [
                "www.example.com": []
            ]
        )

        guard emptyGenerated.isEmpty else {
            fputs("Expected no generated rules for empty selector lists.\n", stderr)
            exit(1)
        }

        print("ok")
    }
}
