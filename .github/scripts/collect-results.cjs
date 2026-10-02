'use strict';
const fs = require('node:fs');
const path = require('node:path');
const s = require('./stacks.cjs');

// Artifacts have a fixed metadata shape only, never planned values or credentials.
module.exports = async ({github, context, core}) => {
  if (context.ref !== 'refs/heads/main') throw Error('Checkpoint requires trusted main');
  const catalog = s.catalog();
  const roots = JSON.parse(process.env.SELECTED_ROOTS);
  const seen = new Set();
  function files(dir) {
    return fs.readdirSync(dir, {withFileTypes: true}).flatMap(entry =>
      entry.isDirectory() ? files(path.join(dir, entry.name)) : [path.join(dir, entry.name)]
    );
  }
  // Validate every record before publication so malformed data cannot partially commit.
  const records = files('stack-results').map(file => {
    const result = JSON.parse(fs.readFileSync(file, 'utf8'));
    const stack = catalog.stacks.find(stack =>
      stack.id === result.id && stack.root === result.root
    );
    const validDigest = result.status === 'changes'
      ? /^[a-f0-9]{64}$/.test(result.digest) : result.digest === '';
    if (!stack || !roots.includes(result.root) || seen.has(result.id) ||
        result.sha !== context.sha ||
        Object.keys(result).sort().join() !== 'digest,id,root,sha,status' ||
        !['empty', 'error', 'changes'].includes(result.status) || !validDigest) {
      throw Error('Invalid stack result artifact');
    }
    seen.add(result.id);
    return {result, stack};
  });
  for (const {result, stack} of records) {
    if (result.status === 'empty') {
      await s.publish(github, context.repo, stack, context.sha, context.runId, 'empty');
    }
    if (result.status === 'changes') core.setOutput(result.id, result.digest);
  }
  // Missing/failed stack metadata stays pending; independent successes stand.
  const missing = roots.filter(root => !records.some(({result}) => result.root === root));
  await core.summary.addHeading('Independent plan outcomes').addTable([
    ['Stack', 'Outcome'],
    ...records.map(({result}) => [result.id, result.status]),
    ...missing.map(root => [root, 'missing; pending']),
  ]).write();
};
