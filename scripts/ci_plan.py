#!/usr/bin/env python3
"""Select CI work from all changed paths; unknown files retain native checks."""
import sys
from pathlib import Path, PurePosixPath

RULES_SOURCES = {
    'wBlock/MonospacedTextView.swift',
    'wBlock/ViewportSyntaxHighlighter.swift',
    'wBlock/AdGuardSyntaxHighlighter.swift',
    'scripts/test_rules_viewer_ui.sh',
}
SHEET_SOURCES = {
    'wBlock/SwiftUICompatibility.swift',
    'scripts/test_apply_sheet_presentation.swift',
    'scripts/test_apply_sheet_presentation.sh',
}
CHEAP_SOURCES = {
    '.github/workflows/ci.yml', 'scripts/ci_plan.py', 'scripts/test_ci_plan.py',
    'scripts/minify-extension-js.sh',
    'scripts/update-scriptlets.sh',
}


def select_checks(paths, full=False):
    paths = {p for p in paths if p and not (
        p.startswith(('docs/', 'screenshots/', '.github/ISSUE_TEMPLATE/'))
        or (len(PurePosixPath(p).parts) == 1 and (
            p.endswith('.md') or p.startswith(('LICENSE', 'NOTICE'))))
    )}
    native = {p for p in paths if p not in CHEAP_SOURCES and not p.endswith(
        ('.js', '.mjs', '.css', '.html')) and not (
            p.startswith('scripts/rules-viewer-ui/') or
            (p.startswith('scripts/') and p in RULES_SOURCES | SHEET_SOURCES))}
    return {
        'javascript': full or bool(paths),
        'native': full or bool(native),
        'build': full or any(p != 'scripts/run-ci-tests.sh' and not p.startswith(
            'scripts/test_') for p in native),
        'rules_ui': full or bool(paths & RULES_SOURCES) or any(
            p.startswith('scripts/rules-viewer-ui/') for p in paths),
        'sheet_ui': full or bool(paths & SHEET_SOURCES),
    }


if __name__ == '__main__':
    full = sys.argv[1:] == ['--full']
    paths = [] if full else Path(sys.argv[1]).read_text().split('\0')
    for key, enabled in select_checks(paths, full).items():
        print(f'{key}={str(enabled).lower()}')
