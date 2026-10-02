'use strict';
// Selection consumes executable inputs only; dependency order never implies fanout.
const fs = require('node:fs');
const cp = require('node:child_process');
const SHA = /^[a-f0-9]{40}$/;
const WORKFLOW = '.github/workflows/terraform.yaml';

function glob(pattern, file) {
  const expression = pattern.split('**/').map(part =>
    part.split('*').map(segment =>
      segment.replace(/[.+?^${}()|[\]\\]/g, '\\$&')
    ).join('[^/]*')
  ).join('(?:.*/)?');
  return new RegExp(`^${expression}$`).test(file);
}

function catalog(value = JSON.parse(fs.readFileSync('.github/opentofu-stacks.json', 'utf8'))) {
  if (value.schema !== 1 || !SHA.test(value.bootstrap_comparison_sha) ||
      !Array.isArray(value.stacks) || !Array.isArray(value.validation_inputs) ||
      !value.dispatch_modes || typeof value.dispatch_modes !== 'object') {
    throw Error('Invalid stack catalog');
  }
  const ids = new Set();
  const roots = new Set();
  const keys = new Set();
  for (const stack of value.stacks) {
    const invalid = !/^[a-z]+$/.test(stack.id) ||
      !/^[a-z0-9/-]+$/.test(stack.root) || stack.root.includes('..') ||
      !stack.state_key || stack.checkpoint_environment !== `infra-checkpoint-${stack.id}` ||
      !Array.isArray(stack.inputs) || !Array.isArray(stack.shared_inputs) ||
      !['ordinary', 'manual', 'gated', 'separate'].includes(stack.lifecycle);
    if (invalid || ids.has(stack.id) || roots.has(stack.root) || keys.has(stack.state_key)) {
      throw Error('Invalid or duplicate stack catalog entry');
    }
    ids.add(stack.id);
    roots.add(stack.root);
    keys.add(stack.state_key);
  }
  for (const [name, mode] of Object.entries(value.dispatch_modes)) {
    if (!/^(apply|plan)_[a-z0-9_-]+$/.test(name) || !ids.has(mode.stack) ||
        typeof mode.ordinary !== 'boolean') {
      throw Error('Invalid dispatch mode catalog');
    }
  }
  return value;
}

