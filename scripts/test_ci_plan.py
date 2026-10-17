import unittest
from ci_plan import select_checks


class CIPlanTests(unittest.TestCase):
    def test_javascript_and_pipeline_changes_need_no_mac_runner(self):
        plan = select_checks([
            'extension-src/background.js', 'wBlock Scripts (iOS)/Resources/background.js',
            'scripts/test_background_config_cache.mjs', 'scripts/minify-extension-js.sh',
            '.github/workflows/ci.yml', 'scripts/ci_plan.py',
        ])
        self.assertEqual(plan, dict(javascript=True, native=False, build=False, sheet_ui=False))

    def test_native_test_changes_do_not_rebuild_both_apps(self):
        for path in ('scripts/run-ci-tests.sh', 'scripts/test_new_native.swift'):
            plan = select_checks([path])
            self.assertTrue(plan['native'])
            self.assertFalse(plan['build'])

    def test_ui_fixtures_do_not_run_unrelated_native_checks(self):
        for path in ('scripts/test_apply_sheet_presentation.swift', 'scripts/test_apply_sheet_presentation.sh'):
            plan = select_checks([path])
            self.assertFalse(plan['native'])
            self.assertFalse(plan['build'])
            self.assertTrue(plan['sheet_ui'])

    def test_docs_and_empty_changes_skip_expensive_checks(self):
        for paths in ([], ['README.md', 'docs/usage.md', 'LICENSE', '.github/ISSUE_TEMPLATE/bug.yml']):
            self.assertFalse(any(select_checks(paths).values()))

    def test_unknown_and_packaging_files_fail_closed_to_native(self):
        for path in ('new-target/code.xyz', 'wBlock/Info.plist', 'wBlock.xcodeproj/project.pbxproj',
                     'wBlock Scripts (iOS)/Resources/manifest.json', 'wBlock/Localizable.xcstrings',
                     'scripts/test_new_native.sh', 'wBlockCoreService/Utils.swift'):
            with self.subTest(path=path):
                self.assertTrue(select_checks([path])['native'])

    def test_sheet_suite_runs_only_for_its_sources(self):
        self.assertTrue(select_checks(['wBlock/SwiftUICompatibility.swift'])['sheet_ui'])
        self.assertFalse(select_checks(['wBlock/ContentView.swift'])['sheet_ui'])

    def test_full_run_overrides_path_filters(self):
        self.assertTrue(all(select_checks([], full=True).values()))


if __name__ == '__main__':
    unittest.main()
