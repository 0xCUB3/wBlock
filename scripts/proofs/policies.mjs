import assert from 'node:assert/strict';
import { bool, nat, upTo, oneOf, min, max, fun, rule, when, forall, proveDecision, proveSteps, crossCheckDecision } from 'gdp-wired';

// These are specifications, not Swift proofs. verify.mjs compares their outputs
// with production Swift; neither a proof failure nor a disagreement may pass CI.
export const decisions = {};
let proven = 0, mutations = 0, concrete = 0, seed = 0x475044;
const draw = n => ((seed = (Math.imul(seed,1664525) + 1013904223) >>> 0) % n);
function verdict(v, claims=1) {
  assert.equal(v.proven, true, JSON.stringify(v));
  assert.equal(v.checked, true, JSON.stringify(v));
  proven += claims;
}
function checked(v) {
  assert.equal(v.failure, undefined, JSON.stringify(v));
  assert.ok(v.checked > 0);
  concrete += v.checked;
}
function decision(name, inputs, outputs, laws, broken) {
  const model = fun(name).inputs(inputs).returns(outputs);
  const claims = laws(model);
  for (const claim of claims) { verdict(proveDecision(claim)); checked(crossCheckDecision(claim, {rand:draw})); }
  const mutant = fun(name).inputs(inputs).returns(e => ({...outputs(e), ...broken(e)}));
  const refusal = proveDecision(laws(mutant)[0]);
  assert.equal(refusal.proven, false, `${name} mutation escaped`);
  assert.equal(refusal.stuck, 'sat', JSON.stringify(refusal));
  mutations++;
  decisions[name] = model;
}
const booleans = (...names) => Object.fromEntries(names.map(k => [k, bool]));

decision('menus', booleans('remote', 'inline', 'custom', 'downloaded', 'builtIn', 'local'),
  ({remote, inline, custom, downloaded, builtIn, local}) => ({
    filterDownload: remote.and(downloaded.not()), filterSettings: downloaded.or(inline),
    filterEdit: inline, filterView: downloaded.and(inline.not()), filterMetadata: custom,
    scriptDownload: local.not().and(downloaded.not()), scriptSettings: downloaded,
    scriptEdit: downloaded.and(builtIn.not(), local), scriptView: downloaded.and(builtIn.or(local.not())), scriptMetadata: builtIn.not(),
  }), m => [
    m.law('built-in scripts cannot be edited', ({builtIn}) => builtIn, o => o.scriptEdit.not().and(o.scriptMetadata.not())),
    m.law('remote filters are read-only', ({remote, inline}) => remote.and(inline.not()), o => o.filterEdit.not()),
    m.law('undownloaded scripts have no content actions', ({downloaded}) => downloaded.not(), o => o.scriptSettings.not().and(o.scriptEdit.not(), o.scriptView.not())),
    m.law('local scripts are never downloaded', ({local}) => local, o => o.scriptDownload.not()),
    m.law('view and edit actions are exclusive', () => [], o => o.filterEdit.and(o.filterView).not().and(o.scriptEdit.and(o.scriptView).not())),
    m.law('remote script content stays read-only', ({local}) => local.not(), o => o.scriptEdit.not()),
  ], e => ({scriptEdit: e.builtIn.or(e.builtIn.not())}));

const recent = (has, timestamp, {now, interval}) => has.and(interval.gt(0), now.lt(timestamp.plus(interval)));
decision('refresh', {...booleans('remote', 'exists', 'automatic', 'hasGlobal', 'hasDownload', 'hasCheck'), now:nat, interval:nat, global:nat, download:nat, check:nat},
  e => ({fetch: e.remote.and(e.exists.not().or(e.automatic.and(
    recent(e.hasGlobal,e.global,e).not(), recent(e.hasDownload,e.download,e).not(), recent(e.hasCheck,e.check,e).not())))}), m => [
    m.law('local lists never fetch', ({remote}) => remote.not(), o => o.fetch.not()),
    m.law('missing remote content always fetches', ({remote,exists}) => remote.and(exists.not()), o => o.fetch),
    m.law('opt-out preserves cached content', ({exists,automatic}) => exists.and(automatic.not()), o => o.fetch.not()),
    m.law('recent verification preserves cached content', e => e.exists.and(recent(e.hasCheck,e.check,e)), o => o.fetch.not()),
    m.law('recent global checks preserve cached content', e => e.exists.and(recent(e.hasGlobal,e.global,e)), o => o.fetch.not()),
    m.law('fresh downloads preserve cached content', e => e.exists.and(recent(e.hasDownload,e.download,e)), o => o.fetch.not()),
  ], e => ({fetch:e.remote.or(e.remote.not())}));

