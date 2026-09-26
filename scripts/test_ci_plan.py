import unittest
from ci_plan import select_checks


class CIPlanTests(unittest.TestCase):
    def test_javascript_and_pipeline_changes_need_no_mac_runner(self):
        plan = select_checks([
            'extension-src/background.js', 'wBlock Scripts (iOS)/Resources/background.js',
            'scripts/test_background_config_cache.mjs', 'scripts/minify-extension-js.sh',
            '.github/workflows/ci.yml', 'scripts/ci_plan.py',
        ])
        self.assertEqual(plan, dict(javascript=True, native=False, build=False, rules_ui=False, sheet_ui=False))

    def test_native_test_changes_do_not_rebuild_both_apps(self):
        for path in ('scripts/run-ci-tests.sh', 'scripts/test_new_native.swift'):
            plan = select_checks([path])
            self.assertTrue(plan['native'])
            self.assertFalse(plan['build'])

    def test_ui_fixtures_do_not_run_unrelated_native_checks(self):
        for path in ('scripts/rules-viewer-ui/App.swift', 'scripts/test_rules_viewer_ui.sh',
                     'scripts/test_apply_sheet_presentation.swift'):
            plan = select_checks([path])
            self.assertFalse(plan['native'])
            self.assertFalse(plan['build'])
            self.assertTrue(plan['rules_ui'] or plan['sheet_ui'])

    def test_docs_and_empty_changes_skip_expensive_checks(self):
        for paths in ([], ['README.md', 'docs/usage.md', 'LICENSE', '.github/ISSUE_TEMPLATE/bug.yml']):
            self.assertFalse(any(select_checks(paths).values()))

    def test_unknown_and_packaging_files_fail_closed_to_native(self):
        for path in ('new-target/code.xyz', 'wBlock/Info.plist', 'wBlock.xcodeproj/project.pbxproj',
                     'wBlock Scripts (iOS)/Resources/manifest.json', 'wBlock/Localizable.xcstrings',
                     'scripts/test_new_native.sh', 'wBlockCoreService/Utils.swift'):
            with self.subTest(path=path):
                self.assertTrue(select_checks([path])['native'])

    def test_ui_suites_only_run_for_their_production_or_fixture_sources(self):
        for path in ('wBlock/MonospacedTextView.swift', 'wBlock/ViewportSyntaxHighlighter.swift',
                     'wBlock/AdGuardSyntaxHighlighter.swift', 'scripts/rules-viewer-ui/project.yml',
                     'scripts/test_rules_viewer_ui.sh'):
            plan = select_checks([path])
            self.assertTrue(plan['rules_ui'])
            self.assertFalse(plan['sheet_ui'])
        for path in ('wBlock/SwiftUICompatibility.swift', 'scripts/test_apply_sheet_presentation.swift',
                     'scripts/test_apply_sheet_presentation.sh'):
            plan = select_checks([path])
            self.assertTrue(plan['sheet_ui'])
            self.assertFalse(plan['rules_ui'])

    def test_combined_changes_keep_both_ui_suites(self):
        plan = select_checks(['wBlock/MonospacedTextView.swift', 'wBlock/SwiftUICompatibility.swift'])
        self.assertTrue(all(plan.values()))

    def test_full_run_overrides_path_filters(self):
        self.assertTrue(all(select_checks([], full=True).values()))


if __name__ == '__main__':
    unittest.main()
