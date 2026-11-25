import assert from 'node:assert/strict';
import { bool, nat, upTo, oneOf, min, max, fun, rule, when, forall, yes, no, proveDecision, proveSteps, crossCheckDecision } from 'gdp-wired';

// These are specifications, not Swift proofs. verify.mjs compares their outputs
// with production Swift; neither a proof failure nor a disagreement may pass CI.
export const decisions = {};
let proven = 0, mutations = 0, concrete = 0, seed = 0x475044;
// High bits: the low bits of a power-of-two LCG cycle with short periods.
const draw = n => (seed = (Math.imul(seed,1664525) + 1013904223) >>> 0, Math.floor(seed / 2 ** 32 * n));
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
// `broken` is one mutant, or one per law in order: mutant i must be refuted by law i.
function decision(name, inputs, outputs, laws, broken) {
  const model = fun(name).inputs(inputs).returns(outputs);
  const claims = laws(model);
  for (const claim of claims) { verdict(proveDecision(claim)); checked(crossCheckDecision(claim, {rand:draw})); }
  [].concat(broken).forEach((breaks, i) => {
    const mutant = fun(name).inputs(inputs).returns(e => ({...outputs(e), ...breaks(e)}));
    const refusal = proveDecision(laws(mutant)[i]);
    assert.equal(refusal.proven, false, `${name} mutation ${i} escaped`);
    assert.equal(refusal.stuck, 'sat', JSON.stringify(refusal));
    mutations++;
  });
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

// CloudSyncCustomFilterReconciler.isImportable: a copy of a built-in list, or a purged list (PurgedFilterLists), is never imported.
decision('customImport', booleans('builtInCurrent','builtInLegacy','purged','variant'),
  ({builtInCurrent, builtInLegacy, purged}) => ({import: builtInCurrent.or(builtInLegacy).or(purged).not()}), m => [
    m.law('a copy of a built-in list is never imported', e => e.builtInLegacy.or(e.builtInCurrent), o => o.import.not()),
    m.law('a purged list is never imported', e => e.purged, o => o.import.not()),
    m.law('other custom lists are imported', e => e.builtInLegacy.or(e.builtInCurrent).or(e.purged).not(), o => o.import),
  ], [
    e => ({import: e.builtInCurrent.not()}),
    e => ({import: e.builtInCurrent.or(e.builtInLegacy).not()}),
  ]);

// Mirrors UserScriptFrameAuthorization.allows: unpaused, not disabled on the site, enabled, on an http(s) URL with a host,
// a noframes script only in the top frame, and matched but not excluded. A page on another host is unmatched
// (otherHost); a hostless or non-http page is refused by webURL whatever the frame.
const frameAllowed = e => e.paused.not().and(e.disabledOnSite.not(), e.enabled, e.webURL, e.noframes.not().or(e.top), e.matched, e.otherHost.not(), e.excluded.not());
decision('frame', booleans('paused','disabledOnSite','enabled','webURL','noframes','top','matched','excluded','otherHost','hostless'),
  e => ({allowed: frameAllowed(e)}), m => [
    m.law('a paused script never runs', ({paused}) => paused, o => o.allowed.not()),
    m.law('a script disabled on its site never runs', ({disabledOnSite}) => disabledOnSite, o => o.allowed.not()),
    m.law('a noframes script never runs in a subframe', ({noframes,top}) => noframes.and(top.not()), o => o.allowed.not()),
    m.law('a non-http(s) or hostless page never runs a script', ({webURL}) => webURL.not(), o => o.allowed.not()),
    m.law('a page on another host never runs a script', ({otherHost}) => otherHost, o => o.allowed.not()),
    m.law('an exclude beats a match', ({matched,excluded}) => matched.and(excluded), o => o.allowed.not()),
    m.law('an enabled, unpaused, matched web page runs the script, except a noframes script in a subframe', frameAllowed, o => o.allowed),
  ], e => ({allowed: e.disabledOnSite.not().and(e.enabled, e.webURL, e.noframes.not().or(e.top), e.matched, e.otherHost.not(), e.excluded.not())}));
// FilterListRemoteMetadataPolicy.applying: a nil or blank header value changes nothing, and a manual flag or a built-in list keeps its name and description.
// The version is not stated here: verify.mjs projects the outputs to the real name, description and version strings.
decision('remoteMetadata', booleans('custom','userName','titlePresent','titleBlank','userDescription','descriptionPresent','descriptionBlank','versionPresent'),
  ({custom,userName,titlePresent,titleBlank,userDescription,descriptionPresent,descriptionBlank,versionPresent}) => ({
    takeTitle: custom.and(userName.not(), titlePresent, titleBlank.not()), takeDescription: custom.and(userDescription.not(), descriptionPresent, descriptionBlank.not()),
    versionUnknown: versionPresent.not(),
  }), m => [
    m.law('a manual name survives remote metadata', ({userName}) => userName, o => o.takeTitle.not()),
    m.law('a manual description survives remote metadata', ({userDescription}) => userDescription, o => o.takeDescription.not()),
    m.law('built-in lists never take header title or description', ({custom}) => custom.not(), o => o.takeTitle.not().and(o.takeDescription.not())),
    m.law('blank header values never replace metadata', () => [], (o,e) => e.titleBlank.implies(o.takeTitle.not()).and(e.descriptionBlank.implies(o.takeDescription.not()))),
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
];
const gateSteps = [
  gateRule.stepLaw('a begin outside a run claims one unit', ({work},a) => a.work.eq(work.plus(1)).and(a.granted), e => e.op.eq(0).and(e.running.not())),
  gateRule.stepLaw('a begin during a run holds nothing', ({work,waiting},a) => a.work.eq(work).and(a.waiting.eq(waiting.plus(1)), a.granted.not()), e => e.op.eq(0).and(e.running)),
  gateRule.stepLaw('an end releases one unit, never below zero', ({work},a) => work.eq(0).implies(a.work.eq(0)).and(work.eq(0).not().implies(a.work.plus(1).eq(work))), e => e.op.eq(1)),
  gateRule.stepLaw('a run starts only without app work', ({work},a) => a.granted.implies(work.eq(0)), e => e.op.eq(2)),
  gateRule.stepLaw('a start without app work runs', (_,a) => a.running, e => e.op.eq(2).and(e.work.eq(0))),
  gateRule.stepLaw('only a finish resumes app work', ({}, a) => a.resumed.eq(0), e => e.op.eq(3).not()),
  gateRule.stepLaw('a finish hands back the queued waiters and clears the run', ({waiting},a) => a.resumed.eq(waiting).and(a.waiting.eq(0), a.running.not()), e => e.op.eq(3)),
  gateRule.stepsLaw('a second finish resumes nothing', 2, (_,a,[,next]) => next.op.eq(3).implies(a.resumed.eq(0)), e => e.op.eq(3)),
];

// InfoPopoverState. Tokens 1 and 2 are two rows of one list (id 1, token 1 on top); token 3 is another item (id 2);
// id 3 names no item. Event numbers are 1 or 2; 0 means none (the mouse flag says whether an event is present).
// v1..v3 say whether each token's anchor is on screen: production selects among the visible anchors only.
const idOf = t => when(t.eq(3), 2, 1), shown = (t, v1, v2, v3) => when(t.eq(1), v1, when(t.eq(2), v2, v3));
const topmost = (i, v1, v2, v3) => when(i.eq(1), when(v1, 1, when(v2, 2, 0)), when(i.eq(2), when(v3, 3, 0), 0));
const topOf = b => topmost(b.id, b.v1, b.v2, b.v3);
const infoBase = rule('info popover')
  .inputs({op: oneOf('clicked', 'anchor', 'request', 'dismiss', 'clear'), tok: nat, id: nat, ev: nat, mouse: bool, fromKb: bool, v1: bool, v2: bool, v3: bool})
  .state({pres: 0, cTok: 0, cEv: 0, kTok: 0, pick: 0})
  .assume(({tok, id, ev}) => tok.atLeast(1).and(tok.atMost(3), id.atLeast(1), id.atMost(3), ev.atLeast(1), ev.atMost(2)))
  .flags(({op, tok, id, ev, mouse, fromKb, v1, v2, v3, pres, cTok, cEv, kTok}) => ({
    closingUp: op.is('request').and(mouse, cTok.eq(tok), cEv.eq(ev)),
    closes: op.is('dismiss').and(pres.eq(tok)),
    clickWins: op.is('anchor').and(fromKb.not(), kTok.atLeast(1), idOf(kTok).eq(id), shown(kTok, v1, v2, v3)),
  }));
const infoStep = (e, broken = '') => {
  const closingUp = broken === 'reopen' ? e.closingUp.and(e.closingUp.not()) : e.closingUp;
  const mouse = broken === 'unmouse' ? e.mouse.or(e.mouse.not()) : e.mouse;
  // The broken click path picks the clicked anchor even when it is off screen.
  const clickWins = broken === 'hidden' ? e.op.is('anchor').and(e.fromKb.not(), e.kTok.atLeast(1), idOf(e.kTok).eq(e.id)) : e.clickWins;
  return {
    pres: when(e.op.is('request').and(closingUp.not()), e.tok, when(e.op.is('clear').or(e.closes), 0, e.pres)),
    cTok: when(e.op.is('request'), 0, when(e.closes, when(mouse, e.tok, 0), e.cTok)),
    cEv: when(e.op.is('request'), 0, when(e.closes, when(mouse, e.ev, 0), e.cEv)),
    kTok: when(e.op.is('clicked'), e.tok, when(e.op.is('anchor').or(e.op.is('clear')), 0, e.kTok)),
    pick: when(clickWins, e.kTok, when(e.op.is('anchor'), topmost(e.id, e.v1, e.v2, e.v3), 0)),
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
  infoRule.stepLaw('other selections show the topmost visible anchor', (b, a) => a.pick.eq(topOf(b)), ({op, clickWins}) => op.is('anchor').and(clickWins.not())),
  infoRule.stepsLaw('a click is consumed by exactly one selection', 3, (_, l, [c, s, t]) =>
    c.op.is('clicked').and(s.op.is('anchor'), s.fromKb.not(), idOf(c.tok).eq(s.id), t.op.is('anchor'), t.id.eq(s.id)).implies(l.pick.eq(topOf(t)))),
];

// Headless rebuild gate (HeadlessLaunch.swift): a 900 s cooldown, doubled per failure up to 21600 s.
// Times are seconds and the clock is positive, but it may move backwards, as shipped: a consume before the last
// stamp is refused, and a recorded outcome stamps the clock it is given, even when that is earlier.
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
  .state({last: 0, failures: 0, outcome: oneOf('none', 'launched', 'launchFailed', 'rebuildSucceeded', 'rebuildFailed').from('none'), granted: bool.from(false)})
  .assume(({now}) => now.atLeast(1));
function headlessStep({op, now, last, failures, outcome}, broken = {}) {
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
  };
}
export const headlessGateRule = headlessBase.step(e => headlessStep(e));
const headlessInvariants = [
  headlessGateRule.law('failures stay within the tracked bound', ({failures}) => failures.atMost(maxFailures)),
  headlessGateRule.law('a launched gate has counted a failure', ({outcome, failures}) => outcome.is('launched').implies(failures.atLeast(1))),
];
const headlessSteps = [
  headlessGateRule.stepLaw('a grant follows the previous recorded attempt by its delay', ({last, now, failures}, a) => a.granted.implies(last.eq(0).or(now.atLeast(last.plus(delayOf(failures)))))),
  headlessGateRule.stepLaw('a clock earlier than the last attempt never grants', ({now, last}, a) => now.lt(last).implies(a.granted.not())),
  headlessGateRule.stepLaw('a refused consume keeps the stamp, including a clock behind it', ({last}, a) => a.last.eq(last),
    ({op, now, last, failures}) => op.is('consume').and(last.eq(0).not(), now.lt(last.plus(delayOf(failures))))),
  headlessGateRule.stepLaw('a recorded outcome stamps the clock it is given, even backwards', ({now}, a) => a.last.eq(now), ({op}) => op.is('consume').not()),
  headlessGateRule.stepLaw('a grant is recorded as a launch', ({now}, a) => a.granted.implies(a.last.eq(now).and(a.outcome.is('launched')))),
  headlessGateRule.stepLaw('a successful rebuild returns to the base cooldown', (_, a) => a.failures.eq(0), ({op}) => op.is('rebuildSucceeded')),
  headlessGateRule.stepLaw('a failure after a launch is not counted twice', ({failures}, a) => a.failures.eq(failures), ({op, outcome}) => op.is('launchFailed').or(op.is('rebuildFailed')).and(outcome.is('launched'))),
];

// The blocking pause store. Stored: the legacy bool, the component mask (absent until written), the request
// bit, the status (idle 0, pending 1, applying 2, succeeded 3, failed 4) and whether an error is stored. `out`
// is the operation's return value; `made` and `consumed` count accepted requests and consumptions (ghosts).
// Ops: 0 set mask, 1 set paused, 2 read (migrates), 3 request, 4 consume, 5 applying, 6 succeeded, 7 failed,
// 8 resumed scope (out: the mask inside), 9 scope whose body throws, 10 scope cancelled (out: 1, the body saw
// the cancellation), 11 an install that wrote only the legacy key. Scope ops 8-10 end with the mask they began with.
export const pause = rule('blocking pause store')
  .inputs({op: upTo(11), fMask: bool, sMask: bool, zMask: bool, paused: bool})
  .state({filters: bool.from(false), scripts: bool.from(false), zapper: bool.from(false), legacy: bool.from(false),
    hasMask: bool.from(false), requested: bool.from(false), err: bool.from(false), status: 0, out: 0, made: 0, consumed: 0})
  .flags(({op, filters, scripts, zapper, legacy, hasMask, status}) => ({
    ef: when(hasMask, filters, legacy), es: when(hasMask, scripts, legacy), ez: when(hasMask, zapper, legacy),
    busy: status.eq(1).or(status.eq(2)), migrates: op.eq(2).or(op.eq(8), op.eq(9), op.eq(10)),
  }));
const effBits = e => when(e.ef, 1, 0).plus(when(e.es, 2, 0)).plus(when(e.ez, 4, 0));
function pauseStep(e) {
  const isSet = e.op.eq(0), isPaused = e.op.eq(1), isLegacy = e.op.eq(11), request = e.op.eq(3), accept = request.and(e.busy.not());
  return {
    filters: when(isSet, e.fMask, when(isPaused, e.paused, when(e.migrates, e.ef, e.filters))),
    scripts: when(isSet, e.sMask, when(isPaused, e.paused, when(e.migrates, e.es, e.scripts))),
    zapper: when(isSet, e.zMask, when(isPaused, e.paused, when(e.migrates, e.ez, e.zapper))),
    legacy: when(isSet, e.fMask.or(e.sMask, e.zMask), when(isPaused.or(isLegacy), e.paused, e.legacy)),
    hasMask: when(isSet.or(isPaused, e.migrates), yes, when(isLegacy, no, e.hasMask)),
    requested: when(accept, yes, when(e.op.eq(4), no, e.requested)),
    err: when(accept.or(e.op.eq(6)), no, when(e.op.eq(7), yes, e.err)),
    status: when(accept, 1, when(e.op.eq(5), 2, when(e.op.eq(6), 3, when(e.op.eq(7), 4, e.status)))),
    out: when(e.op.eq(2), effBits(e), when(request, when(e.busy, e.status, 1), when(e.op.eq(4), when(e.requested, 1, 0),
      when(e.op.eq(8), when(e.es, 2, 0), when(e.op.eq(10), 1, 0))))),
    made: e.made.plus(when(accept, 1, 0)),
    consumed: e.consumed.plus(when(e.op.eq(4).and(e.requested), 1, 0)),
  };
}
export const pauseRule = pause.step(pauseStep);
const pauseLaws = [
  pauseRule.law('a stored mask agrees with the legacy bool', ({hasMask, legacy, filters, scripts, zapper}) => hasMask.implies(legacy.iff(filters.or(scripts, zapper)))),
  pauseRule.law('a failed status keeps its error', ({status, err}) => status.eq(4).implies(err)),
  pauseRule.law('every status is valid', ({status}) => status.atMost(4)),
  pauseRule.law('a pending request is not yet consumed', ({requested, made, consumed}) => requested.implies(consumed.lt(made))),
  pauseRule.law('every request is consumed at most once', ({made, consumed}) => consumed.atMost(made)),
];
const pauseSteps = [
  pauseRule.stepLaw('a set stores exactly the requested components', (b, a) => a.filters.iff(b.fMask).and(a.scripts.iff(b.sMask), a.zapper.iff(b.zMask)), b => b.op.eq(0)),
  pauseRule.stepLaw('after a set, legacy is true exactly when the mask is non-empty', (b, a) => a.legacy.iff(a.filters.or(a.scripts, a.zapper)), b => b.op.eq(0).or(b.op.eq(1))),
  pauseRule.stepLaw('legacy alone migrates to all components', (b, a) => a.filters.and(a.scripts, a.zapper, a.hasMask), b => b.op.eq(2).and(b.hasMask.not(), b.legacy)),
  pauseRule.stepLaw('a request during pending or applying changes neither status nor request', (b, a) => a.status.eq(b.status).and(a.requested.iff(b.requested)), b => b.op.eq(3).and(b.busy)),
  pauseRule.stepLaw('an accepted request is pending and requested', (_, a) => a.status.eq(1).and(a.requested), b => b.op.eq(3).and(b.busy.not())),
  pauseRule.stepLaw('a consume returns the request bit and clears it', (b, a) => a.requested.not().and(a.out.eq(when(b.requested, 1, 0))), b => b.op.eq(4)),
  pauseRule.stepLaw('a resumed scope shows only the scripts paused inside', (b, a) => a.out.eq(when(b.es, 2, 0)), b => b.op.eq(8)),
  pauseRule.stepLaw('a resumed scope ends with the mask it began with', (b, a) => a.filters.iff(b.ef).and(a.scripts.iff(b.es), a.zapper.iff(b.ez)), b => b.op.eq(8).or(b.op.eq(9), b.op.eq(10))),
  pauseRule.stepLaw('a failed resume records its error', (_, a) => a.err, b => b.op.eq(7)),
  pauseRule.stepsLaw('a scope ends with the mask it began with, however it ends, and the next status read shows it', 2,
    (f, l, [r1, r2]) => r1.op.eq(8).or(r1.op.eq(9), r1.op.eq(10)).and(r2.op.eq(2)).implies(l.out.eq(effBits(f)))),
  pauseRule.stepsLaw('two consumes in a row: the second finds no request', 2,
    (_, l, [r1, r2]) => r1.op.eq(4).and(r2.op.eq(4)).implies(l.out.eq(0))),
];

// Filter update popup status (FilterUpdatePopupStatus.swift). Stored state: idle 0, running 1, succeeded 2,
// noChange 3, failed 4. A running claim whose start is more than 300 s old reads as failed, so it is taken by the
// next claim and acknowledged by consumeSnapshot. Claims and times are at least 1 (0 encodes none or nil).
// op: 0 beginIfIdle, 1 requestUpdate, 2 consumeUpdateRequest, 3 finish, 4 snapshot, 5 consumeSnapshot.
// outcome: the finish's run outcome, in the probe's order: 0 applied and 1 staged (succeeded); 2 no filter updates
// and 3 no selected filters (noChange); 4 failed, 5 over limit, 6 deferred, 7 cancelled, 8 skipped (failed).
// ok: the claim, request consume or finish succeeded.
export const popup = rule('filter update popup status')
  .inputs({op: upTo(5), claim: nat, now: nat, outcome: upTo(8)})
  .state({st: upTo(4).from(0), owner: 0, requested: bool.from(false), startedAt: 0, finishedAt: 0, ok: bool.from(false)})
  .assume(({claim, now}) => claim.atLeast(1).and(now.atLeast(1)));
// `broken` names one deliberate fault the proofs must refuse; '' is the shipped transition.
function popupStep({op, claim, now, outcome, st, owner, requested, startedAt, finishedAt}, broken = '') {
  const stale = st.eq(1).and(broken === 'boundary' ? startedAt.plus(300).atMost(now) : startedAt.plus(300).lt(now));
  const live = st.eq(1).and(stale.not()), open = broken === 'claim' ? yes : live.not();
  const terminal = stale.or(st.atLeast(2));
  const claimed = op.eq(0).or(op.eq(1)).and(open), asked = op.eq(1).and(open);
  const finished = op.eq(3).and(st.eq(1), broken === 'owner' ? yes : owner.eq(claim));
  const taken = op.eq(2).and(requested, st.eq(1), owner.atLeast(1));
  const acked = (broken === 'read' ? op.eq(4).or(op.eq(5)) : op.eq(5)).and(broken === 'ack' ? st.atLeast(1) : terminal);
  const done = when(outcome.lt(2), 2, when(outcome.lt(4), broken === 'outcome' ? 2 : 3, 4));
  return {
    ok: claimed.or(taken, finished),
    st: when(claimed, 1, when(finished, done, when(acked, 0, st))),
    owner: when(claimed, claim, when(acked, 0, owner)),
    requested: when(claimed, asked.or(broken === 'request' ? requested : no), when(finished.or(taken, acked), no, requested)),
    startedAt: when(claimed, now, when(acked, 0, startedAt)),
    finishedAt: when(claimed, 0, when(finished, now, when(acked, 0, finishedAt))),
  };
}
export const popupRule = popup.step(e => popupStep(e));
const frozen = (s, a) => a.st.eq(s.st).and(a.owner.eq(s.owner), a.requested.iff(s.requested), a.startedAt.eq(s.startedAt), a.finishedAt.eq(s.finishedAt));
// Not running: idle, finished, or a running claim more than 300 s old. The spec's formula, not the rule's flags.
const notLive = ({st, startedAt, now}) => st.eq(1).implies(startedAt.plus(300).lt(now));
const popupInvariants = [
  popupRule.law('a running claim has an owner', ({st, owner}) => st.eq(1).implies(owner.atLeast(1))),
  popupRule.law('an idle store has no owner', ({st, owner}) => st.eq(0).implies(owner.eq(0))),
  popupRule.law('a pending request belongs to a running claim', ({st, requested}) => requested.implies(st.eq(1))),
];
const popupSteps = [
  popupRule.stepLaw('a live claim is refused and changes nothing', (s, a) => frozen(s, a).and(a.ok.not()), s => s.op.eq(0).or(s.op.eq(1)).and(notLive(s).not())),
  popupRule.stepLaw('a claim takes an idle, finished or expired store', (s, a) => a.st.eq(1).and(a.owner.eq(s.claim), a.startedAt.eq(s.now), a.finishedAt.eq(0), a.ok),
    s => s.op.eq(0).or(s.op.eq(1)).and(notLive(s))),
  popupRule.stepLaw('a direct claim clears the request bit', (_, a) => a.requested.not().and(a.ok), s => s.op.eq(0).and(notLive(s))),
  popupRule.stepLaw('a request claim sets the request bit', (_, a) => a.requested.and(a.ok), s => s.op.eq(1).and(notLive(s))),
  popupRule.stepLaw('a finish by a non-owner changes nothing', (s, a) => frozen(s, a).and(a.ok.not()), s => s.op.eq(3).and(s.owner.eq(s.claim).not())),
  popupRule.stepLaw('a finish records its outcome', (s, a) => a.st.eq(when(s.outcome.lt(2), 2, when(s.outcome.lt(4), 3, 4))).and(a.ok),
    s => s.op.eq(3).and(s.owner.eq(s.claim), s.st.eq(1))),
  popupRule.stepLaw('taking a request clears only its bit', (s, a) => a.requested.not().and(a.st.eq(s.st), a.owner.eq(s.owner), a.startedAt.eq(s.startedAt), a.finishedAt.eq(s.finishedAt), a.ok),
    s => s.op.eq(2).and(s.requested, s.st.eq(1), s.owner.atLeast(1))),
  popupRule.stepLaw('a snapshot changes nothing', frozen, s => s.op.eq(4)),
  popupRule.stepLaw('acknowledging an idle store changes nothing', frozen, s => s.op.eq(5).and(s.st.eq(0))),
  popupRule.stepLaw('acknowledging a running claim changes nothing', frozen, s => s.op.eq(5).and(notLive(s).not())),
  popupRule.stepLaw('acknowledging a finished or expired claim clears the store', (_, a) => a.st.eq(0).and(a.owner.eq(0), a.requested.not(), a.startedAt.eq(0), a.finishedAt.eq(0)),
    s => s.op.eq(5).and(s.st.ne(0), notLive(s))),
];

// SwipeBackGestureState (wBlock/SwipeBackNavigation.swift): interactive macOS back-swipe state machine.
// Progress and amount are encoded in permille (0..1000): 300 = 0.30, 500 = 0.50, 995 = 0.995, 1000 = 1.00.
// Axis classifies a scroll event after accumulation: 'short' (< 8 pt), 'back' (>= 8 pt right-dominant), 'other' (vertical or left).
export const swipeOps = ['scroll', 'track', 'finishCommit', 'abort'];
export const swipePhases = ['none', 'mayBegin', 'began', 'changed', 'ended', 'cancelled'];
const swipeModes = ['idle', 'pending', 'tracking', 'committing'];
const swipeActions = ['none', 'start', 'update', 'cancel', 'commit'];
const swipeBase = rule('swipe back gesture')
  .inputs({
    op: oneOf(...swipeOps),
    phase: oneOf(...swipePhases),
    hasMomentum: bool,
    swipeEnabled: bool,
    reduceMotionIn: bool,
    axis: oneOf('short', 'back', 'other'),
    amount: nat,
    isComplete: bool,
  })
  .state({
    mode: oneOf(...swipeModes).from('idle'),
    didRelease: bool.from(false),
    reduceMotion: bool.from(false),
    progress: 0,
    action: oneOf(...swipeActions).from('none'),
    stopped: bool.from(false),
  })
  .assume(({ amount }) => amount.atMost(1000));

function swipeStep(e, broken = '') {
  const active = e.mode.is('tracking').or(e.mode.is('committing'));
  const canScroll = broken === 'momentum'
    ? e.op.is('scroll').and(active.not())
    : e.op.is('scroll').and(active.not(), e.hasMomentum.not());
  const evalScroll = canScroll.and(e.phase.is('began').or(e.phase.is('changed').and(e.mode.is('pending'))));
  const starts = evalScroll.and(e.axis.is('back'), e.swipeEnabled);
  const goesPending = canScroll.and(e.phase.is('mayBegin').or(evalScroll.and(e.axis.is('short'))));

  const isTracking = e.op.is('track').and(e.mode.is('tracking'));
  const rel = e.didRelease.or(e.phase.is('ended')).or(e.phase.is('cancelled'));
  const rm = e.reduceMotion;

  const rmCompleteCommit = isTracking.and(rm, e.isComplete, e.amount.atLeast(500));
  const rmCompleteCancel = isTracking.and(rm, e.isComplete, e.amount.lt(500));
  const rmEndCommit = broken === 'waitForComplete'
    ? no
    : isTracking.and(rm, e.isComplete.not(), e.phase.is('ended'), e.amount.atLeast(300));
  const rmEndCancel = broken === 'waitForComplete'
    ? no
    : isTracking.and(rm, e.isComplete.not(), e.phase.is('ended'), e.amount.lt(300));
  const rmCancel = isTracking.and(rm, e.isComplete.not(), e.phase.is('cancelled'));

  const normCompleteCommit = isTracking.and(rm.not(), e.isComplete, e.amount.atLeast(500));
  const normCompleteCancel = isTracking.and(rm.not(), e.isComplete, e.amount.lt(500));
  const normTailCommit = broken === 'commitWhileHolding'
    ? isTracking.and(rm.not(), e.isComplete.not(), e.amount.atLeast(995))
    : broken === 'waitForComplete'
      ? no
      : isTracking.and(rm.not(), e.isComplete.not(), rel, e.amount.atLeast(995));

  const commits = rmCompleteCommit.or(rmEndCommit, normCompleteCommit, normTailCommit);
  const cancels = rmCompleteCancel.or(rmEndCancel, rmCancel, normCompleteCancel);
  const updates = isTracking.and(commits.not(), cancels.not());
  const stopped = rmEndCommit.or(rmEndCancel, rmCancel, normTailCommit, e.op.is('track').and(e.mode.is('tracking').not()));

  const commitMode = broken === 'doubleCommit' ? e.mode.of('tracking') : e.mode.of('committing');
  const nextMode = when(
    e.op.is('abort'), e.mode.of('idle'),
    when(
      e.op.is('finishCommit'), when(e.mode.is('committing'), e.mode.of('idle'), e.mode),
      when(
        starts, e.mode.of('tracking'),
        when(
          goesPending, e.mode.of('pending'),
          when(
            canScroll, e.mode.of('idle'),
            when(
              commits, commitMode,
              when(cancels, e.mode.of('idle'), e.mode),
            ),
          ),
        ),
      ),
    ),
  );

  return {
    mode: nextMode,
    didRelease: when(starts, no, when(updates, rel, when(nextMode.is('tracking'), e.didRelease, no))),
    reduceMotion: when(starts, e.reduceMotionIn, when(nextMode.is('tracking'), e.reduceMotion, no)),
    progress: when(
      starts, 0,
      when(
        updates, broken === 'waitForComplete' ? 0 : when(rm, 0, e.amount),
        when(nextMode.is('tracking'), e.progress, 0),
      ),
    ),
    action: when(
      starts, e.action.of('start'),
      when(commits, e.action.of('commit'), when(cancels, e.action.of('cancel'), when(updates, e.action.of('update'), e.action.of('none')))),
    ),
    stopped,
  };
}

export const swipeRule = swipeBase.step(e => swipeStep(e));
const swipeInvariants = [
  swipeRule.law('progress stays within 0..1000', ({ progress }) => progress.atMost(1000)),
  swipeRule.law('didRelease is only true while tracking', ({ mode, didRelease }) => didRelease.implies(mode.is('tracking'))),
  swipeRule.law('reduceMotion is only true while tracking', ({ mode, reduceMotion }) => reduceMotion.implies(mode.is('tracking'))),
];
const swipeSteps = [
  swipeRule.stepLaw('momentum scroll never starts tracking', (_, a) => a.action.is('start').not(),
    e => e.op.is('scroll').and(e.hasMomentum)),
  swipeRule.stepLaw('vertical or leftward scroll never starts tracking', (_, a) => a.action.is('start').not().and(a.mode.is('tracking').not()),
    e => e.op.is('scroll').and(e.mode.is('tracking').not(), e.axis.is('other'))),
  swipeRule.stepLaw('horizontal back scroll past threshold starts tracking immediately', (_, a) => a.action.is('start').and(a.mode.is('tracking')),
    e => e.op.is('scroll').and(e.mode.is('idle'), e.hasMomentum.not(), e.swipeEnabled, e.phase.is('began'), e.axis.is('back'))),
  swipeRule.stepLaw('holding a finger down never commits or cancels', (_, a) => a.action.is('update').and(a.mode.is('tracking'), a.stopped.not()),
    e => e.op.is('track').and(e.mode.is('tracking'), e.didRelease.not(), e.isComplete.not(), e.phase.is('changed'))),
  swipeRule.stepLaw('normal motion tracks live finger progress immediately', (b, a) => a.progress.eq(b.amount),
    e => e.op.is('track').and(e.mode.is('tracking'), e.reduceMotion.not(), e.didRelease.not(), e.isComplete.not(), e.phase.is('changed'))),
  swipeRule.stepLaw('post-release tail past 99.5% snaps and commits immediately', (_, a) => a.action.is('commit').and(a.stopped, a.mode.is('committing')),
    e => e.op.is('track').and(e.mode.is('tracking'), e.reduceMotion.not(), e.isComplete.not(), e.didRelease, e.amount.atLeast(995))),
  swipeRule.stepLaw('reduce motion commits on release past 30% without waiting for settle', (_, a) => a.action.is('commit').and(a.stopped, a.mode.is('committing')),
    e => e.op.is('track').and(e.mode.is('tracking'), e.reduceMotion, e.isComplete.not(), e.phase.is('ended'), e.amount.atLeast(300))),
  swipeRule.stepLaw('while committing, stray track callbacks are ignored and stopped', (_, a) => a.action.is('none').and(a.stopped, a.mode.is('committing')),
    e => e.op.is('track').and(e.mode.is('committing'))),
  swipeRule.stepLaw('abort always returns cleanly to idle without committing', (_, a) => a.mode.is('idle').and(a.action.is('none')),
    e => e.op.is('abort')),
];

export function verifyProofs() {
  for (const [r, invariants, steps] of [[uploadRule,[],uploadLaws],[revisionRule,[],revisionLaws],[railRule,railLaws,railSteps],[gateRule,gateLaws,gateSteps],[infoRule,infoInvariants,infoSteps],[headlessGateRule,headlessInvariants,headlessSteps],[pauseRule,pauseLaws,pauseSteps],[popupRule,popupInvariants,popupSteps],[swipeRule,swipeInvariants,swipeSteps]]) {
    verdict(proveSteps(r,invariants,steps,{search:false}), invariants.length + steps.length); checked(r.crossCheck(invariants,steps,{rand:draw}));
  }
  for (const [r,invariants,steps] of [
    [upload.step(e=>({...uploadStep(e),pending:when(e.take,0,e.pending)})),[],uploadLaws],
    [revisions.step(e=>revisionStep(e,true)),[],revisionLaws],
    [rail.step(e=>railStep(e,true)),railLaws,[]],
    [gate.step(e=>gateStep(e,'claim')),gateLaws,gateSteps],
    [gate.step(e=>gateStep(e,'start')),gateLaws,gateSteps],
    [gate.step(e=>gateStep(e,'keep')),gateLaws,gateSteps],
    // A throwing resume leaves the filters paused.
    [pause.step(e=>({...pauseStep(e),filters:when(e.op.eq(9),no,pauseStep(e).filters)})),pauseLaws,pauseSteps],
    // A request during apply restarts the status.
    [pause.step(e=>({...pauseStep(e),status:when(e.op.eq(3),1,pauseStep(e).status)})),pauseLaws,pauseSteps],
    // A consume keeps the request bit.
    [pause.step(e=>({...pauseStep(e),requested:when(e.op.eq(4),e.requested,pauseStep(e).requested)})),pauseLaws,pauseSteps],
    // A mask write leaves legacy stale.
    [pause.step(e=>({...pauseStep(e),legacy:when(e.op.eq(0),e.legacy,pauseStep(e).legacy)})),pauseLaws,pauseSteps],
  ]) {
    const v=proveSteps(r,invariants,steps,{search:false});
    assert.equal(v.proven,false,'broken transition escaped');
    assert.equal(v.stuck,'sat',JSON.stringify(v));
    assert.ok(v.witness || v.run,'mutation must have counterexample evidence'); mutations++;
  }
  for (const r of [infoBase.step(e => infoStep(e, 'reopen')), infoBase.step(e => infoStep(e, 'unmouse')), infoBase.step(e => infoStep(e, 'hidden'))]) {
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
  for (const b of ['claim','boundary','owner','read','ack','outcome','request']) {
    const v=proveSteps(popup.step(e=>popupStep(e,b)),popupInvariants,popupSteps,{search:false});
    assert.equal(v.proven,false,`popup ${b} mutation escaped`);
    assert.equal(v.stuck,'sat',JSON.stringify(v));
    assert.ok(v.witness || v.run,'mutation must have counterexample evidence'); mutations++;
  }
  for (const b of ['waitForComplete','commitWhileHolding','momentum','doubleCommit']) {
    const v = proveSteps(swipeBase.step(e => swipeStep(e, b)), swipeInvariants, swipeSteps, { search: false });
    assert.equal(v.proven, false, `swipe ${b} mutation escaped`);
    assert.equal(v.stuck, 'sat', JSON.stringify(v));
    assert.ok(v.witness || v.run, 'swipe mutation must have counterexample evidence'); mutations++;
  }
  return {proven,mutations,concrete};
}