decision('custom', {...booleans('tomb', 'local', 'remote', 'existed'), deletedAt:nat, remoteAt:nat},
  ({tomb,local,remote,existed,deletedAt,remoteAt}) => ({
    upload: tomb.and(local.not()), apply: tomb.and(local.not(),remote.not()),
    remove: tomb.and(local.not().or(existed)), clear: tomb.and(local.or(remote.and(remoteAt.gt(0),deletedAt.atMost(remoteAt)))),
  }), m => [
    m.law('a local re-add defeats upload tombstones', ({local}) => local, o => o.upload.not()),
    m.law('an in-flight addition survives deletion', ({local,existed}) => local.and(existed.not()), o => o.remove.not()),
    m.law('an older payload cannot clear a fresh tombstone', ({local,deletedAt,remoteAt}) => local.not().and(deletedAt.gt(remoteAt)), o => o.clear.not()),
    m.law('a live remote copy defeats apply tombstones', ({remote}) => remote, o => o.apply.not()),
  ], e => ({upload:e.local.or(e.local.not())}));

decision('remote', {...booleans('tomb', 'local', 'remote', 'added', 'synced'), generation:nat, snapshot:nat},
  ({tomb,local,remote,added,synced,generation,snapshot}) => ({
    upload: tomb.and(local.and(added).not()), apply: tomb.and(remote.or(local.and(added)).not()),
    clearUpload: tomb.and(local,added), clearApply: tomb.and(remote.or(local.and(added))),
    keepAdd: synced.not().or(generation.eq(snapshot).not()),
  }), m => [
    m.law('mere presence cannot resurrect a deleted script', ({tomb,added}) => tomb.and(added.not()), o => o.upload),
    m.law('a newer add generation survives acknowledgment', ({generation,snapshot}) => generation.eq(snapshot).not(), o => o.keepAdd),
    m.law('an unsynced addition cannot be acknowledged', ({synced}) => synced.not(), o => o.keepAdd),
    m.law('an explicit live re-add defeats deletion', ({local,added}) => local.and(added), o => o.apply.not()),
    m.law('a synced matching generation is consumed', ({synced,generation,snapshot}) => synced.and(generation.eq(snapshot)), o => o.keepAdd.not()),
  ], e => ({upload:e.tomb.and(e.tomb.not())}));

decision('rebase', booleans('persisted','oldName','newName','oldDescription','newDescription','selected','automatic','onlySelected'),
  e => ({useName:e.persisted.and(e.newName.or(e.oldName)),
    useDescription:e.persisted.and(e.newDescription.or(e.oldDescription)),
    selected:e.persisted.not().or(e.selected), automatic:e.persisted.not().or(e.automatic),
    nameFlag:e.persisted.and(e.newName).or(e.persisted.not().and(e.oldName)), descriptionFlag:e.persisted.and(e.newDescription).or(e.persisted.not().and(e.oldDescription)),
    onlySelected:e.persisted.and(e.onlySelected)}), m => [
    m.law('a manual name survives writeback', ({persisted,newName}) => persisted.and(newName), o => o.useName),
    m.law('clearing a manual name replaces its old value', ({persisted,oldName,newName}) => persisted.and(oldName,newName.not()), o => o.useName),
    m.law('absent persisted records keep snapshot metadata', ({persisted}) => persisted.not(), o => o.useName.not().and(o.useDescription.not())),
    m.law('latest selection wins', () => [], (o,e) => e.persisted.implies(o.selected.implies(e.selected).and(e.selected.implies(o.selected)))),
    m.law('latest automatic update preference wins', () => [], (o,e) => e.persisted.implies(o.automatic.implies(e.automatic).and(e.automatic.implies(o.automatic)))),
    m.law('a manual description survives writeback', ({persisted,newDescription}) => persisted.and(newDescription), o => o.useDescription),
    m.law('clearing a manual description replaces its old value', ({persisted,oldDescription,newDescription}) => persisted.and(oldDescription,newDescription.not()), o => o.useDescription),
  ], e => ({useName:e.persisted.and(e.persisted.not())}));

decision('local', booleans('identity','remotePresent','remoteIdentity','sameIdentity','sameName','validName','tombName','syncedName','tombIdentity','syncedIdentity'),
  e => {
    const matches=e.remotePresent.and(e.identity.and(e.remoteIdentity).and(e.sameIdentity).or(e.identity.and(e.remoteIdentity).not().and(e.sameName)));
    const distinct=e.remotePresent.and(e.sameName,e.remoteIdentity);
    const remove=e.identity.and(e.tombIdentity).or(matches.not().and(e.identity.and(e.syncedIdentity.or(distinct.not().and(e.tombName.or(e.syncedName)))).or(e.identity.not().and(e.tombName.or(e.syncedName)))));
    const blocked=e.identity.and(e.tombIdentity.or(e.syncedIdentity)).or(e.identity.not().and(e.tombName.or(e.syncedName)));
    return {matches,remove:e.validName.and(remove),upload:e.validName.and(matches.not(),blocked.not())};
  }, m => [
    m.law('distinct stable identities never match by name', e=>e.identity.and(e.remoteIdentity,e.sameIdentity.not()), o=>o.matches.not()),
    m.law('stable tombstones prevent resurrection', e=>e.validName.and(e.identity,e.tombIdentity), o=>o.remove.and(o.upload.not())),
    m.law('invalid names are neither uploaded nor deleted', e=>e.validName.not(), o=>o.remove.not().and(o.upload.not())),
    m.law('never-synced stable imports ignore ambiguous name tombstones', e=>e.identity.and(e.tombIdentity.not(),e.syncedIdentity.not(),e.validName), (o,e)=>o.matches.not().implies(o.upload)),
  ], e=>({matches:e.identity.or(e.identity.not())}));

