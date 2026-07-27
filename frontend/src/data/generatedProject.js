const MAX_WORKFLOW_NAME_LENGTH = 80;
const GENERATED_WORKFLOW_PREFIX = 'AI - ';

export function suggestGeneratedWorkflowName(prompt) {
  const readablePrompt = prompt
    .normalize('NFKD')
    .replace(/\p{Mark}/gu, '')
    .replace(/[^A-Za-z0-9 _-]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
  const title = readablePrompt || 'Generated Workflow';

  return `${GENERATED_WORKFLOW_PREFIX}${title}`
    .slice(0, MAX_WORKFLOW_NAME_LENGTH)
    .trimEnd();
}
