export const SOURCE_ID = 'workflow-on-run';

const clone = (value) => JSON.parse(JSON.stringify(value));

export function createSourceNode(_config = {}, x = 32, y = 140) {
  return {
    id: SOURCE_ID,
    type: 'on_run',
    title: 'On Run',
    category: 'source',
    jacNode: 'SourceBlock',
    position: { x, y },
    customPrompt: '',
    config: {},
    status: 'idle'
  };
}

function normalizePosition(node, fallback) {
  const x = node?.position?.x ?? node?.x ?? fallback.x;
  const y = node?.position?.y ?? node?.y ?? fallback.y;
  return {
    x: Number.isFinite(Number(x)) ? Number(x) : fallback.x,
    y: Number.isFinite(Number(y)) ? Number(y) : fallback.y
  };
}

function normalizeNode(node) {
  const { x, y, position, customPrompt, ...rest } = node;
  return {
    ...rest,
    position: normalizePosition(node, { x: 250, y: 180 }),
    customPrompt: typeof customPrompt === 'string' ? customPrompt : '',
    config: node.config || {},
    status: node.status || 'idle'
  };
}

/**
 * Makes every graph start with a fixed manual "On Run" block.
 */
export function normalizeWorkflow(nodes = [], edges = []) {
  const inputNodes = clone(nodes || []);
  const inputEdges = clone(edges || []);
  const sourceCandidates = inputNodes.filter((node) => node.category === 'source' || node.type === 'source' || node.type === 'on_run');
  const source = sourceCandidates[0] || createSourceNode();
  const removedIds = new Set(sourceCandidates.slice(1).map((node) => node.id));
  const existingSourceId = sourceCandidates[0]?.id;
  if (existingSourceId && existingSourceId !== SOURCE_ID) {
    removedIds.add(existingSourceId);
  }

  source.id = SOURCE_ID;
  source.type = 'on_run';
  source.category = 'source';
  source.title = 'On Run';
  source.jacNode = 'SourceBlock';
  source.position = normalizePosition(source, { x: 32, y: 140 });
  source.customPrompt = typeof source.customPrompt === 'string' ? source.customPrompt : '';
  delete source.x;
  delete source.y;
  source.config = {};

  const retainedNodes = inputNodes
    .filter((node) => !removedIds.has(node.id))
    .map(normalizeNode);
  const nodeIds = new Set(retainedNodes.map((node) => node.id));
  const rewiredEdges = inputEdges
    .filter((edge) => !removedIds.has(edge.source) && !removedIds.has(edge.target) && nodeIds.has(edge.source) && nodeIds.has(edge.target))
    .map((edge) => ({ ...edge }));

  // Make the manual starter reach every unconnected action root.
  const incomingTargets = new Set(rewiredEdges.map((edge) => edge.target));
  retainedNodes.forEach((node) => {
    if (node.id !== SOURCE_ID && !incomingTargets.has(node.id) && !rewiredEdges.some((edge) => edge.source === SOURCE_ID && edge.target === node.id)) {
      rewiredEdges.push({ id: `edge-${SOURCE_ID}-${node.id}`, source: SOURCE_ID, target: node.id, sourcePort: 'event', targetPort: 'in' });
    }
  });

  return { nodes: [source, ...retainedNodes.filter((node) => node.id !== SOURCE_ID)], edges: rewiredEdges };
}