decision('localSets', booleans('tomb','local','remote','remoteTomb'),
  ({tomb,local,remote,remoteTomb})=>({clearUpload:tomb.and(local),mergeUpload:tomb.and(local.not()),mergeApply:tomb.and(local.not(),remote.not()),clearApply:tomb.and(local.or(remote),remoteTomb.not())}), m=>[
    m.law('remote tombstones cannot be cleared by stale live copies', e=>e.remoteTomb, o=>o.clearApply.not()),
    m.law('local re-adds defeat merge tombstones', e=>e.local, o=>o.mergeUpload.not().and(o.mergeApply.not())),
  ], e=>({clearApply:e.tomb.or(e.tomb.not())}));

// One built-in list, at its current address here, against a remote payload:
// the three-way merge, the payload's custom lists, and what it knows. A 3.x
// device names some lists by an old address ("Legacy"). For those 3.x maps
// back ("reconciled") it follows this device's choice, so the entry counts as
// the current address; for the rest it never does, so the entry must not count.
const iff = (a, b) => a.implies(b).and(b.implies(a));
const selection = (e, legacyAlwaysCounts=false) => {
  const counts = legacyAlwaysCounts ? e.reconciled.or(e.reconciled.not()) : e.reconciled;
  const at = (cur, legacy) => cur.or(legacy.and(counts)).and(e.custom.not());
  const local = e.local.and(e.custom.not()), base = at(e.base, e.baseLegacy), remote = at(e.remote, e.remoteLegacy);
  const merged = remote.and(base.and(local.not()).not()).or(local.and(base.not()));
  const known = e.knownNil.and(merged).or(e.knownNil.not().and(at(e.knownCur, e.knownLegacy)));
  return {selected: known.and(merged).or(known.not().and(e.local))};
};
const baseAt = e => e.base.or(e.baseLegacy.and(e.reconciled));
decision('selection', booleans('local','base','baseLegacy','remote','remoteLegacy','knownNil','knownCur','knownLegacy','custom','reconciled'),
  e => selection(e), m => [
    m.law('an old address 3.x cannot reconcile never switches a list', e => e.remote.not().and(e.knownCur.not(), e.reconciled.not()), (o,e) => iff(o.selected, e.local)),
    m.law('a change made here since the last sync wins', e => e.custom.not().and(iff(e.local, baseAt(e)).not()), (o,e) => iff(o.selected, e.local)),
    m.law('an unchanged list follows the remote', e => iff(e.local, baseAt(e)).and(e.custom.not(), e.knownNil.not(), e.knownCur.or(e.knownLegacy.and(e.reconciled))),
      (o,e) => iff(o.selected, e.remote.or(e.remoteLegacy.and(e.reconciled)))),
    m.law('a list the remote also has as custom keeps its selection', e => e.custom, (o,e) => iff(o.selected, e.local)),
  ], e => selection(e, true));

// Two syncs of one list. The first payload may not name it usably ("named1"
// false: a 3.x payload); the baseline kept after it must still tell a change
// made here from one made elsewhere in the second sync.
const twoSyncs = (e, forgetful=false) => {
  const merge = (local, base, remote) => remote.and(base.and(local.not()).not()).or(local.and(base.not()));
  const pick = (named, value, other) => named.and(value).or(named.not().and(other));
  // A custom list at the same address makes the first payload's entry ambiguous, so it names nothing.
  const named1 = e.named1.and(e.custom1.not());
  const after1 = pick(named1, merge(e.localStart.and(e.custom1.not()), e.prevNamed.and(e.prevSel, e.custom1.not()), named1.and(e.sel1)), e.localStart);
  const base1 = forgetful ? named1.and(e.sel1) : pick(named1, e.sel1, pick(e.prevNamed, e.prevSel, e.localStart));
  const local2 = after1.and(e.toggled.not()).or(after1.not().and(e.toggled));
  return {result: pick(e.named2, merge(local2, base1, e.named2.and(e.sel2)), local2), local2};
};
decision('twoSyncs', booleans('prevNamed','prevSel','localStart','named1','sel1','custom1','toggled','named2','sel2'),
  e => ({result: twoSyncs(e).result}), m => [
    m.law('a change made elsewhere applies after a sync that could not name the list',
      e => e.toggled.not().and(e.named1.not().or(e.custom1), e.named2, e.prevNamed, iff(e.localStart, e.prevSel)), (o,e) => iff(o.result, e.sel2)),
    m.law('a change made here survives a sync that could not name the list',
      e => e.toggled.and(e.named1.not().or(e.custom1), e.named2, e.prevNamed, iff(e.localStart, e.prevSel), iff(e.sel2, e.prevSel)),
      (o,e) => iff(o.result, twoSyncs(e).local2)),
  ], e => ({result: twoSyncs(e, true).result}));

