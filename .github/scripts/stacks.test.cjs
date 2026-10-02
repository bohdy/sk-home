'use strict';
// Fixtures exercise decisions and API failure modes without infrastructure access.
const {test} = require('node:test'), assert = require('node:assert/strict');
const fs = require('node:fs'), os = require('node:os'), path = require('node:path'), cp = require('node:child_process');
const s = require('./stacks.cjs'), select = require('./select-stacks.cjs');
const c = s.catalog(), stack = c.stacks[0], sha = 'a'.repeat(40), head = 'b'.repeat(40);
const timestamp = '2026-10-01T12:00:00Z', newerTimestamp = '2026-10-02T12:00:00Z';
// API fixtures carry documented timestamps rather than implying array order.
function status(overrides = {}) { return {created_at:timestamp,state:'success',creator:{login:'github-actions[bot]'},...overrides}; }
const ids = paths => s.selected(c,paths).map(x=>x.id);
function deployment(overrides = {}) { return {id:1,created_at:timestamp,sha,task:'infra:reconcile',environment:stack.checkpoint_environment,creator:{login:'github-actions[bot]'},payload:{schema:1,stack:stack.id,root:stack.root,sha,workflow:'.github/workflows/terraform.yaml',run_id:23,status:'empty'},...overrides}; }
function sdk(records = [deployment()], statuses = [status()], run = {}) {
  const calls = [];
  return {calls,rest:{repos:{listDeployments:async args=>{calls.push(args);return {data:records};},listDeploymentStatuses:async()=>({data:statuses}),createDeployment:async args=>{calls.push(args);return {data:{id:1}};},createDeploymentStatus:async args=>{calls.push(args);return {data:{}};}},actions:{getWorkflowRun:async()=>({data:{head_sha:sha,head_branch:'main',path:'.github/workflows/terraform.yaml',event:'push',repository:{full_name:'owner/repo'},...run}})}}};
}
const repo = {owner:'owner',repo:'repo'};
test('documents and generic workflow edits do not plan infrastructure',()=> {
  assert.deepEqual(ids(['README.md','terraform/network/gw/interfaces/README.md','.github/workflows/terraform.yaml','.github/scripts/stacks.cjs']),[]);
  assert.deepEqual(ids(['terraform/k3s/talos-cluster/main.tf']),['talos']);
  assert.deepEqual(ids(['terraform/k3s/talos-cluster/image/schematic.yaml']),['talos']);
  assert.deepEqual(ids(['terraform/network/gw/interfaces/.terraform.lock.hcl']),['gateway']);
  assert.deepEqual(ids(['terraform/network/gw/interfaces/main.tf','terraform/cloudflare/tunnel/variables.tf']),['gateway','cloudflare']);
  assert.equal(ids(['mise.toml']).length,5);
});
test('PR helper changes validate all six; certificates remain PR-only',()=> {
  assert.equal(s.selected(c,['.github/scripts/stacks.cjs'],true).length,6);
  assert.deepEqual(ids(['terraform/network/gw/certificates/main.tf']),[]);
  assert.deepEqual(s.selected(c,['.github/workflows/mikrotik-certificates.yaml'],true).map(x=>x.id),['certificates']);
});
test('rename/delete paths and explicit shared consumers select both owners',()=> {
  assert.deepEqual(ids(['terraform/network/gw/interfaces/old.tf','terraform/network/gw/dhcp/new.tf']),['gateway','dhcp']);
  const copy = structuredClone(c); copy.stacks[0].shared_inputs = ['inventory/nodes.json']; copy.stacks[2].shared_inputs = ['inventory/nodes.json'];
  assert.deepEqual(s.selected(copy,['inventory/nodes.json']).map(x=>x.id),['gateway','talos']);
});
test('catalog rejects duplicate roots, IDs, keys and invalid identities',()=> {
  for (const key of ['id','root','state_key']) { const value=structuredClone(c); value.stacks[1][key]=value.stacks[0][key]; assert.throws(()=>s.catalog(value)); }
  const value=structuredClone(c); value.stacks[0].root='../escape'; assert.throws(()=>s.catalog(value));
});
test('checkpoint trusts exact schema, SDK workflow provenance and successful status',async()=> {
  assert.equal(await s.checkpoint(sdk(),repo,stack,head,()=>true),sha);
  for (const overrides of [{task:'deploy'},{environment:'production'},{creator:{login:'operator'}},{payload:{schema:99}},{sha:'invalid'}]) assert.equal(await s.checkpoint(sdk([deployment(overrides)]),repo,stack,head,()=>true),null);
  for (const overrides of [{head_sha:head},{head_branch:'feature'},{path:'.github/workflows/other.yaml'},{event:'pull_request'},{repository:{full_name:'fork/repo'}}]) assert.equal(await s.checkpoint(sdk(undefined,undefined,overrides),repo,stack,head,()=>true),null);
});
test('pending/failed newer records do not hide previous success',async()=> {
  const github=sdk([deployment({id:2,created_at:newerTimestamp}),deployment()]);
  github.rest.repos.listDeploymentStatuses=async args=>({data:args.deployment_id===2?[status({state:'failure'})]:[status()]});
  assert.equal(await s.checkpoint(github,repo,stack,head,()=>true),sha);
  for (const state of ['pending','failure','error','inactive']) assert.equal(await s.checkpoint(sdk(undefined,[status({state})]),repo,stack,head,()=>true),null);
  for (const conclusion of ['failure','cancelled']) assert.equal(await s.checkpoint(sdk(undefined,undefined,{conclusion}),repo,stack,head,()=>true),sha);
});
test('successful checkpoint with unverifiable ancestry fails closed',async()=> {
  await assert.rejects(s.checkpoint(sdk(),repo,stack,head,()=>false),/ancestry/);
});
test('pagination reaches old successful checkpoints and sanitizes request failures',async()=> {
  let pages=[];
  const g=sdk();
  g.rest.repos.listDeployments=async args=> {pages.push(args.page);return {data:args.page===1?Array.from({length:100},()=>deployment({task:'other'})):[deployment()]};};
  assert.equal(await s.checkpoint(g,repo,stack,head,()=>true),sha); assert.deepEqual(pages,[1,2]);
  g.rest.repos.listDeployments=async()=>{throw Error('token=secret raw response');};
  await assert.rejects(s.checkpoint(g,repo,stack,head,()=>true),e=>e.message==='Checkpoint API request failed');
});
// Different SHA fixtures retain matching payload and workflow provenance.
function checkpointSdk(records, statusesById = {}) {
  const g = sdk(records);
  g.rest.repos.listDeploymentStatuses = async args => ({data:statusesById[args.deployment_id] || [status()]});
  g.rest.actions.getWorkflowRun = async args => ({data:{
    head_sha:records.find(record => record.payload?.run_id === args.run_id).sha,
    head_branch:'main',path:'.github/workflows/terraform.yaml',event:'push',repository:{full_name:'owner/repo'},
  }});
  return g;
}
function laterDeployment(overrides = {}) {
  return deployment({id:2,sha:head,created_at:newerTimestamp,
    payload:{...deployment().payload,sha:head,run_id:24},...overrides});
}
test('checkpoint and latest status selection ignore reversed and shuffled response order', async () => {
  const records = [deployment(),laterDeployment(),deployment({id:3,created_at:'2026-09-30T12:00:00Z'})];
  for (const order of [records,[...records].reverse(),[records[1],records[2],records[0]]]) {
    const statuses = [status({state:'failure'}),status({created_at:newerTimestamp})];
    for (const statusOrder of [statuses,[...statuses].reverse()]) {
      assert.equal(await s.checkpoint(checkpointSdk(order,{2:statusOrder}),repo,stack,head,()=>true),head);
    }
  }
  // A later failed status prevents reuse of an earlier success on that deployment.
  const g = checkpointSdk(records,{2:[status(),status({created_at:newerTimestamp,state:'failure'})]});
  assert.equal(await s.checkpoint(g,repo,stack,head,()=>true),sha);
});
test('pagination order does not determine newest deployment or latest status', async () => {
  const records = [deployment(),laterDeployment()];
  const g = checkpointSdk(records);
  g.rest.repos.listDeployments = async args => ({data:args.page === 1 ?
    Array.from({length:100},() => deployment()) : [laterDeployment()]});
  g.rest.repos.listDeploymentStatuses = async args => ({data:args.page === 1 ?
    Array.from({length:100},() => status({state:'failure'})) : [status({created_at:newerTimestamp})]});
  assert.equal(await s.checkpoint(g,repo,stack,head,()=>true),head);
});
test('invalid or missing trusted timestamps fail closed with sanitized errors', async () => {
  for (const created_at of [undefined,'private-response','2026-02-30T12:00:00Z','2026-10-01T12:00:00+00:00','2026-10-01T12:00:00.000Z']) {
    await assert.rejects(s.checkpoint(sdk([deployment({created_at})]),repo,stack,head,()=>true),
      error => error.message === 'Invalid checkpoint timestamp');
    await assert.rejects(s.checkpoint(sdk(undefined,[status({created_at})]),repo,stack,head,()=>true),
      error => error.message === 'Invalid checkpoint timestamp');
  }
  assert.equal(await s.checkpoint(sdk([deployment({task:'other',created_at:'private-response'}),deployment()]),repo,stack,head,()=>true),sha);
});
test('latest status ties accept equivalence and reject conflicting states or creators', async () => {
  assert.equal(await s.checkpoint(sdk(undefined,[status(),status()]),repo,stack,head,()=>true),sha);
  for (const other of [status({state:'failure'}),status({creator:{login:'operator'}})]) {
    for (const statuses of [[status(),other],[other,status()]]) {
      await assert.rejects(s.checkpoint(sdk(undefined,statuses),repo,stack,head,()=>true),
        error => error.message === 'Ambiguous latest checkpoint status');
    }
  }
});
test('deployment timestamp ties preserve success but reject different successful SHAs', async () => {
  const tied = laterDeployment({created_at:timestamp});
  for (const records of [[deployment(),tied],[tied,deployment()]]) {
    await assert.rejects(s.checkpoint(checkpointSdk(records),repo,stack,head,()=>true),
      error => error.message === 'Ambiguous successful checkpoint timestamp');
    assert.equal(await s.checkpoint(checkpointSdk(records,{2:[status({state:'pending'})]}),repo,stack,head,()=>true),sha);
    await assert.rejects(s.checkpoint(checkpointSdk(records),repo,stack,head,value=>value!==head),/ancestry/);
  }
  assert.equal(await s.checkpoint(checkpointSdk([deployment(),deployment({id:3})]),repo,stack,head,()=>true),sha);
});
test('publishing is nonproduction exact-SHA metadata with explicit success',async()=> {
  const g=sdk();
  await s.publish(g,repo,stack,sha,23,'empty');
  assert.equal(g.calls[0].ref,sha);
  assert.equal(g.calls[0].auto_merge,false);
  assert.deepEqual(g.calls[0].required_contexts,[]);
  assert.equal(g.calls[0].production_environment,false);
  assert.equal(g.calls[1].state,'success');
  assert.deepEqual(Object.keys(g.calls[0].payload).sort(),['root','run_id','schema','sha','stack','status','workflow']);
  await assert.rejects(s.publish(g,repo,stack,sha,23,'changes'));
});
test('sanitized plan result has no arbitrary values',()=> {
  assert.equal(s.result(stack,sha,0).status,'empty'); assert.equal(s.result(stack,sha,1).status,'error');
  assert.equal(s.result(stack,sha,2,'c'.repeat(64)).status,'changes');
  assert.throws(()=>s.result(stack,sha,2,'')); assert.throws(()=>s.result(stack,sha,7));
  assert.deepEqual(Object.keys(s.result(stack,sha,0)).sort(),['digest','id','root','sha','status']);
});
function core() {
  const outputs = {};
  return {
    outputs,
    setOutput: (key, value) => { outputs[key] = value; },
    summary: {
      addHeading() { return this; },
      addRaw() { return this; },
      write: async () => {},
    },
  };
}
test('missing checkpoints use cumulative rollout anchor; manual bootstrap names only one root',async()=> {
  const diff=s.diff; s.diff=()=>['terraform/k3s/talos-cluster/main.tf'];
  try {
    const k=core();
  await select({github:sdk([]),core:k,context:{sha:head,ref:'refs/heads/main',repo,eventName:'push',payload:{before:sha}}});
    assert.deepEqual(JSON.parse(k.outputs.stacks),['k3s/talos-cluster']);
  assert.equal(JSON.parse(k.outputs.uninitialized).length,5);
    const m=core();
  await select({github:sdk([]),core:m,context:{sha:head,ref:'refs/heads/main',repo,eventName:'workflow_dispatch',payload:{inputs:{reconcile_stack:'talos'}}}});
  assert.deepEqual(JSON.parse(m.outputs.stacks),['k3s/talos-cluster']);
    const n=core();
  await select({github:sdk([]),core:n,context:{sha:head,ref:'refs/heads/main',repo,eventName:'workflow_dispatch',payload:{inputs:{}}}});
  assert.deepEqual(JSON.parse(n.outputs.stacks),['k3s/talos-cluster']);
  } finally {s.diff=diff;}
});
test('manual modes exclude ordinary planning except the requested full stack',async()=> {
  for (const [mode,expected] of [['apply_gateway',['network/gw/interfaces']],['apply_cloudflare',['cloudflare/tunnel']],['apply_gateway_bgp',[]],['plan_proxmox_storage',[]],['apply_gateway_dhcp',[]]]) {
    const k=core();
  await select({github:{},core:k,context:{sha:head,ref:'refs/heads/main',repo,eventName:'workflow_dispatch',payload:{inputs:{[mode]:'true'}}}});
  assert.deepEqual(JSON.parse(k.outputs.stacks),expected);
  }
  for (const inputs of [{apply_gateway:'maybe'},{unknown:'true'},{apply_gateway_unknown:'true'},{apply_gateway:'true',reconcile_stack:'talos'},{reconcile_stack:'unknown'}]) await assert.rejects(select({github:{},core:core(),context:{sha:head,ref:'refs/heads/main',repo,eventName:'workflow_dispatch',payload:{inputs}}}));
});
test('PR compares merge-base and never queries deployments',async()=> {
  const diff=s.diff, git=s.git;
  let compared;
  s.git=args=>args[0]==='merge-base'?sha:args[0]==='ls-tree'?'.github/opentofu-stacks.json':JSON.stringify(c);
  s.diff=(base,h)=>{compared=[base,h];return ['terraform/network/gw/dhcp/main.tf'];};
  try {const k=core();
  await select({github:{},core:k,context:{eventName:'pull_request',payload:{pull_request:{base:{sha:head},head:{sha:'c'.repeat(40)}}}}});
  assert.deepEqual(compared,[sha,'c'.repeat(40)]);
  assert.deepEqual(JSON.parse(k.outputs.stacks),['network/gw/dhcp']);}finally{s.diff=diff;s.git=git;}
});
test('actual plan runner handles exit 0, 1, 2 and deletes only no-op binaries',()=> {
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),'stack-plan-test-'));
  fs.mkdirSync(path.join(dir,'terraform/root'),{recursive:true});
  fs.writeFileSync(path.join(dir,'tofu'),'#!/bin/sh\nexit "$FIXTURE_EXIT"\n',{mode:0o700});
  try {for(const exit of [0,1,2]) {
    fs.writeFileSync(path.join(dir,'terraform/root/tofuplan'),'fixture');
    const out=path.join(dir,`out${exit}`),run=cp.spawnSync('bash',[path.resolve('.github/scripts/plan.sh')],{cwd:dir,env:{...process.env,PATH:`${dir}:${process.env.PATH}`,FIXTURE_EXIT:String(exit),STACK_PATH:'root',GITHUB_OUTPUT:out}});
    assert.equal(run.status,exit===1?1:0);
  assert.equal(fs.readFileSync(out,'utf8'),`exitcode=${exit}\n`);
  assert.equal(fs.existsSync(path.join(dir,'terraform/root/tofuplan')),exit!==0);
  }}finally{fs.rmSync(dir,{recursive:true,force:true});}
});

