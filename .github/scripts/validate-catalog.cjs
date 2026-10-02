'use strict';
const fs = require('node:fs');
const path = require('node:path');
const {catalog, glob, dispatchInputs} = require('./stacks.cjs');

// Validate static backend source; never initialize or read remote state.
const value = catalog();
function walk(dir) {
  return fs.readdirSync(dir, {withFileTypes: true}).flatMap(entry => {
    const file = path.join(dir, entry.name);
    if (entry.isDirectory() && !entry.name.startsWith('.')) return walk(file);
    return entry.isFile() && entry.name === 'backend.tf' ? [file] : [];
  });
}
const roots = walk('terraform').map(file => file.slice(10, -11));
if (roots.length !== value.stacks.length ||
    roots.some(root => !value.stacks.some(stack => stack.root === root))) {
  throw Error('Catalog must cover every active backend root');
}
for (const stack of value.stacks) {
  const backend = fs.readFileSync(`terraform/${stack.root}/backend.tf`, 'utf8');
  if (!backend.includes(`key    = "${stack.state_key}"`)) throw Error('Catalog state key mismatch');
  for (const name of fs.readdirSync(`terraform/${stack.root}`)) {
    if (/\.(tf|tfvars)$/.test(name) &&
        !stack.inputs.some(pattern => glob(pattern, `terraform/${stack.root}/${name}`))) {
      throw Error('Executable root input omitted');
    }
  }
}
for (const [file, id] of [
  ['scripts/routeros-qdevice-recovery.sh', 'gateway'],
  ['scripts/proxmox-synology-storage-reconcile.sh', 'storage'],
]) {
  if (!value.stacks.find(stack => stack.id === id).inputs.includes(file)) {
    throw Error('Recovery input mapping omitted');
  }
}
// Preserve the dedicated dispatch contract while changing ordinary selection.
const workflow = fs.readFileSync('.github/workflows/terraform.yaml', 'utf8');
const declared = dispatchInputs(workflow);
if (!declared.includes('reconcile_stack')) throw Error('Reconciliation dispatch input missing');
const modes = declared.filter(name => name !== 'reconcile_stack').sort();
if (JSON.stringify(modes) !== JSON.stringify(Object.keys(value.dispatch_modes).sort())) {
  throw Error('Dispatch catalog/workflow mismatch');
}
console.log(`Validated ${value.stacks.length} stable stacks and unchanged backend keys.`);