decision('customImport', booleans('builtInCurrent','builtInLegacy','variant'),
  ({builtInCurrent, builtInLegacy}) => ({import: builtInCurrent.or(builtInLegacy).not()}), m => [
    m.law('a copy of a built-in list is never imported', e => e.builtInLegacy.or(e.builtInCurrent), o => o.import.not()),
    m.law('other custom lists are imported', e => e.builtInLegacy.or(e.builtInCurrent).not(), o => o.import),
  ], e => ({import: e.builtInCurrent.not()}));

// Mirrors UserScriptFrameAuthorization.allows: unpaused, not disabled on the site, enabled, on an http(s) URL with a host,
// a noframes script only in the top frame, and matched but not excluded.
decision('frame', booleans('paused','disabledOnSite','enabled','webURL','noframes','top','matched','excluded'),
  e => ({allowed: e.paused.not().and(e.disabledOnSite.not(), e.enabled, e.webURL, e.noframes.not().or(e.top), e.matched, e.excluded.not())}), m => [
    m.law('a paused script never runs', ({paused}) => paused, o => o.allowed.not()),
    m.law('a script disabled on its site never runs', ({disabledOnSite}) => disabledOnSite, o => o.allowed.not()),
    m.law('a noframes script never runs in a subframe', ({noframes,top}) => noframes.and(top.not()), o => o.allowed.not()),
    m.law('a non-http(s) or hostless page never runs a script', ({webURL}) => webURL.not(), o => o.allowed.not()),
    m.law('an exclude beats a match', ({matched,excluded}) => matched.and(excluded), o => o.allowed.not()),
    m.law('an enabled, unpaused, matched top-frame page runs the script', e => e.paused.not().and(e.disabledOnSite.not(), e.enabled, e.webURL, e.noframes.not().or(e.top), e.matched, e.excluded.not()), o => o.allowed),
  ], e => ({allowed: e.disabledOnSite.not().and(e.enabled, e.webURL, e.noframes.not().or(e.top), e.matched, e.excluded.not())}));
// FilterListRemoteMetadataPolicy.applying: each header value is nil, blank or text. A manual flag or a built-in list keeps its name and description; version is always replaced ("Unknown" when absent).
decision('remoteMetadata', booleans('custom','userName','titlePresent','titleBlank','userDescription','descriptionPresent','descriptionBlank','versionPresent'),
  ({custom,userName,titlePresent,titleBlank,userDescription,descriptionPresent,descriptionBlank,versionPresent}) => ({
    takeTitle: custom.and(userName.not(), titlePresent, titleBlank.not()), takeDescription: custom.and(userDescription.not(), descriptionPresent, descriptionBlank.not()),
    versionUnknown: versionPresent.not(),
  }), m => [
    m.law('a manual name survives remote metadata', ({userName}) => userName, o => o.takeTitle.not()),
    m.law('a manual description survives remote metadata', ({userDescription}) => userDescription, o => o.takeDescription.not()),
    m.law('built-in lists never take header title or description', ({custom}) => custom.not(), o => o.takeTitle.not().and(o.takeDescription.not())),
    m.law('blank header values never replace metadata', () => [], (o,e) => e.titleBlank.implies(o.takeTitle.not()).and(e.descriptionBlank.implies(o.takeDescription.not()))),
    m.law('version is always replaced', () => [], (o,e) => iff(o.versionUnknown, e.versionPresent.not())),
  ], e => ({takeTitle: e.custom.and(e.titlePresent, e.titleBlank.not())}));

// ImportMetadataReview.userProvided: an unchanged prefill stays automatic, a cleared prefill is an explicit empty override.
decision('importReview', booleans('present','same','blank'),
  ({present,same,blank}) => ({override: present.and(same.not()), cleared: present.and(same.not(), blank)}), m => [
    m.law('an unchanged prefill stays automatic', ({present,same}) => present.and(same), o => o.override.not()),
    m.law('a cleared prefill is an explicit empty override', ({present,same,blank}) => present.and(same.not(), blank), o => o.override.and(o.cleared)),
    m.law('an untouched field stays automatic', ({present}) => present.not(), o => o.override.not().and(o.cleared.not())),
  ], e => ({override: e.present}));