test('precheckpoint failed/cancelled input remains selected after a later docs-only push',async()=> {
  const diff=s.diff;
  let bases=[];s.diff=(base)=>{bases.push(base);return ['terraform/network/gw/dhcp/main.tf','README.md'];};
  try {for(const before of [sha,'c'.repeat(40)]) {const k=core();
  await select({github:sdk([]),core:k,context:{sha:head,ref:'refs/heads/main',repo,eventName:'push',payload:{before}}});
  assert.deepEqual(JSON.parse(k.outputs.stacks),['network/gw/dhcp']);}assert.ok(bases.every(base=>base===c.bootstrap_comparison_sha));}finally{s.diff=diff;}
});

test('complete workflow defaults and both ether7 dispatches preserve dedicated lifecycles', async () => {
  const names = s.dispatchInputs(fs.readFileSync('.github/workflows/terraform.yaml', 'utf8'));
  assert.equal(names.length, Object.keys(c.dispatch_modes).length + 1);
  assert.ok(names.includes('apply_gateway_ether7'));
  assert.ok(names.includes('plan_gateway_ether7'));
  const defaults = Object.fromEntries(names.map(name =>
    [name, name === 'reconcile_stack' ? 'none' : 'false']
  ));
  const originalDiff = s.diff;
  s.diff = () => [];
  try {
  for (const enabled of [null, 'apply_gateway_ether7', 'plan_gateway_ether7']) {
    const inputs = {...defaults};
    if (enabled) inputs[enabled] = 'true';
    const k = core();
    await select({
      github: sdk([]), core: k,
      context: {
        sha: head, ref: 'refs/heads/main', repo, eventName: 'workflow_dispatch',
        payload: {inputs},
      },
    });
    assert.deepEqual(JSON.parse(k.outputs.stacks), []);
  }
  } finally { s.diff = originalDiff; }
});

test('dispatch declaration discovery includes digits, dashes and future unrecognized IDs', () => {
  const workflow = "on:\n  workflow_dispatch:\n    inputs:\n      apply_gateway_ether7:\n        type: boolean\n      future-mode2:\n        type: boolean\npermissions:\n  contents: read\n";
  assert.deepEqual(s.dispatchInputs(workflow), ['apply_gateway_ether7', 'future-mode2']);
});
