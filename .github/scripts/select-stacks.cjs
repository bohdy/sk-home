'use strict';
const s = require('./stacks.cjs');

// github-script supplies its authenticated SDK; no credentials enter child processes.
module.exports = async ({github, context, core}) => {
  const catalog = s.catalog();
  const head = context.sha;
  const selected = [];
  const uninitialized = [];
  const event = context.payload;
  if (context.eventName === 'pull_request') {
    const base = event.pull_request.base.sha;
    const prHead = event.pull_request.head.sha;
    if (!s.SHA.test(base) || !s.SHA.test(prHead)) throw Error('Invalid PR comparison');
    // Main can advance after a PR branches; compare its actual common ancestor.
    const mergeBase = s.git(['merge-base', base, prHead]);
    const paths = s.diff(mergeBase, prHead);
    const names = s.git(['ls-tree', '--name-only', base, '.github/opentofu-stacks.json']);
    const previous = names
      ? s.catalog(JSON.parse(s.git(['show', `${base}:.github/opentofu-stacks.json`])))
      : catalog;
    const ids = new Set([
      ...s.selected(catalog, paths, true), ...s.selected(previous, paths, true),
    ].map(stack => stack.id));
    for (const id of ids) {
      const current = catalog.stacks.find(stack => stack.id === id);
      if (!current) throw Error('Removed stack requires an explicit catalog migration');
      selected.push(current);
    }
  } else {
    if (context.ref !== 'refs/heads/main') throw Error('Stack selection requires trusted main');
    const inputs = event.inputs || {};
    for (const [name, value] of Object.entries(inputs)) {
      if (name !== 'reconcile_stack' &&
          (!Object.hasOwn(catalog.dispatch_modes, name) || !['true', 'false'].includes(value))) {
        throw Error('Invalid dispatch input');
      }
    }
    const modes = Object.entries(inputs)
      .filter(([name, value]) => name !== 'reconcile_stack' && value === 'true')
      .map(([name]) => name);
    const reconcile = inputs.reconcile_stack || 'none';
    const selectedReconcile = catalog.stacks.find(stack =>
      stack.id === reconcile && stack.lifecycle !== 'separate'
    );
    if (modes.length + Number(reconcile !== 'none') > 1 ||
        (reconcile !== 'none' && !selectedReconcile)) {
      throw Error('Invalid stack selection mode');
    }
    if (modes.length) {
      const mode = catalog.dispatch_modes[modes[0]];
      if (mode.ordinary) selected.push(catalog.stacks.find(stack => stack.id === mode.stack));
      // All other modes retain the existing dedicated guarded lifecycle.
    } else if (reconcile !== 'none') {
      selected.push(selectedReconcile);
    } else {
      for (const stack of catalog.stacks.filter(stack => stack.lifecycle !== 'separate')) {
        const checkpoint = await s.checkpoint(github, context.repo, stack, head);
        if (!checkpoint) uninitialized.push(stack.id);
        // Preserve pending inputs until first convergence; the anchor is only a comparison base.
        const base = checkpoint || catalog.bootstrap_comparison_sha;
        if (s.selected(catalog, s.diff(base, head)).some(changed => changed.id === stack.id)) {
          selected.push(stack);
        }
      }
    }
  }
  core.setOutput('stacks', JSON.stringify(selected.map(stack => stack.root)));
  core.setOutput('has_changes', String(selected.length > 0));
  core.setOutput('uninitialized', JSON.stringify(uninitialized));
  await core.summary.addHeading('OpenTofu selection').addRaw(
    `Selected: ${selected.map(stack => stack.id).join(', ') || 'none'}\n\n` +
    `Uninitialized checkpoints: ${uninitialized.join(', ') || 'none'}. ` +
    'Bootstrap each named stack with reconcile_stack; no convergence is inferred.\n'
  ).write();
};