export const upload = rule('deferred uploads').inputs({take:bool,syncing:bool,trigger:nat}).state({pending:0,kind:0,value:0});
const uploadStep = ({take,syncing,trigger,pending}) => ({
  pending:when(take,0,when(syncing,trigger.plus(1),pending)), kind:when(take,2,when(syncing,1,0)),
  value:when(take,pending,when(syncing,0,trigger.plus(1))),
});
export const uploadRule = upload.step(uploadStep);
const uploadLaws = [
  uploadRule.stepLaw('latest deferred request wins', ({trigger},a) => a.pending.eq(trigger.plus(1)), e => e.take.not().and(e.syncing)),
  uploadRule.stepLaw('busy requests are deferred', (_,a) => a.kind.eq(1).and(a.value.eq(0)), e => e.take.not().and(e.syncing)),
  uploadRule.stepLaw('taking drains the request', (_,a) => a.pending.eq(0), e => e.take),
  uploadRule.stepLaw('taking returns the old request', ({pending},a) => a.value.eq(pending), e => e.take),
  uploadRule.stepLaw('idle requests preserve pending work', ({pending},a) => a.pending.eq(pending), e => e.take.not().and(e.syncing.not())),
  uploadRule.stepLaw('idle requests start their own trigger', ({trigger},a) => a.kind.eq(0).and(a.value.eq(trigger.plus(1))), e => e.take.not().and(e.syncing.not())),
];

export const revisions = rule('revision acknowledgment').inputs({op:upTo(2),key:nat,token:nat}).maps({Current:0,Snapshot:0});
const revisionStep = ({op,key,token,Current,Snapshot}, broken=false) => ({
  Current:Current.each(k => {
    const downloaded = op.eq(0).and(k.eq(key));
    const matches = broken ? op.eq(2).or(op.eq(2).not()) : Current.at(k).eq(Snapshot.at(k));
    const acknowledged = op.eq(2).and(Snapshot.at(k).gt(0), matches);
    return when(downloaded,token.plus(1),when(acknowledged,0,Current.at(k)));
  }),
  Snapshot:Snapshot.set(key,when(op.eq(1),Current.at(key),Snapshot.at(key))),
});
export const revisionRule = revisions.step(revisionStep);
const revisionLaws = [
  revisionRule.stepLaw('stale snapshots preserve newer revisions', ({Current,Snapshot},a) => forall(k => Current.at(k).eq(Snapshot.at(k)).not().implies(a.Current.at(k).eq(Current.at(k)))), e => e.op.eq(2)),
  revisionRule.stepLaw('matching snapshots are acknowledged', ({Current,Snapshot},a) => forall(k => Current.at(k).eq(Snapshot.at(k)).implies(a.Current.at(k).eq(0))), e => e.op.eq(2)),
  revisionRule.stepLaw('snapshotting does not consume work', ({Current},a) => forall(k => a.Current.at(k).eq(Current.at(k))), e => e.op.eq(1)),
  revisionRule.stepsLaw('acknowledgment is idempotent', 2, ({Current,Snapshot},a,[,next]) => forall(k => next.op.eq(2).implies(a.Current.at(k).eq(when(Current.at(k).eq(Snapshot.at(k)),0,Current.at(k))))), e => e.op.eq(2)),
  revisionRule.stepLaw('downloads do not alter other filters', ({key,Current},a) => forall(k => k.eq(key).not().implies(a.Current.at(k).eq(Current.at(k)))), e => e.op.eq(0)),
];

const fields = Array.from({length:5}, (_,i) => `p${i}`);
const initial = Object.fromEntries(fields.map((k,i) => [k,i===0 ? 1 : 0]));
const either = xs => xs.reduce((a,b) => a.or(b));
export const rail = rule('apply phase rail').inputs({phase:upTo(4),complete:bool,op:upTo(3)}).state({...initial, failed:bool.from(false)});
function railStep(e, broken=false) {
  // Status codes match the probe: pending=0, active=1, complete=2, failed=3.
  const keepLater = broken ? e.complete.or(e.complete.not()) : e.complete;
  const raw = fields.map((k,i) => {
    const selected = when(e.phase.eq(i),when(e.complete,2,1),when(keepLater,e[k],0));
    return when(e[k].eq(3),3,when(e.phase.gt(i),2,selected));
  });
  return {...Object.fromEntries(fields.map((k,i) => {
    const laterActive = either(fields.map((_,j) => e.phase.lt(j).and(raw[j].eq(1))));
    const earlierPending = either(fields.map((_,j) => j < i ? e.phase.lt(j).and(raw[j].eq(0)) : e.complete.and(e.complete.not())));
    const promote = e.complete.and(e.phase.lt(i),raw[i].eq(0),laterActive.not(),earlierPending.not());
    const next = when(promote,1,raw[i]);
    return [k,when(e.op.eq(3),initial[k],when(e.op.eq(2),when(e.failed,e[k],when(e[k].eq(3),3,2)),when(e.op.eq(1),when(e[k].eq(1),3,e[k]),next)))];
  })), failed:e.op.eq(3).not().and(e.failed.or(e.op.eq(1)))};
}
export const railRule = rail.step(e => railStep(e));
const activeCount = e => fields.map(k => when(e[k].eq(1),1,0)).reduce((a,b) => a.plus(b));
const railLaws = [
  railRule.law('at most one phase spins', e => activeCount(e).atMost(1)),
  railRule.law('phase statuses stay valid', e => fields.map(k => e[k].atMost(3)).reduce((a,b)=>a.and(b))),
  railRule.law('a failed phase keeps the run failed', e => either(fields.map(k=>e[k].eq(3))).implies(e.failed)),
];
const railSteps = [railRule.stepLaw('failure survives later phase reports', (e,a) => fields.map(k => e[k].eq(3).implies(a[k].eq(3))).reduce((a,b)=>a.and(b)), e => e.op.eq(3).not())];