function dispatchInputs(workflow) {
  const lines = workflow.split('\n');
  const dispatch = lines.findIndex(line => line.trimEnd() === '  workflow_dispatch:');
  if (dispatch < 0 || lines[dispatch + 1].trimEnd() !== '    inputs:') {
    throw Error('Workflow dispatch input declarations missing');
  }
  const inputs = [];
  for (const line of lines.slice(dispatch + 2)) {
    if (line.trim() && !line.trimStart().startsWith('#') && !line.startsWith('      ')) break;
    const declaration = line.match(/^ {6}([^ ].*):\s*(?:#.*)?$/);
    if (!declaration) continue;
    const name = declaration[1].replace(/^(['"])(.*)\1$/, '$2');
    if (inputs.includes(name)) throw Error('Duplicate dispatch input declaration');
    inputs.push(name);
  }
  return inputs;
}

function selected(value, paths, validation = false) {
  const all = validation && paths.some(file =>
    value.validation_inputs.some(pattern => glob(pattern, file))
  );
  return value.stacks.filter(stack =>
    (validation || stack.lifecycle !== 'separate') &&
    (all || paths.some(file =>
      [...stack.inputs, ...stack.shared_inputs].some(pattern => glob(pattern, file))
    ))
  );
}

function git(args) {
  return cp.execFileSync('git', args, {
    encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'],
  }).trim();
}

function ancestor(base, head) {
  if (!SHA.test(base) || !SHA.test(head)) return false;
  try {
    git(['merge-base', '--is-ancestor', base, head]);
    return true;
  } catch {
    return false;
  }
}

function diff(base, head) {
  if (!ancestor(base, head)) throw Error('Invalid comparison ancestry');
  // --no-renames preserves both old and new mappings for moved/deleted inputs.
  return git(['diff', '--name-only', '--no-renames', base, head])
    .split('\n').filter(Boolean);
}

async function pages(method, parameters) {
  const records = [];
  try {
    for (let page = 1; ; page++) {
      const {data} = await method({...parameters, per_page: 100, page});
      if (!Array.isArray(data)) throw Error('Invalid API response');
      records.push(...data);
      if (data.length < 100) return records;
    }
  } catch {
    // SDK exceptions may contain request details; expose only the operation.
    throw Error('Checkpoint API request failed');
  }
}

// GitHub documents UTC second timestamps, but not response ordering. Validate
// before sorting so malformed dates cannot silently select an older checkpoint.
function newestFirst(records) {
  for (const record of records) {
    const timestamp = record?.created_at;
    if (typeof timestamp !== 'string' ||
        !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/.test(timestamp) ||
        !Number.isFinite(Date.parse(timestamp)) ||
        new Date(timestamp).toISOString() !== timestamp.replace('Z', '.000Z')) {
      throw Error('Invalid checkpoint timestamp');
    }
  }
  return records.sort((a, b) => b.created_at.localeCompare(a.created_at));
}

async function checkpoint(github, repo, stack, head, isAncestor = ancestor) {
  const deployments = await pages(github.rest.repos.listDeployments, {
    ...repo, environment: stack.checkpoint_environment, task: 'infra:reconcile',
  });
  // Unrelated metadata cannot provide a checkpoint, regardless of its date.
  const trustedDeployments = deployments.filter(deployment => {
    const payload = deployment.payload;
    return deployment.environment === stack.checkpoint_environment &&
      deployment.task === 'infra:reconcile' &&
      deployment.creator?.login === 'github-actions[bot]' && SHA.test(deployment.sha) &&
      payload?.schema === 1 && payload.stack === stack.id && payload.root === stack.root &&
      payload.sha === deployment.sha && payload.workflow === WORKFLOW &&
      Number.isSafeInteger(payload.run_id) && ['empty', 'reconciled'].includes(payload.status);
  });
  // A failed or pending newer deployment must not hide an older success. Check
  // all peers at the winning timestamp; IDs are not documented time ordering.
  let successfulSha = null, successfulTimestamp = null;
  for (const deployment of newestFirst(trustedDeployments)) {
    if (successfulTimestamp && deployment.created_at !== successfulTimestamp) break;
    const payload = deployment.payload;
    const statuses = await pages(github.rest.repos.listDeploymentStatuses, {
      ...repo, deployment_id: deployment.id,
    });
    const latest = newestFirst(statuses)[0];
    // Conflicting newest ties cannot establish success at second resolution.
    if (latest && statuses.some(status => status.created_at === latest.created_at &&
        (status.state !== latest.state || status.creator?.login !== latest.creator?.login))) {
      throw Error('Ambiguous latest checkpoint status');
    }
    if (latest?.state !== 'success' ||
        latest?.creator?.login !== 'github-actions[bot]') continue;

    let run;
    try {
      run = (await github.rest.actions.getWorkflowRun({
        ...repo, run_id: payload.run_id,
      })).data;
    } catch {
      throw Error('Checkpoint provenance request failed');
    }
    // Overall failure is allowed: another independent stack may have failed.
    const trustedRun = run.head_sha === deployment.sha && run.head_branch === 'main' &&
      run.path === WORKFLOW && ['push', 'workflow_dispatch'].includes(run.event) &&
      run.repository?.full_name === `${repo.owner}/${repo.repo}`;
    if (!trustedRun) continue;
    if (!isAncestor(deployment.sha, head)) {
      throw Error('Successful checkpoint ancestry cannot be verified');
    }
    if (successfulSha && successfulSha !== deployment.sha) {
      throw Error('Ambiguous successful checkpoint timestamp');
    }
    successfulSha = deployment.sha;
    successfulTimestamp = deployment.created_at;
  }
  return successfulSha;
}

async function publish(github, repo, stack, sha, runId, status) {
  if (!SHA.test(sha) || !Number.isSafeInteger(runId) ||
      !['empty', 'reconciled'].includes(status)) {
    throw Error('Invalid checkpoint result');
  }
  try {
    const {data: deployment} = await github.rest.repos.createDeployment({
      ...repo, ref: sha, task: 'infra:reconcile',
      environment: stack.checkpoint_environment, auto_merge: false,
      required_contexts: [], production_environment: false,
      payload: {
        schema: 1, stack: stack.id, root: stack.root, sha,
        workflow: WORKFLOW, run_id: runId, status,
      },
    });
    if (!Number.isSafeInteger(deployment.id)) throw Error('Invalid deployment');
    await github.rest.repos.createDeploymentStatus({
      ...repo, deployment_id: deployment.id, state: 'success',
      auto_inactive: false, environment: stack.checkpoint_environment,
    });
  } catch {
    throw Error('Checkpoint publication failed');
  }
}

function result(stack, sha, exit, digest = '') {
  if (!SHA.test(sha) || ![0, 1, 2].includes(exit) ||
      (exit === 2 && !/^[a-f0-9]{64}$/.test(digest))) {
    throw Error('Invalid plan result');
  }
  return {
    id: stack.id, root: stack.root, sha,
    status: ['empty', 'error', 'changes'][exit], digest: exit === 2 ? digest : '',
  };
}

module.exports = {dispatchInputs, git, catalog, glob, selected, diff, ancestor, pages, checkpoint, publish, result, SHA};
