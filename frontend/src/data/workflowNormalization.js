export const SOURCE_ID = 'workflow-source';

export const SOURCE_EVENTS = {
  trigger_email: {
    type: 'trigger_email',
    title: 'On Email Received',
    description: 'Start when any new message arrives in Apple Mail.',
    config: { mailbox: 'Inbox', filterSubject: '', checkIntervalSec: 15, waitTimeoutSec: 0 }
  },
  trigger_cron: {
    type: 'trigger_cron',
    title: 'Repeat Schedule',
    description: 'Start on a recurring cron schedule.',
    config: { cron: '*/15 * * * *', timezone: 'America/Los_Angeles' }
  },
  trigger_voice: {
    type: 'trigger_voice',
    title: 'Voice Command',
    description: 'Start when a voice command or wake word is spoken.',
    config: { wakeWord: 'Hey Swirl', language: 'en-US', listenTimeoutSec: 30 }
  },
  trigger_webhook: {
    type: 'trigger_webhook',
    title: 'HTTP Webhook',
    description: 'Start when an incoming HTTP payload is posted to an endpoint.',
    config: { host: '127.0.0.1', port: 8787, path: '/api/v1/webhook', method: 'POST', authRequired: false, authToken: '' }
  },
  trigger_clipboard: {
    type: 'trigger_clipboard',
    title: 'Clipboard Listener',
    description: 'Start when text is copied to the macOS clipboard.',
    config: { watchText: true, minChars: 1, checkIntervalSec: 1 }
  },
  trigger_file: {
    type: 'trigger_file',
    title: 'On File Created',
    description: 'Start when a file appears in the watched Finder folder.',
    config: { watchPath: '~/Downloads', filePattern: '*', checkIntervalSec: 2 }
  }
};

export const sourceConfig = (eventType = 'trigger_email', config = {}) => {
  const normalizedEventType = SOURCE_EVENTS[eventType] ? eventType : 'trigger_email';
  return {
    eventType: normalizedEventType,
    runMode: 'once',
    ...SOURCE_EVENTS[normalizedEventType].config,
    ...config
  };
};

export const changeSourceEvent = (eventType, current = {}) => sourceConfig(eventType, {
  eventType,
  runMode: current.runMode === 'continuous' ? 'continuous' : 'once'
});

const clone = (value) => JSON.parse(JSON.stringify(value));

function normalizeNodePosition(node, defaultX = 250, defaultY = 180) {
  const x = Number.isFinite(node?.x)
    ? node.x
    : Number.isFinite(node?.position?.x)
      ? node.position.x
      : defaultX;
  const y = Number.isFinite(node?.y)
    ? node.y
    : Number.isFinite(node?.position?.y)
      ? node.position.y
      : defaultY;

  return { ...node, x, y, position: { x, y } };
}

export function createSourceNode(config = {}, x = 32, y = 140) {
  const normalizedConfig = sourceConfig(config.eventType || 'trigger_email', config);
  return {
    id: SOURCE_ID,
    type: 'source',
    title: 'Source',
    category: 'source',
    jacNode: 'SourceBlock',
    x,
    y,
    position: { x, y },
    config: normalizedConfig,
    status: 'idle'
  };
}

function legacyTriggerToSource(trigger) {
  const eventType = SOURCE_EVENTS[trigger?.type] ? trigger.type : 'trigger_email';
  const positionedTrigger = normalizeNodePosition(trigger, 32, 140);
  return createSourceNode(
    { eventType, ...(trigger?.config || {}) },
    positionedTrigger.x,
    positionedTrigger.y
  );
}

/**
 * Makes any graph safe for the canonical source contract. This is intentionally
 * pure so prompt results, presets, and persisted legacy workflows share one path.
 */
export function normalizeWorkflow(nodes = [], edges = []) {
  const inputNodes = clone(nodes || []);
  const inputEdges = clone(edges || []);
  const sourceCandidates = inputNodes.filter((node) => node.category === 'source' || node.type === 'source');
  const legacyTriggers = inputNodes.filter((node) => node.category === 'trigger');
  const source = normalizeNodePosition(
    sourceCandidates[0] || (legacyTriggers[0] ? legacyTriggerToSource(legacyTriggers[0]) : createSourceNode()),
    32,
    140
  );
  const removedIds = new Set([
    ...sourceCandidates.slice(1).map((node) => node.id),
    ...legacyTriggers.map((node) => node.id).filter((id) => id !== source.id)
  ]);
  const existingSourceId = sourceCandidates[0]?.id;
  if (existingSourceId && existingSourceId !== SOURCE_ID) {
    removedIds.add(existingSourceId);
  }

  source.id = SOURCE_ID;
  source.type = 'source';
  source.category = 'source';
  source.title = 'Source';
  source.jacNode = 'SourceBlock';
  source.config = sourceConfig(source.config?.eventType || 'trigger_email', source.config);

  const retainedNodes = inputNodes
    .filter((node) => !removedIds.has(node.id) && node.category !== 'trigger')
    .map((node) => normalizeNodePosition({ ...node, status: node.status || 'idle' }));
  const nodeIds = new Set([SOURCE_ID, ...retainedNodes.map((node) => node.id)]);
  const rewiredEdges = inputEdges
    .map((edge) => ({
      ...edge,
      source: edge.source === existingSourceId ? SOURCE_ID : edge.source,
      target: edge.target === existingSourceId ? SOURCE_ID : edge.target
    }))
    .filter((edge) => (
      edge.target !== SOURCE_ID
      && !removedIds.has(edge.source)
      && !removedIds.has(edge.target)
      && nodeIds.has(edge.source)
      && nodeIds.has(edge.target)
    ));

  // Preserve every former trigger branch by connecting its outgoing targets to Source.
  const oldTriggerIds = new Set(legacyTriggers.map((node) => node.id));
  inputEdges.forEach((edge) => {
    if (!oldTriggerIds.has(edge.source) || !nodeIds.has(edge.target)) return;
    if (!rewiredEdges.some((candidate) => candidate.source === SOURCE_ID && candidate.target === edge.target)) {
      rewiredEdges.push({
        id: `edge-${SOURCE_ID}-${edge.target}`,
        source: SOURCE_ID,
        target: edge.target,
        sourcePort: 'event',
        targetPort: edge.targetPort || 'in'
      });
    }
  });

  // A graph with no legacy trigger gets Source edges to all roots.
  const incomingTargets = new Set(rewiredEdges.map((edge) => edge.target));
  retainedNodes.forEach((node) => {
    if (node.id !== SOURCE_ID && !incomingTargets.has(node.id) && !rewiredEdges.some((edge) => edge.source === SOURCE_ID && edge.target === node.id)) {
      rewiredEdges.push({ id: `edge-${SOURCE_ID}-${node.id}`, source: SOURCE_ID, target: node.id, sourcePort: 'event', targetPort: 'in' });
    }
  });

  return { nodes: [source, ...retainedNodes.filter((node) => node.id !== SOURCE_ID)], edges: rewiredEdges };
}
