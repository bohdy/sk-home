'use strict';
// Static contracts complement actionlint with repository-specific trust rules.
const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),os=require('node:os'),path=require('node:path');
const main=fs.readFileSync('.github/workflows/terraform.yaml','utf8'),pr=fs.readFileSync('.github/workflows/terraform-pr-validation.yaml','utf8');
function job(name) {const start=main.indexOf(`\n  ${name}:\n`),tail=main.slice(start+1);
  assert.ok(start>=0);
  const end=tail.slice(3).search(/\n  [a-z][a-z-]+:\n/);return end<0?tail:tail.slice(0,end+3);}
test('hosted discovery and collector cannot run infrastructure commands',()=> {
  for(const name of ['detect-changes','collect-stack-results']) {const x=job(name);
  assert.match(x,/runs-on: ubuntu-latest/);
  assert.doesNotMatch(x,/bitwarden\/|self-hosted|run: tofu|BWS_ACCESS_TOKEN/);}
  assert.match(job('detect-changes'),/deployments: read/);
  assert.match(job('collect-stack-results'),/if: always\(\)/);
  assert.match(job('collect-stack-results'),/deployments: write/);
});
test('matrix independent results gate exact digests and production applies',()=> {
  assert.match(job('tofu-plan'),/fail-fast: false/);
  assert.match(job('tofu-plan'),/fromJSON\(needs.detect-changes.outputs.stacks\)/);
  assert.match(job('tofu-plan'),/PLAN_EXIT: \$\{\{ job.status == 'success' && steps.plan.outputs.exitcode \|\| '1' \}\}/);
  assert.match(job('tofu-plan'),/Upload OpenTofu plan artifact\n        if: steps.plan.outputs.exitcode == '2'/);
  for(const [name,id] of [['tofu-apply','talos'],['gateway-apply','gateway'],['cloudflare-apply','cloudflare']]) {
    const x=job(name);
  assert.match(x,/environment: production/);
  assert.ok(x.includes(`needs.collect-stack-results.outputs.${id} != ''`));
  assert.match(x,/sha256sum --check --status/);
  assert.match(x,/Verify full-root convergence/);
  assert.ok(x.indexOf('Verify full-root convergence')<x.indexOf('Record verified full-root checkpoint'));
  assert.ok(x.indexOf('Verify same-run plan digest')<x.indexOf('Get '));
  }
  assert.match(job('tofu-plan'),/if: matrix.stacks == 'k3s\/talos-cluster'\n        # The GitHub Bitwarden identity/);
});
test('targeted recovery cannot write canonical checkpoints',()=> {
  const names=[...main.matchAll(/^  ([a-z][a-z-]+):$/gm)].map(m=>m[1]);
  for(const name of names.filter(n=>/^(gateway-|proxmox-storage-)/.test(n) && n!=='gateway-apply')) assert.doesNotMatch(job(name),/deployments: write|s\.publish\(|Record verified full-root checkpoint/);
});
test('PR workflow has no infrastructure access or plan/upload steps',()=> {
  assert.doesNotMatch(pr,/runs-on: self-hosted|bitwarden\/|deployments:|actions\/upload-artifact|run:.*\bplan\b|environment: production|run:.*init\s*$/m);
  assert.match(pr,/init -backend=false -input=false/);
  assert.match(pr,/persist-credentials: false/);
  assert.match(pr,/fetch-depth: 0/);
  assert.match(pr,/fail-fast: false/);
  assert.match(pr,/name: OpenTofu validation complete/);
});
test('certificate and service credentials follow main-only job guards',()=> {
  for(const file of ['mikrotik-certificates.yaml','routeros-service-inventory.yaml']) {const x=fs.readFileSync(`.github/workflows/${file}`,'utf8');
  assert.match(x,/if: github.ref == 'refs\/heads\/main'/);
  assert.ok(x.indexOf("if: github.ref == 'refs/heads/main'")<x.indexOf('uses: bitwarden/'));}
});
test('collector records independent empty success while failed/missing roots stay pending',async()=> {
  const collect=require('./collect-results.cjs'),s=require('./stacks.cjs'),catalog=s.catalog(),sha='a'.repeat(40),dir=fs.mkdtempSync(path.join(os.tmpdir(),'collector-test-')),cwd=process.cwd(),old=process.env.SELECTED_ROOTS,publish=s.publish,calls=[],outputs={};
  fs.mkdirSync(path.join(dir,'stack-results'));
  fs.writeFileSync(path.join(dir,'stack-results/gateway.json'),JSON.stringify(s.result(catalog.stacks[0],sha,0)));
  fs.writeFileSync(path.join(dir,'stack-results/talos.json'),JSON.stringify(s.result(catalog.stacks.find(x=>x.id==='talos'),sha,1)));
  process.env.SELECTED_ROOTS=JSON.stringify(['network/gw/interfaces','k3s/talos-cluster','network/gw/dhcp']);
  s.publish=async(_g,_r,stack)=>calls.push(stack.id);
  // Load catalog from the original checkout while artifact paths use the fixture.
  const cat=s.catalog;
  s.catalog=()=>catalog;
  process.chdir(dir);
  try {await collect({github:{},context:{ref:'refs/heads/main',sha,runId:1,repo:{}},core:{setOutput:(k,v)=>outputs[k]=v,summary:{addHeading(){return this;},addTable(){return this;},write:async()=>{}}}});
  assert.deepEqual(calls,['gateway']);
  assert.deepEqual(outputs,{});
    fs.writeFileSync(path.join(dir,'stack-results/gateway.json'),JSON.stringify({...s.result(catalog.stacks[0],sha,0),secret:'must reject'}));
  await assert.rejects(collect({github:{},context:{ref:'refs/heads/main',sha},core:{}}),/Invalid stack result/);
  }finally{process.chdir(cwd);
  s.publish=publish;
  s.catalog=cat;if(old===undefined)delete process.env.SELECTED_ROOTS;else process.env.SELECTED_ROOTS=old;
  fs.rmSync(dir,{recursive:true,force:true});}
});

test('every initial targeted plan waits for dispatch mutual-exclusion validation',()=> {
  const names = [...main.matchAll(/^  ([a-z][a-z-]+):$/gm)].map(match => match[1]);
  for (const name of names.filter(name => name.endsWith('-plan') && name !== 'tofu-plan')) {
    assert.match(job(name), /needs:/);
  }
});
