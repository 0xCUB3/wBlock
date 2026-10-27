import assert from 'node:assert/strict';
import { bool, nat, upTo, fun, rule, when, forall, proveDecision, proveSteps, crossCheckDecision } from 'gdp-wired';

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

export function verifyProofs() {
  for (const [r, invariants, steps] of [[uploadRule,[],uploadLaws],[revisionRule,[],revisionLaws],[railRule,railLaws,railSteps]]) {
    verdict(proveSteps(r,invariants,steps,{search:false}), invariants.length + steps.length); checked(r.crossCheck(invariants,steps,{rand:draw}));
  }
  for (const [r,laws] of [
    [upload.step(e=>({...uploadStep(e),pending:when(e.take,0,e.pending)})),uploadLaws],
    [revisions.step(e=>revisionStep(e,true)),revisionLaws],
    [rail.step(e=>railStep(e,true)),railLaws],
  ]) {
    const v=proveSteps(r,laws===railLaws ? laws : [],laws===railLaws ? [] : laws,{search:false});
    assert.equal(v.proven,false,'broken transition escaped');
    assert.equal(v.stuck,'sat',JSON.stringify(v));
    assert.ok(v.witness || v.run,'mutation must have counterexample evidence'); mutations++;
  }
  return {proven,mutations,concrete};
}
