import test from 'node:test';
import assert from 'node:assert/strict';
import { suggestGeneratedWorkflowName } from './generatedProject.js';

test('generated workflow names are short, readable, and storage-safe', () => {
  assert.equal(
    suggestGeneratedWorkflowName('  Summarize email & save it to Notes!  '),
    'AI - Summarize email save it to Notes'
  );
  assert.match(
    suggestGeneratedWorkflowName('🌀'),
    /^AI - Generated Workflow$/
  );
  assert.ok(
    suggestGeneratedWorkflowName('word '.repeat(100)).length <= 80
  );
});
