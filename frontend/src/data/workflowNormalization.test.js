import test from 'node:test';
import assert from 'node:assert/strict';
import {
  changeSourceEvent,
  normalizeWorkflow,
  SOURCE_EVENTS,
  SOURCE_ID
} from './workflowNormalization.js';

test('normalization creates exactly one leftmost Source', () => {
  const workflow = normalizeWorkflow(
    [{ id: 'summary', type: 'llm_summarize', category: 'ai', title: 'Summary', x: 400, y: 100, config: {} }],
    []
  );
  assert.equal(workflow.nodes.filter((node) => node.category === 'source').length, 1);
  assert.equal(workflow.nodes[0].id, SOURCE_ID);
  assert.equal(workflow.nodes[0].x, 32);
  assert.deepEqual(workflow.edges.map(({ source, target }) => ({ source, target })), [
    { source: SOURCE_ID, target: 'summary' }
  ]);
});

test('event changes retain run mode and apply event-specific configuration', () => {
  for (const eventType of Object.keys(SOURCE_EVENTS)) {
    const config = changeSourceEvent(eventType, { runMode: 'continuous', mailbox: 'Old mailbox' });
    assert.equal(config.eventType, eventType);
    assert.equal(config.runMode, 'continuous');
    for (const [key, value] of Object.entries(SOURCE_EVENTS[eventType].config)) {
      assert.deepEqual(config[key], value);
    }
  }
});

test('legacy triggers migrate and reconnect downstream nodes', () => {
  const workflow = normalizeWorkflow(
    [
      { id: 'legacy', type: 'trigger_file', category: 'trigger', title: 'File', x: 50, y: 90, config: { watchPath: '~/Desktop' } },
      { id: 'next', type: 'mac_finder', category: 'mac', title: 'Finder', x: 400, y: 90, config: {} }
    ],
    [{ id: 'old-edge', source: 'legacy', target: 'next' }]
  );
  assert.equal(workflow.nodes.some((node) => node.category === 'trigger'), false);
  assert.equal(workflow.nodes[0].config.eventType, 'trigger_file');
  assert.equal(workflow.nodes[0].config.watchPath, '~/Desktop');
  assert.equal(workflow.edges.some((edge) => edge.source === SOURCE_ID && edge.target === 'next'), true);
});

test('duplicate generated sources collapse to the canonical Source', () => {
  const workflow = normalizeWorkflow(
    [
      { id: 'source-a', type: 'source', category: 'source', title: 'A', config: { eventType: 'trigger_voice' } },
      { id: 'source-b', type: 'source', category: 'source', title: 'B', config: { eventType: 'trigger_cron' } },
      { id: 'result', type: 'mac_notes', category: 'mac', title: 'Notes', config: {} }
    ],
    [{ id: 'edge', source: 'source-a', target: 'result' }]
  );
  assert.equal(workflow.nodes.filter((node) => node.category === 'source').length, 1);
  assert.equal(workflow.nodes[0].id, SOURCE_ID);
  assert.equal(workflow.nodes[0].config.eventType, 'trigger_voice');
});
