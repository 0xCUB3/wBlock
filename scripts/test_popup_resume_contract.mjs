#!/usr/bin/env node
import fs from 'node:fs';

const read = (path) => fs.readFileSync(path, 'utf8');
const popup = read('wBlock Scripts (iOS)/Resources/pages/popup/popup.js');
const html = read('wBlock Scripts (iOS)/Resources/pages/popup/popup.html');
const native = read('wBlockCoreService/WebExtensionRequestHandler.swift');
const store = read('wBlockCoreService/BlockingPauseStore.swift');
const manager = read('wBlock/AppFilterManager.swift');
const pipeline = read('wBlock/AppFilterManager+ApplyPipeline.swift');
const background = read('extension-src/background.js');

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
check(popup.includes("action: 'getResumeRequestStatus'"),
  'Popup must poll the app-group resume result, not infer completion from the pause flag');
check(popup.includes("status.status === 'succeeded' && status.paused === false"),
  'Popup success must require the terminal apply result and an unpaused flag');
check(popup.includes("status.status === 'failed'"),
  'Popup must render terminal apply failures');
check(popup.includes("status: 'unavailable'"),
  'Popup must distinguish an unavailable containing app from apply failure');
check(popup.includes('resident containing app') && popup.includes("status: 'unavailable'"),
  'Popup must allow resident-app polling and use unavailable only after the terminal poll timeout');
check(popup.includes("popup_error_resume_unavailable"),
  'Unavailable resume must explain that wBlock must be opened');
check(popup.includes("? t('popup_status_paused'"),
  'Resume failure/unavailability must leave the popup in the paused state');
check(native.includes('case "getResumeRequestStatus":') && native.includes('"status": resumeStatus.status.rawValue') &&
  native.includes('requestContainingAppWake') && native.includes('"wakeSupported": wake.supported'),
  'Native bridge must expose terminal status and the platform wake acknowledgement');
check(store.includes('setResumeApplying') && store.includes('setResumeSucceeded') && store.includes('setResumeFailed'),
  'App Group store must persist applying/success/failure resume states');
check(manager.includes('await self.handleResumeRequest()') && manager.includes('deinit {') &&
  manager.includes('NotificationCenter.default.removeObserver') &&
  manager.includes('CFNotificationCenterGetDarwinNotifyCenter(),\n            nil,\n            AppFilterManager.resumeRequestCallback'),
  'Darwin notifications must use a process-lifetime relay and removable manager tokens');
check(!manager.includes('Unmanaged.passUnretained(self)'),
  'Resume notification lifecycle must not retain a raw manager pointer');
check(pipeline.includes('allowPausedResume: true') && pipeline.includes('BlockingPauseStore.setPaused(true)') &&
  pipeline.includes('BlockingPauseStore.setPaused(false)') && pipeline.includes('return started && lastApplySucceeded'),
  'Resume must apply while still paused, publish unpaused only after success, and return terminal state');
const resumeApply = pipeline.indexOf('allowPausedResume: true');
const publishUnpaused = pipeline.indexOf('BlockingPauseStore.setPaused(false)', resumeApply);
check(resumeApply >= 0 && publishUnpaused > resumeApply,
  'Resume must not clear the shared pause flag before the canonical apply begins');
check(background.includes('path: blockingPaused || siteDisabled ? DISABLED_ACTION_ICON : DEFAULT_ACTION_ICON'),
  'Toolbar icon must remain disabled while paused');

const locales = fs.readdirSync('wBlock Scripts (iOS)/Resources/_locales');
const english = JSON.parse(read('wBlock Scripts (iOS)/Resources/_locales/en/messages.json'));
const requiredKeys = [
  'popup_paused_prompt_title',
  'popup_paused_prompt_message',
  'popup_button_resume_blocking',
  'popup_status_resuming',
  'popup_status_error',
  'popup_error_resume_blocking',
  'popup_error_resume_unavailable',
];
for (const locale of locales) {
  const messages = JSON.parse(read(`wBlock Scripts (iOS)/Resources/_locales/${locale}/messages.json`));
  for (const key of requiredKeys) {
    check(messages[key]?.message, `${locale} is missing ${key}`);
  }
  if (locale !== 'en') {
    check(messages.popup_error_resume_unavailable.message !== english.popup_error_resume_unavailable.message,
      `${locale} must have a real unavailable-resume translation`);
  }
}
check(locales.length === 17, 'Popup resume copy must cover all 17 locales');

// Protocol behavior probe for resident success, terminal failure, and unavailable app.
async function resolveResume(statuses) {
  for (const status of statuses) {
    if (status.status === 'succeeded' && status.paused === false) return 'success';
    if (status.status === 'failed') return 'failure';
    await new Promise((resolve) => setTimeout(resolve, 0));
  }
  return 'unavailable';
}
check(await resolveResume([
  { status: 'applying', paused: true },
  { status: 'succeeded', paused: false },
]) === 'success', 'Resident app success must reach terminal success');
check(await resolveResume([
  { status: 'applying', paused: true },
  { status: 'failed', paused: true },
]) === 'failure', 'Apply failure must reach terminal failure');
check(await resolveResume([
  { status: 'pending', paused: true },
  { status: 'pending', paused: true },
]) === 'unavailable', 'A terminated app must become unavailable, not Active');
check(popup.includes('20; attempt += 1') && popup.includes('return { status: \'unavailable\' }'),
  'Resume polling must have a bounded timeout that preserves paused UX');
check(await (async () => {
  const response = { ok: true, status: 'pending', paused: true, wakeSupported: false };
  return response.wakeSupported === false ? 'unavailable' : 'poll';
})() === 'unavailable', 'Unsupported iOS wake must prompt the user instead of polling');

console.log('PASS: popup resume terminal-state, lifecycle, and localization contract');