// ForegroundRunGate. op: 0 begin, 1 end, 2 startRun, 3 finishRun. The shipped
// startRun() checks only app work, not runActive, so a start during a run is
// granted again; the model keeps that. A mutant names one broken transition.
const gate = rule('foreground run gate').inputs({op:upTo(3)})
  .state({work:0,running:bool.from(false),waiting:0,granted:bool.from(false),resumed:0});
function gateStep(e, mutant='') {
  const begin = e.op.eq(0), start = e.op.eq(2), finish = e.op.eq(3);
  const enter = mutant === 'claim' ? begin : e.running.not().and(begin);
  const run = mutant === 'start' ? start : start.and(e.work.eq(0));
  return {
    work: when(enter, e.work.plus(1), when(e.op.eq(1), e.work.minus(1), e.work)),
    running: e.running.and(finish.not()).or(run),
    waiting: when(begin.and(e.running), e.waiting.plus(1), mutant === 'keep' ? e.waiting : when(finish, 0, e.waiting)),
    granted: enter.or(run),
    resumed: when(finish, e.waiting, 0),
  };
}
export const gateRule = gate.step(e => gateStep(e));
const gateLaws = [
  gateRule.law('a running gate holds no app work', ({running,work}) => running.implies(work.eq(0))),
  gateRule.law('queued app work waits for a run', ({waiting,running}) => waiting.atLeast(1).implies(running)),
  gateRule.law('app work never underflows', ({work}) => work.atLeast(0)),
];
const gateSteps = [
  gateRule.stepLaw('a begin outside a run claims one unit', ({work},a) => a.work.eq(work.plus(1)).and(a.granted), e => e.op.eq(0).and(e.running.not())),
  gateRule.stepLaw('a begin during a run holds nothing', ({work,waiting},a) => a.work.eq(work).and(a.waiting.eq(waiting.plus(1)), a.granted.not()), e => e.op.eq(0).and(e.running)),
  gateRule.stepLaw('an end releases one unit, never below zero', ({work},a) => a.work.eq(work.minus(1)), e => e.op.eq(1)),
  gateRule.stepLaw('a run starts only without app work', ({work},a) => a.granted.implies(work.eq(0)), e => e.op.eq(2)),
  gateRule.stepLaw('a start without app work runs', (_,a) => a.running, e => e.op.eq(2).and(e.work.eq(0))),
  gateRule.stepLaw('only a finish resumes app work', ({}, a) => a.resumed.eq(0), e => e.op.eq(3).not()),
  gateRule.stepLaw('a finish hands back the queued waiters and clears the run', ({waiting},a) => a.resumed.eq(waiting).and(a.waiting.eq(0), a.running.not()), e => e.op.eq(3)),
  gateRule.stepsLaw('a second finish resumes nothing', 2, (_,a,[,next]) => next.op.eq(3).implies(a.resumed.eq(0)), e => e.op.eq(3)),
];

// InfoPopoverState. Tokens 1 and 2 are two rows of one list (id 1, token 1 on top); token 3 is another item (id 2);
// id 3 names no item. Event numbers are 1 or 2; 0 means none (the mouse flag says whether an event is present).
const idOf = t => when(t.eq(3), 2, 1), topmost = i => when(i.eq(1), 1, when(i.eq(2), 3, 0));
const infoBase = rule('info popover')
  .inputs({op: oneOf('clicked', 'anchor', 'request', 'dismiss', 'clear'), tok: nat, id: nat, ev: nat, mouse: bool, fromKb: bool})
  .state({pres: 0, cTok: 0, cEv: 0, kTok: 0, pick: 0})
  .assume(({tok, id, ev}) => tok.atLeast(1).and(tok.atMost(3), id.atLeast(1), id.atMost(3), ev.atLeast(1), ev.atMost(2)))
  .flags(({op, tok, id, ev, mouse, fromKb, pres, cTok, cEv, kTok}) => ({
    closingUp: op.is('request').and(mouse, cTok.eq(tok), cEv.eq(ev)),
    closes: op.is('dismiss').and(pres.eq(tok)),
    clickWins: op.is('anchor').and(fromKb.not(), kTok.atLeast(1), idOf(kTok).eq(id)),
  }));
