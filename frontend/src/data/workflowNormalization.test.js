import test from 'node:test';
import assert from 'node:assert/strict';
import {
  changeSourceEvent,
  normalizeWorkflow,
  SOURCE_EVENTS,
  SOURCE_ID
} from './workflowNormalization.js';

test('normalization creates exactly one default-positioned Source', () => {
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

test('self-text source is configured for the requested number', () => {
  assert.deepEqual(SOURCE_EVENTS.trigger_sms.config, {
    phoneNumber: '8604644276',
    checkIntervalSec: 1
  });
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

test('persisted node positions round-trip through canvas coordinates', () => {
  const loaded = normalizeWorkflow(
    [
      {
        id: SOURCE_ID,
        type: 'source',
        category: 'source',
        title: 'Source',
        position: { x: 84, y: 156 },
        config: { eventType: 'trigger_email' }
      },
      {
        id: 'summary',
        type: 'llm_summarize',
        category: 'ai',
        title: 'Summary',
        position: { x: 512, y: 288 },
        config: {}
      }
    ],
    [{ id: 'source-summary', source: SOURCE_ID, target: 'summary' }]
  );

  assert.deepEqual(
    loaded.nodes.map(({ id, x, y, position }) => ({ id, x, y, position })),
    [
      { id: SOURCE_ID, x: 84, y: 156, position: { x: 84, y: 156 } },
      { id: 'summary', x: 512, y: 288, position: { x: 512, y: 288 } }
    ]
  );

  const saved = normalizeWorkflow(
    loaded.nodes.map((node) => (
      node.id === 'summary' ? { ...node, x: 640, y: 336 } : node
    )),
    loaded.edges
  );

  assert.deepEqual(
    saved.nodes.find((node) => node.id === 'summary').position,
    { x: 640, y: 336 }
  );

  const reopened = normalizeWorkflow(
    saved.nodes.map(({ x: _x, y: _y, ...persistedNode }) => persistedNode),
    saved.edges
  );
  assert.deepEqual(
    reopened.nodes.find((node) => node.id === 'summary'),
    saved.nodes.find((node) => node.id === 'summary')
  );
});
