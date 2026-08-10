import Foundation

@main
struct ApplyProgressLocalizationTests {
    static func main() {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let localizationRootURL = rootURL.appendingPathComponent("wBlock", isDirectory: true)
        let expectedKey = "Applying filters...\n(This may take a while)"
        let escapedKey = #"Applying filters...\n(This may take a while)"#
        let updateBreakdownKey = "Filters: %d / Userscripts: %d"
        let expectedStatusValuesByLocale = [
            "ar.lproj": [
                "Checking for Updates": "جارٍ التحقق من تحديثات عوامل التصفية",
                "Updating Scripts": "جارٍ التحقق من تحديثات نصوص المستخدم",
            ],
            "de.lproj": [
                "Checking for Updates": "Suche nach Filter-Updates",
                "Updating Scripts": "Suche nach Userscript-Updates",
            ],
            "el.lproj": [
                "Checking for Updates": "Έλεγχος για ενημερώσεις φίλτρων",
                "Updating Scripts": "Έλεγχος για ενημερώσεις σεναρίων χρήστη",
            ],
            "en.lproj": [
                "Checking for Updates": "Checking for Filter Updates",
                "Updating Scripts": "Checking for Userscript Updates",
            ],
            "es.lproj": [
                "Checking for Updates": "Buscando actualizaciones de filtros",
                "Updating Scripts": "Buscando actualizaciones de scripts de usuario",
            ],
            "fr.lproj": [
                "Checking for Updates": "Recherche de mises à jour des filtres",
                "Updating Scripts": "Recherche de mises à jour des scripts utilisateur",
            ],
            "hu.lproj": [
                "Checking for Updates": "Szűrőfrissítések keresése",
                "Updating Scripts": "Felhasználói szkriptfrissítések keresése",
            ],
            "it.lproj": [
                "Checking for Updates": "Controllo aggiornamenti dei filtri",
                "Updating Scripts": "Controllo aggiornamenti degli script utente",
            ],
            "ja.lproj": [
                "Checking for Updates": "フィルターを更新中",
                "Updating Scripts": "ユーザースクリプトを更新中",
            ],
            "ko.lproj": [
                "Checking for Updates": "필터 업데이트 확인 중",
                "Updating Scripts": "사용자 스크립트 업데이트 확인 중",
            ],
            "pl.lproj": [
                "Checking for Updates": "Sprawdzanie aktualizacji filtrów",
                "Updating Scripts": "Sprawdzanie aktualizacji skryptów użytkownika",
            ],
            "pt-BR.lproj": [
                "Checking for Updates": "Verificando atualizações de filtros",
                "Updating Scripts": "Verificando atualizações de scripts de usuário",
            ],
            "ro.lproj": [
                "Checking for Updates": "Se verifică actualizările filtrelor",
                "Updating Scripts": "Se verifică actualizările scripturilor de utilizator",
            ],
            "ru.lproj": [
                "Checking for Updates": "Проверка обновлений фильтров",
                "Updating Scripts": "Проверка обновлений пользовательских скриптов",
            ],
            "tr.lproj": [
                "Checking for Updates": "Filtre güncellemeleri denetleniyor",
                "Updating Scripts": "Kullanıcı betiği güncellemeleri denetleniyor",
            ],
            "zh-Hans.lproj": [
                "Checking for Updates": "正在检查过滤器更新",
                "Updating Scripts": "正在检查用户脚本更新",
            ],
            "zh-Hant.lproj": [
                "Checking for Updates": "正在檢查過濾器更新",
                "Updating Scripts": "正在檢查使用者腳本更新",
            ],
        ]

        do {
            let localeDirectories = try FileManager.default.contentsOfDirectory(
                at: localizationRootURL,
                includingPropertiesForKeys: nil
            )
            .filter { $0.pathExtension == "lproj" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

            guard !localeDirectories.isEmpty else {
                fail("expected localization directories to exist")
            }

            for localeDirectory in localeDirectories {
                let stringsURL = localeDirectory.appendingPathComponent("Localizable.strings")
                guard let table = NSDictionary(contentsOf: stringsURL) as? [String: String] else {
                    fail("failed to parse \(stringsURL.path)")
                }

                guard let value = table[expectedKey] else {
                    fail("missing localized apply progress key in \(localeDirectory.lastPathComponent)")
                }

                guard table[escapedKey] == nil else {
                    fail("found literal escaped apply progress key in \(localeDirectory.lastPathComponent)")
                }

                guard !value.contains(#"\n"#) else {
                    fail("apply progress value contains a literal \\n in \(localeDirectory.lastPathComponent)")
                }

                guard let updateBreakdown = table[updateBreakdownKey] else {
                    fail("missing localized update breakdown key in \(localeDirectory.lastPathComponent)")
                }
                guard updateBreakdown.components(separatedBy: "%d").count == 3 else {
                    fail("update breakdown must preserve two integer placeholders in \(localeDirectory.lastPathComponent)")
                }

                guard let expectedStatusValues = expectedStatusValuesByLocale[localeDirectory.lastPathComponent] else {
                    fail("missing status expectations for \(localeDirectory.lastPathComponent)")
                }
                for (key, expectedValue) in expectedStatusValues {
                    guard table[key] == expectedValue else {
                        fail(
                            "unexpected \(key) value in \(localeDirectory.lastPathComponent): "
                                + "\(table[key] ?? "<missing>")"
                        )
                    }
                }
            }
        } catch {
            fail("localization test failed: \(error)")
        }

        print("PASS")
    }

    private static func fail(_ message: String) -> Never {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}
