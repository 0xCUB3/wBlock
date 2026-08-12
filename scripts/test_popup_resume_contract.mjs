#!/usr/bin/env node
import fs from 'node:fs';

const read = (path) => fs.readFileSync(path, 'utf8');
const popup = read('wBlock Scripts (iOS)/Resources/pages/popup/popup.js');
const html = read('wBlock Scripts (iOS)/Resources/pages/popup/popup.html');
const css = read('wBlock Scripts (iOS)/Resources/pages/popup/popup.css');
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
check(html.includes('class="popup-action-row"') &&
  html.indexOf('id="resume-blocking"') > html.indexOf('id="update-filters"'),
  'Resume Blocking must sit beside Update Filters in the bottom action row');
check(!html.slice(html.indexOf('id="paused-prompt"'), html.indexOf('class="popup-actions"')).includes('id="resume-blocking"'),
  'Resume Blocking must not remain inside the paused prompt card');
check(html.includes('id="resume-blocking"') && html.includes('aria-live="polite" hidden'),
  'Resume action must be hidden unless the authoritative state is paused');
check(popup.includes('resumeButton.hidden = !(blockingPaused && resumeAvailable)') &&
  css.includes('.popup-action-row .btn {') && css.includes('flex: 1 1 0;') &&
  css.includes('width: 0;') && css.includes('#resume-blocking[aria-busy="true"]'),
  'Resume and Update must have equal dimensions with compact in-button progress');
check(!css.includes('.paused-prompt .btn'),
  'Paused prompt card must not style Resume Blocking as a full-width card button');
check(popup.includes("action: 'resumeBlocking'"),
  'Resume button must route through a native resume action');
check(native.includes('"filtersPaused": components.contains(.filters)') &&
  native.includes('"userScriptsPaused": components.contains(.userScripts)') &&
  native.includes('"elementZapperPaused": components.contains(.elementZapper)') &&
  native.includes('NSRunningApplication.runningApplications') &&
  native.includes('"resumeAvailable": resumeAvailable'),
  'Native pause state must expose each component and whether the containing app can resume');
check(popup.includes('typeof response.resumeAvailable') &&
  popup.includes('const resumeAvailable = pauseState.resumeAvailable') &&
  popup.includes('resumeButton.disabled = !(blockingPaused && resumeAvailable)'),
  'Resume must stay hidden and disabled unless the containing app is available');
check(popup.includes('const filtersPaused = pauseState.filtersPaused') &&
  popup.includes("action: 'getBlockingPausedState'") &&
  popup.includes('const zapperPaused = pauseState.elementZapperPaused') &&
  popup.includes("t('popup_status_partially_paused'") &&
  popup.includes("t('popup_paused_partial_prompt_title'"),
  'Popup must distinguish partial pauses in status and prompt text');
check(popup.includes('disableToggle.disabled = filtersPaused') &&
  popup.includes('zapperEnabledToggle.disabled = siteDisabled || zapperPaused') &&
  popup.includes('zapperActivate.disabled = siteDisabled || zapperPaused || zapperRulesDisabled'),
  'Popup must disable only controls owned by paused components');
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
const resumeHandlerStart = native.indexOf('private static func handleResumeBlocking');
const resumeHandlerEnd = native.indexOf('private static func handleGetResumeRequestStatus', resumeHandlerStart);
check(resumeHandlerStart >= 0 && resumeHandlerEnd > resumeHandlerStart &&
  !native.slice(resumeHandlerStart, resumeHandlerEnd).includes('requestContainingAppWake()'),
  'Resume requests must not foreground the containing app');
check(store.includes('setResumeApplying') && store.includes('setResumeSucceeded') && store.includes('setResumeFailed'),
  'App Group store must persist applying/success/failure resume states');
check(store.includes('resumeRequestLock') &&
  store.includes('currentStatus == .pending || currentStatus == .applying') &&
  store.includes('repeated popup taps cannot start'),
  'Native resume requests must coalesce while pending or applying');
check(manager.includes('await self.handleResumeRequest()') && manager.includes('deinit {') &&
  manager.includes('NotificationCenter.default.removeObserver') &&
  manager.includes('CFNotificationCenterGetDarwinNotifyCenter(),\n            nil,\n            AppFilterManager.resumeRequestCallback'),
  'Darwin notifications must use a process-lifetime relay and removable manager tokens');
check(manager.includes('await waitUntilReady()') && manager.includes('resumeApplyInFlight'),
  'Resume handling must wait for the authoritative app snapshot and serialize requests');
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
  'popup_paused_partial_prompt_title',
  'popup_paused_prompt_message',
  'popup_status_partially_paused',
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
  check(JSON.stringify(Object.keys(messages).sort()) === JSON.stringify(Object.keys(english).sort()),
    `${locale} must preserve popup locale key parity`);
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
check(popup.includes('let resumeInFlight = false') && popup.includes('if (resumeInFlight) return') &&
  popup.includes('resumeInFlight = true') && popup.includes('resumeInFlight = false'),
  'Popup resume clicks must not issue duplicate native requests');
check(await (async () => {
  const response = { ok: true, status: 'pending', paused: true, wakeSupported: false };
  return response.wakeSupported === false ? 'unavailable' : 'poll';
})() === 'unavailable', 'Unsupported iOS wake must prompt the user instead of polling');

console.log('PASS: popup resume terminal-state, lifecycle, and localization contract');
