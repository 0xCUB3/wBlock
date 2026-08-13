#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';

const root = process.cwd();
const read = (relativePath) => fs.readFileSync(path.join(root, relativePath), 'utf8');
const check = (condition, message) => {
  if (!condition) {
    throw new Error(`FAIL: ${message}`);
  }
};

const popup = read('wBlock Scripts (iOS)/Resources/pages/popup/popup.js');
const html = read('wBlock Scripts (iOS)/Resources/pages/popup/popup.html');
const css = read('wBlock Scripts (iOS)/Resources/pages/popup/popup.css');
const background = read('extension-src/background.js');
const native = read('wBlockCoreService/WebExtensionRequestHandler.swift');
const xpc = read('wBlockCoreService/FilterUpdateXPC.swift');
const service = read('FilterUpdateService/FilterUpdateService.swift');
const manager = read('wBlock/AppFilterManager.swift');
const popupStatus = read('wBlockCoreService/FilterUpdatePopupStatus.swift');

check(html.includes('id="update-filters"') && html.includes('id="filter-update-status"'),
  'popup must expose an accessible update action and live status');
check(html.includes('class="popup-actions"') && html.includes('class="popup-action-row"') &&
  !html.includes('class="section filter-update-section"') &&
  !html.includes('data-i18n="popup_filter_update_label"') &&
  css.includes('.popup-action-row .btn {') && css.includes('flex: 1 1 0;') && css.includes('width: 0;'),
  'Update Filters and Resume Blocking must share one equal-width action row');
check(popup.includes("action: 'wblock:filterUpdate:start'") &&
  popup.includes("action: 'wblock:filterUpdate:getStatus'"),
  'popup must use the registered background bridge for start and status requests');
check(popup.includes('FILTER_UPDATE_POLL_ATTEMPTS') && popup.includes('snapshot.state === \'running\''),
  'popup must poll a persisted running state after reopening');
check(popup.includes('button.disabled = state === \'running\''),
  'popup must prevent duplicate update requests while running');
check(popup.includes("popup_status_filters_updated") &&
  popup.includes("popup_status_filters_no_change") &&
  popup.includes("popup_error_filter_update"),
  'popup must render success, no-change, and error states');
check(css.includes('.filter-update-status.is-running::before') &&
  css.includes('prefers-reduced-motion'),
  'popup progress must be compact, accessible, and motion-aware');

check(background.includes('message.action === "wblock:filterUpdate:start"') &&
  background.includes('action: "startFilterUpdate"'),
  'background bridge must register the native start request');
check(background.includes('message.action === "wblock:filterUpdate:getStatus"') &&
  background.includes('action: "getFilterUpdateStatus"'),
  'background bridge must register the native status request');
check(native.includes('case "startFilterUpdate":') &&
  native.includes('case "getFilterUpdateStatus":'),
  'native handler must register both update actions');
check(manager.includes('handleFilterUpdateRequest()') &&
  manager.includes('trigger: "Popup"') && manager.includes('force: true') &&
  manager.includes('FilterUpdatePopupStatus.finish(outcome)'),
  'resident-app popup requests must run and publish the forced shared update directly');
check(native.includes('NSRunningApplication.runningApplications') &&
  native.includes('FilterUpdatePopupStatus.requestUpdate()') &&
  popupStatus.includes('CFNotificationCenterPostNotification') &&
  manager.includes('CFNotificationCenterAddObserver'),
  'native start must signal a running app without activating or foregrounding it');
check(service.includes('FilterUpdatePopupStatus.beginIfIdle()') &&
  service.includes('FilterUpdatePopupStatus.finish(outcome)'),
  'XPC fallback must retain lifecycle status for a terminated app');
check(xpc.includes('public func startFilterUpdate') && xpc.includes('filterProxy.startFilterUpdate'),
  'XPC bridge must expose an acknowledged background start request');
check(popupStatus.includes('.noFilterUpdates') && popupStatus.includes('case .failed(let message)'),
  'status store must preserve no-change and failure outcomes');
check(native.includes('FilterUpdatePopupStatus.consumeSnapshot()') &&
  popupStatus.includes('current.state != .idle, current.state != .running'),
  'terminal status must be shown once, then clear before the popup reopens');

const updateHandler = native.slice(native.indexOf('private static func handleStartFilterUpdate'), native.indexOf('private static func handleOpenContainingApp'));
check(!updateHandler.includes('openContainingApp') && !updateHandler.includes('NSWorkspace') && !updateHandler.includes('openApplication'),
  'filter update action must not foreground or open the containing app');

const localeRoot = path.join(root, 'wBlock Scripts (iOS)/Resources/_locales');
const locales = fs.readdirSync(localeRoot).filter((name) => fs.statSync(path.join(localeRoot, name)).isDirectory());
const englishKeys = Object.keys(JSON.parse(read('wBlock Scripts (iOS)/Resources/_locales/en/messages.json'))).sort();
for (const locale of locales) {
  const messages = JSON.parse(fs.readFileSync(path.join(localeRoot, locale, 'messages.json'), 'utf8'));
  check(JSON.stringify(Object.keys(messages).sort()) === JSON.stringify(englishKeys),
    `${locale} must preserve localization key parity`);
  for (const key of ['popup_filter_update_label', 'popup_button_update_filters',
    'popup_status_updating_filters', 'popup_status_filters_updated',
    'popup_status_filters_no_change', 'popup_error_filter_update',
    'popup_error_filter_update_start']) {
    check(typeof messages[key]?.message === 'string' && messages[key].message.length > 0,
      `${locale} is missing ${key}`);
  }
}

const outcomes = [
  ['running', 'running'],
  ['succeeded', 'succeeded'],
  ['no_change', 'no_change'],
  ['failed', 'failed'],
];
for (const [input, expected] of outcomes) check(input === expected, `status model must preserve ${expected}`);

console.log('PASS: popup filter update bridge, lifecycle, UI, localization, and no-foreground contract');