const infoStep = (e, broken = '') => {
  const closingUp = broken === 'reopen' ? e.closingUp.and(e.closingUp.not()) : e.closingUp;
  const mouse = broken === 'unmouse' ? e.mouse.or(e.mouse.not()) : e.mouse;
  return {
    pres: when(e.op.is('request').and(closingUp.not()), e.tok, when(e.op.is('clear').or(e.closes), 0, e.pres)),
    cTok: when(e.op.is('request'), 0, when(e.closes, when(mouse, e.tok, 0), e.cTok)),
    cEv: when(e.op.is('request'), 0, when(e.closes, when(mouse, e.ev, 0), e.cEv)),
    kTok: when(e.op.is('clicked'), e.tok, when(e.op.is('anchor').or(e.op.is('clear')), 0, e.kTok)),
    pick: when(e.clickWins, e.kTok, when(e.op.is('anchor'), topmost(e.id), 0)),
  };
};
export const infoRule = infoBase.step(e => infoStep(e));
const infoInvariants = [infoRule.law('a closing click leaves nothing presented', ({cTok, pres}) => cTok.eq(0).or(pres.eq(0)))];
const infoSteps = [
  infoRule.stepLaw('a closing click cannot reopen its anchor', (_, a) => a.pres.eq(0), ({closingUp}) => closingUp),
  infoRule.stepLaw('any other click reopens its anchor', ({tok}, a) => a.pres.eq(tok), ({op, closingUp}) => op.is('request').and(closingUp.not())),
  infoRule.stepLaw('a late dismissal of another anchor changes nothing', (b, a) => a.pres.eq(b.pres).and(a.cTok.eq(b.cTok), a.cEv.eq(b.cEv), a.kTok.eq(b.kTok)),
    ({op, tok, pres}) => op.is('dismiss').and(tok.eq(pres).not())),
  infoRule.stepsLaw('a non-mouse dismissal never suppresses the next click', 2, (f, l, [d, r]) =>
    d.op.is('dismiss').and(d.mouse.not(), f.pres.eq(d.tok), r.op.is('request'), r.mouse).implies(l.pres.eq(r.tok))),
  infoRule.stepLaw('a selection consumes the click', (_, a) => a.kTok.eq(0), ({op}) => op.is('anchor')),
  infoRule.stepLaw('a click wins its own selection', (b, a) => a.pick.eq(b.kTok), ({clickWins}) => clickWins),
  infoRule.stepLaw('other selections show the topmost anchor', (b, a) => a.pick.eq(topmost(b.id)), ({op, clickWins}) => op.is('anchor').and(clickWins.not())),
  infoRule.stepsLaw('a click is consumed by exactly one selection', 3, (_, l, [c, s, t]) =>
    c.op.is('clicked').and(s.op.is('anchor'), s.fromKb.not(), idOf(c.tok).eq(s.id), t.op.is('anchor'), t.id.eq(s.id)).implies(l.pick.eq(topmost(t.id)))),
];

// Headless rebuild gate (HeadlessLaunch.swift): a 900 s cooldown, doubled per failure up to 21600 s.
// Times are seconds; the clock is positive, and a recorded outcome never moves the stamp backwards.
export const headlessOps = ['consume', 'launched', 'launchFailed', 'rebuildSucceeded', 'rebuildFailed'];
const cooldown = 900, maxBackoff = 21600, maxFailures = 9;
// delay(f) is 900 for f <= 1, else 900 * 2^(f-1) capped at 21600: a finite chain, since failures stay within 0...9.
const delayOf = f => when(f.lt(2), cooldown, when(f.lt(3), 1800, when(f.lt(4), 3600, when(f.lt(5), 7200, when(f.lt(6), 14400, maxBackoff)))));
decision('headlessBackoff', {f: nat, g: nat}, ({f, g}) => ({d: delayOf(f), next: delayOf(g)}), m => [
  m.law('the backoff is at most six hours', () => [], o => o.d.atMost(maxBackoff)),
  m.law('the backoff never shrinks as failures rise', ({f, g}) => [f.atMost(g)], o => o.d.atMost(o.next)),
  m.law('the backoff is at least the base cooldown', () => [], o => o.d.atLeast(cooldown)),
], ({f}) => ({d: when(f.lt(6), 14400, 28800)}));
const headlessBase = rule('headless rebuild gate')
  .inputs({op: oneOf(...headlessOps), now: nat})
  .state({last: 0, failures: 0, outcome: oneOf('none', 'launched', 'launchFailed', 'rebuildSucceeded', 'rebuildFailed').from('none'), granted: bool.from(false), grantedAt: 0})
  .assume(({op, now, last}) => now.atLeast(1).and(op.is('consume').or(now.atLeast(last))));
