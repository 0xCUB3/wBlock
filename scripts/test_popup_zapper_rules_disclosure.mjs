#!/usr/bin/env node
// The zapper Rules disclosure must have its rows laid out before the panel
// starts its height animation, and must not re-render mid-animation unless
// the authoritative rules actually differ (Christopher Galicia, email).
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const popup = readFileSync(path.join(root, 'wBlock Scripts (iOS)', 'Resources/pages/popup/popup.js'), 'utf8');

let failed = false;
function check(condition, message) {
  if (!condition) {
    failed = true;
    console.error(`FAIL: ${message}`);
  }
}

const start = popup.indexOf("rulesToggle.addEventListener('click'");
check(start >= 0, 'rules toggle click handler exists');
const handler = popup.slice(start, popup.indexOf('});', start));

const renderIndex = handler.indexOf('renderZapperRules(currentZapperRules)');
const openIndex = handler.indexOf('setRulesExpanded(true)');
check(renderIndex >= 0 && openIndex >= 0 && renderIndex < openIndex,
  'rows are rendered before the panel is opened');
check(handler.includes('if (changed) renderZapperRules(currentZapperRules)'),
  'authoritative rules only re-render the list when they differ');
check(handler.includes('if (!zapperRulesExpanded) return;'),
  'a fetch that lands after the panel closed does not render into it');

if (failed) process.exit(1);
console.log('PASS test_popup_zapper_rules_disclosure');
