#!/usr/bin/env node
import fs from 'node:fs';

const read = (path) => fs.readFileSync(path, 'utf8');
const popup = read('wBlock Scripts (iOS)/Resources/pages/popup/popup.js');
const html = read('wBlock Scripts (iOS)/Resources/pages/popup/popup.html');
const native = read('wBlockCoreService/WebExtensionRequestHandler.swift');
const store = read('wBlockCoreService/BlockingPauseStore.swift');
const manager = read('wBlock/AppFilterManager.swift');

function check(condition, message) {
  if (!condition) {
    console.error(`FAIL: ${message}`);
    process.exit(1);
  }
}

check(html.includes('id="paused-prompt"') && html.includes('id="resume-blocking"'),
  'Paused popup must expose an explicit prompt and Resume Blocking button');
check(popup.includes("action: 'resumeBlocking'"),
  'Resume button must route through a native resume action');
check(popup.includes("setStatus(t('popup_status_resuming'"),
  'Resume action must expose a loading state');
check(popup.includes("setError(t('popup_error_resume_blocking'"),
  'Resume action must expose a failure state');
check(popup.includes('if (blockingPaused === null)'),
  'Pause-state probe failures must not be treated as active blocking');
check(popup.includes('pausedPrompt.hidden = !blockingPaused'),
  'Paused prompt must follow the authoritative global pause state');
check(native.includes('case "resumeBlocking":') && native.includes('BlockingPauseStore.requestResume()'),
  'Native bridge must queue resume through the shared pause store');
check(store.includes('resumeRequestNotificationName') && store.includes('CFNotificationCenterPostNotification'),
  'Resume requests must cross the extension/app process boundary');
check(manager.includes('registerResumeRequestObserver()') && manager.includes('await manager.setBlockingPaused(false)'),
  'Containing app must consume the request through the canonical resume/apply lifecycle');

const localeRoot = 'wBlock Scripts (iOS)/Resources/_locales';
const requiredKeys = [
  'popup_paused_prompt_title',
  'popup_paused_prompt_message',
  'popup_button_resume_blocking',
  'popup_status_resuming',
  'popup_status_error',
  'popup_error_resume_blocking',
];
for (const locale of fs.readdirSync(localeRoot)) {
  const path = `${localeRoot}/${locale}/messages.json`;
  if (!fs.existsSync(path)) continue;
  const messages = JSON.parse(read(path));
  for (const key of requiredKeys) {
    check(messages[key]?.message, `${locale} is missing ${key}`);
  }
}

console.log('PASS: popup resume bridge and loading/failure contract');