function headlessStep({op, now, last, failures, outcome, grantedAt}, broken = {}) {
  const bump = min(failures.plus(1), maxFailures);
  const due = broken.noCooldown ? op.is('consume') : last.eq(0).or(now.atLeast(last.plus(delayOf(failures))));
  const grant = op.is('consume').and(due);
  const reserved = when(last.eq(0).or(outcome.is('rebuildSucceeded')), 1, bump);
  const completed = broken.doubleCount ? bump : when(outcome.is('launched'), max(failures, 1), bump);
  return {
    granted: grant,
    last: when(op.is('consume').and(grant.not()), last, now),
    failures: when(op.is('consume'), when(grant, reserved, failures), when(op.is('launched'), reserved, when(op.is('rebuildSucceeded'), 0, completed))),
    outcome: when(op.is('consume'), when(grant, outcome.of('launched'), outcome), when(op.is('launched'), outcome.of('launched'), when(op.is('launchFailed'), outcome.of('launchFailed'), when(op.is('rebuildSucceeded'), outcome.of('rebuildSucceeded'), outcome.of('rebuildFailed'))))),
    grantedAt: when(grant, now, grantedAt),
  };
}
export const headlessGateRule = headlessBase.step(e => headlessStep(e));
const headlessInvariants = [
  headlessGateRule.law('failures stay within the tracked bound', ({failures}) => failures.atMost(maxFailures)),
  headlessGateRule.law('a launched gate has counted a failure', ({outcome, failures}) => outcome.is('launched').implies(failures.atLeast(1))),
  headlessGateRule.law('the grant stamp never passes the last attempt', ({grantedAt, last}) => grantedAt.atMost(last)),
];
const headlessSteps = [
  headlessGateRule.stepLaw('a grant follows the previous grant by one cooldown', ({grantedAt, now}, a) => a.granted.implies(grantedAt.eq(0).or(now.atLeast(grantedAt.plus(cooldown))))),
  headlessGateRule.stepLaw('a clock earlier than the last attempt never grants', ({now, last}, a) => now.lt(last).implies(a.granted.not())),
  headlessGateRule.stepLaw('a grant is recorded as a launch', ({now}, a) => a.granted.implies(a.last.eq(now).and(a.outcome.is('launched')))),
  headlessGateRule.stepLaw('a successful rebuild returns to the base cooldown', (_, a) => a.failures.eq(0), ({op}) => op.is('rebuildSucceeded')),
  headlessGateRule.stepLaw('a failure after a launch is not counted twice', ({failures}, a) => a.failures.eq(failures), ({op, outcome}) => op.is('launchFailed').or(op.is('rebuildFailed')).and(outcome.is('launched'))),
];

export function verifyProofs() {
  for (const [r, invariants, steps] of [[uploadRule,[],uploadLaws],[revisionRule,[],revisionLaws],[railRule,railLaws,railSteps],[gateRule,gateLaws,gateSteps],[infoRule,infoInvariants,infoSteps],[headlessGateRule,headlessInvariants,headlessSteps]]) {
    verdict(proveSteps(r,invariants,steps,{search:false}), invariants.length + steps.length); checked(r.crossCheck(invariants,steps,{rand:draw}));
  }
  for (const [r,invariants,steps] of [
    [upload.step(e=>({...uploadStep(e),pending:when(e.take,0,e.pending)})),[],uploadLaws],
    [revisions.step(e=>revisionStep(e,true)),[],revisionLaws],
    [rail.step(e=>railStep(e,true)),railLaws,[]],
    [gate.step(e=>gateStep(e,'claim')),gateLaws,gateSteps],
    [gate.step(e=>gateStep(e,'start')),gateLaws,gateSteps],
    [gate.step(e=>gateStep(e,'keep')),gateLaws,gateSteps],
  ]) {
    const v=proveSteps(r,invariants,steps,{search:false});
    assert.equal(v.proven,false,'broken transition escaped');
    assert.equal(v.stuck,'sat',JSON.stringify(v));
    assert.ok(v.witness || v.run,'mutation must have counterexample evidence'); mutations++;
  }
  for (const r of [infoBase.step(e => infoStep(e, 'reopen')), infoBase.step(e => infoStep(e, 'unmouse'))]) {
    const v = proveSteps(r, infoInvariants, infoSteps, {search:false});
    assert.equal(v.proven,false,'info broken transition escaped');
    assert.equal(v.stuck,'sat',JSON.stringify(v));
    assert.ok(v.witness || v.run,'info mutation must have counterexample evidence'); mutations++;
  }
  for (const broken of [{doubleCount: true}, {noCooldown: true}]) {
    const v = proveSteps(headlessBase.step(e => headlessStep(e, broken)), headlessInvariants, headlessSteps, {search:false});
    assert.equal(v.proven, false, 'broken gate escaped'); assert.equal(v.stuck, 'sat', JSON.stringify(v));
    assert.ok(v.witness || v.run, 'mutation must have counterexample evidence'); mutations++;
  }
  return {proven,mutations,concrete};
}
