"""Preview-to-Proof effect preparation and persisted receipt derivation."""

import difflib;
import hashlib;
import json;
import from block_registry { BlockExecutionResult, block_definition }
import from connectors { inspect_brief_target }
import from contracts {
    Approval,
    Artifact,
    Block,
    EffectKind,
    EffectProposalSpec,
    ExecutionFlow,
    HasRun,
    HasStep,
    ProducedArtifact,
    RequiresApproval,
    ResourceScopeSpec,
    Run,
    RunContractSpec,
    RunReceiptSpec,
    RunState,
    RunStep,
    StepState,
    StepForBlock,
    Workflow,
    WorkflowSpec
}
import from safety { sanitize_public_message }

glob WORKFLOW_DIGEST_DOMAIN: str = "quaze.workflow-revision.v1";
glob EFFECT_DIGEST_DOMAIN: str = "quaze.effect-contract.v1";
glob LOGICAL_BRIEF_TARGET: str = "fixtures/demo-vault/Tomorrow Brief.md";
glob MAX_REVIEW_CONTENT_CHARS: int = 16000;
glob MAX_REVIEW_DIFF_CHARS: int = 12000;


def _sha256_text(value: str) -> str {
    return hashlib.sha256(value.encode("utf-8")).hexdigest();
}


def canonical_snapshot_hash(snapshot: str) -> str {
    return _sha256_text(snapshot) if snapshot else "";
}


def _canonical_config(config: dict[str, object]) -> str {
    return json.dumps(
        config,
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=True
    );
}


def _dict_string(data: dict[str, object], key: str) -> str {
    value = data.get(key);
    return value if isinstance(value, str) else "";
}


def _dict_strings(data: dict[str, object], key: str) -> list[str] {
    value = data.get(key);
    return value as list[str] if isinstance(value, list) else [];
}


def _dict_bool(data: dict[str, object], key: str) -> bool {
    value = data.get(key);
    return value if isinstance(value, bool) else False;
}


def _append_unique(values: list[str], value: str) {
    if value and value not in values {
        values.append(value);
    }
}


def _effect_access(kind: EffectKind) -> str {
    if kind == EffectKind.READ {
        return "read";
    }
    if kind == EffectKind.WRITE {
        return "write";
    }
    if kind == EffectKind.OPEN {
        return "open";
    }
    return str(kind.value);
}


def workflow_revision_digest(workflow: WorkflowSpec) -> str {
    blocks_payload: list[dict[str, object]] = [];
    for block in workflow.blocks {
        blocks_payload.append({
            "id": block.id,
            "type": block.block_type,
            "block_version": block.block_version,
            "config_version": block.config_version,
            "config": block.config,
            "inputs": block.inputs,
            "outputs": block.outputs,
            "permissions": block.permissions
        });
    }
    connections_payload: list[dict[str, object]] = [];
    for connection in workflow.connections {
        connections_payload.append({
            "source_id": connection.source_id,
            "target_id": connection.target_id,
            "source_port": connection.source_port,
            "target_port": connection.target_port
        });
    }
    payload: dict[str, object] = {
        "domain": WORKFLOW_DIGEST_DOMAIN,
        "workflow_id": workflow.id,
        "name": workflow.name,
        "version": workflow.version,
        "blocks": blocks_payload,
        "connections": connections_payload
    };
    return _sha256_text(
        json.dumps(
            payload,
            sort_keys=True,
            separators=(",", ":"),
            ensure_ascii=True
        )
    );
}


def preflight_for_workflow(
    workflow: WorkflowSpec,
    connector_mode: str = "fixture",
    run_id: str = ""
) -> RunContractSpec {
    revision_digest = workflow_revision_digest(workflow);
    summary = RunContractSpec(
        state="ready",
        enforcement_level="experimental",
        contract_id=_sha256_text(
            "quaze.run-contract.v1:" + run_id + ":" + revision_digest
        ),
        workflow_version=workflow.version,
        workflow_revision_digest=revision_digest,
        connector_mode=connector_mode,
        outbound_data=[
            entry for entry in workflow.compiler_provenance.outbound_data
        ],
        duplicate_protection=(
            "bounded effect digest, server nonce, expected-prior-hash "
            "precondition, and content-hash comparison; replay deduplication "
            "is not yet proven"
        ),
        blockers=[
            (
                "Anonymous public walkers lack per-run ownership and "
                "CSRF or local-capability protection."
            ),
            (
                "The filesystem boundary is not yet a fully symlink-safe, "
                "OS-atomic compare-and-swap."
            ),
            (
                "A crash between filesystem replacement and Jac artifact "
                "persistence still requires manual reconciliation."
            ),
            (
                "Non-fixture exact content is redacted until an authenticated "
                "no-log delivery path exists."
            )
        ]
    );
    for block in workflow.blocks {
        definition = block_definition(block.block_type);
        if (
            definition is None
            or block.block_version != definition.version
            or block.config_version != definition.config_version
        ) {
            raise ValueError(
                f"Unsupported block contract {block.block_type} "
                f"v{block.block_version}/config-v{block.config_version}."
            );
        }
        kind = definition.effect_policy.kind;
        if kind == EffectKind.READ {
            summary.read_count += 1;
        } elif kind == EffectKind.TRANSFORM {
            summary.transform_count += 1;
        } elif kind == EffectKind.APPROVAL {
            summary.approval_count += 1;
        } elif kind == EffectKind.WRITE {
            summary.write_count += 1;
        } elif kind == EffectKind.OPEN {
            summary.open_count += 1;
        } elif kind == EffectKind.SEND {
            summary.send_count += 1;
        } elif kind == EffectKind.DELETE {
            summary.delete_count += 1;
        } elif kind == EffectKind.PURCHASE {
            summary.purchase_count += 1;
        }
        if kind in [
            EffectKind.WRITE,
            EffectKind.SEND,
            EffectKind.DELETE,
            EffectKind.PURCHASE
        ] {
            summary.maximum_affected_items += (
                definition.effect_policy.maximum_affected_items
            );
        }
        for permission in definition.permissions {
            _append_unique(summary.required_permissions, permission);
        }
        for requirement in definition.connector_requirements {
            summary.resource_scopes.append(
                ResourceScopeSpec(
                    connector_id=requirement.connector_id,
                    permission=requirement.permission,
                    mode=connector_mode,
                    target=definition.effect_policy.target_scope,
                    access=_effect_access(kind)
                )
            );
        }
        if definition.effect_policy.requires_approval {
            summary.required_approvals.append(block.id);
        }
        summary.retry_policy.append(
            (
                block.id + ":max_attempts="
                + str(definition.retry_policy.max_attempts)
                + ":idempotent=" + str(definition.retry_policy.idempotent)
            )
        );
        if kind == EffectKind.WRITE {
            summary.irreversible_effects.append(
                "Save Brief may replace prior file content; no backup is created."
            );
        }
    }
    return summary;
}


def effect_is_declared(
    block_type: str,
    block_version: int,
    config_version: int,
    performed_effect: EffectKind,
    outcome: str = "",
    write_state: str = ""
) -> bool {
    definition = block_definition(block_type);
    if (
        definition is None
        or definition.version != block_version
        or definition.config_version != config_version
    ) {
        return False;
    }
    if performed_effect == definition.effect_policy.kind {
        return True;
    }
    if (
        performed_effect == EffectKind.NONE
        and definition.effect_policy.kind == EffectKind.WRITE
        and outcome == "succeeded"
        and write_state == "no_change"
    ) {
        return True;
    }
    if (
        performed_effect == EffectKind.NONE
        and definition.effect_policy.kind == EffectKind.OPEN
        and outcome == "skipped"
    ) {
        return True;
    }
    return False;
}

def execution_result_disposition(
    block: Block, result: BlockExecutionResult
) -> str {
    if result.error_code in ["target_changed", "unsafe_target"] {
        return "target_revalidation";
    }
    if not result.success {
        return "connector_failure";
    }
    if not effect_is_declared(
        block.block_type,
        block.block_version,
        block.config_version,
        result.effect_kind,
        result.outcome,
        result.write_state
    ) {
        return "undeclared_effect";
    }
    return "success";
}


def _ordered_steps(run: Run) -> list[RunStep] {
    steps = [run->:HasStep:->];
    steps.sort(key=lambda (step: RunStep) { step.position; });
    return steps;
}


def _step_for_type(run: Run, block_type: str) -> RunStep | None {
    for step in _ordered_steps(run) {
        if step.block_type == block_type {
            return step;
        }
    }
    return None;
}


def _block_for_step(step: RunStep) -> Block | None {
    blocks = [step->:StepForBlock:->];
    return blocks[0] if blocks else None;
}


def _owning_workflow(run: Run) -> Workflow | None {
    workflows = [run<-:HasRun:<-];
    return workflows[0] if workflows else None;
}


def _runtime_block_contracts(run: Run) -> list[dict[str, object]] {
    contracts: list[dict[str, object]] = [];
    for step in _ordered_steps(run) {
        candidate_block = _block_for_step(step);
        if candidate_block is None {
            raise ValueError(
                f"Persisted step {step.block_id} is detached from its block."
            );
        }
        block: Block = candidate_block;
        definition = block_definition(block.block_type);
        if definition is None {
            raise ValueError(
                f"Persisted block {block.block_type} has no registry contract."
            );
        }
        connector_contracts: list[dict[str, object]] = [];
        for requirement in definition.connector_requirements {
            connector_contracts.append({
                "connector_id": requirement.connector_id,
                "implementation_version": requirement.implementation_version,
                "permission": requirement.permission,
                "required": requirement.required
            });
        }
        next_block_ids = [
            target.block_id for target in [block->:ExecutionFlow:->]
        ];
        next_block_ids.sort();
        contracts.append({
            "block_id": block.block_id,
            "block_type": block.block_type,
            "block_version": block.block_version,
            "config_version": block.config_version,
            "handler_version": definition.handler_version,
            "normalized_config": _canonical_config(block.config),
            "inputs": block.inputs,
            "outputs": block.outputs,
            "permissions": block.permissions,
            "connector_contracts": connector_contracts,
            "next_block_ids": next_block_ids
        });
    }
    return contracts;
}


obj TargetSnapshot {
    has exists: bool,
        text: str,
        content_hash: str;
}


def _target_snapshot -> TargetSnapshot {
    inspected = inspect_brief_target();
    if not inspected.success {
        raise ValueError(inspected.error);
    }
    return TargetSnapshot(
        exists=_dict_bool(inspected.data, "exists"),
        text=_dict_string(inspected.data, "content"),
        content_hash=_dict_string(inspected.data, "content_hash")
    );
}


def _effect_diff(prior: str, proposed: str) -> str {
    if prior == proposed {
        return "No content change.";
    }
    lines = difflib.unified_diff(
        prior.splitlines(),
        proposed.splitlines(),
        fromfile="prior/Tomorrow Brief.md",
        tofile="proposed/Tomorrow Brief.md",
        lineterm=""
    );
    return "\n".join(lines);
}


def _bounded(value: str, limit: int) -> tuple[str, bool] {
    return (value, False) if len(value) <= limit else (value[:limit], True);
}


def presented_source_references(
    sources: list[str], connector_mode: str
) -> list[str] {
    if connector_mode == "fixture" {
        return sources;
    }
    return [
        "source-sha256:" + _sha256_text(source)
        for source in sources
    ];
}


def prepare_write_effect(
    run: Run,
    approval_generation: int,
    approval_nonce: str,
    persist_snapshot: bool = False
) -> EffectProposalSpec {
    if approval_generation < 1 or not approval_nonce {
        raise ValueError(
            "The server must issue an approval generation and nonce."
        );
    }
    workflow = _owning_workflow(run);
    save_step = _step_for_type(run, "save_brief");
    draft_step = _step_for_type(run, "draft_brief");
    if workflow is None or save_step is None or draft_step is None {
        raise ValueError(
            "The persisted run is missing workflow, draft, or write provenance."
        );
    }
    candidate_block = _block_for_step(save_step);
    if candidate_block is None {
        raise ValueError("Save Brief is detached from its persisted block contract.");
    }
    save_block: Block = candidate_block;
    definition = block_definition(save_block.block_type);
    if (
        definition is None
        or definition.effect_policy.kind != EffectKind.WRITE
        or not definition.effect_policy.requires_approval
        or save_block.block_version != definition.version
        or save_block.config_version != definition.config_version
    ) {
        raise ValueError("Save Brief does not have a valid declared write policy.");
    }

    proposed = _dict_string(draft_step.outputs, "brief_markdown");
    sources = _dict_strings(draft_step.outputs, "source_references");
    if not proposed.strip() {
        raise ValueError("A persisted non-empty draft is required before approval.");
    }
    snapshot = _target_snapshot();
    prior = snapshot.text;
    prior_hash = snapshot.content_hash;
    proposed_hash = _sha256_text(proposed);
    canonical_sources = [source for source in sources];
    canonical_sources.sort();
    source_references_hash = _sha256_text(
        json.dumps(
            canonical_sources,
            sort_keys=True,
            separators=(",", ":"),
            ensure_ascii=True
        )
    );
    target_fingerprint = _sha256_text("filesystem:" + LOGICAL_BRIEF_TARGET);
    change_kind = (
        "create"
            if not snapshot.exists
            else "no_change" if prior_hash == proposed_hash else "update"
    );
    evidence_hashes: list[str] = [];
    for step in _ordered_steps(run) {
        for evidence_hash in step.evidence_snapshot_hashes {
            _append_unique(evidence_hashes, evidence_hash);
        }
    }
    evidence_hashes.sort();
    connector_implementation_version = (
        definition.connector_requirements[0].implementation_version
            if definition.connector_requirements
            else 0
    );
    effect_id = _sha256_text(
        (
            run.run_contract.contract_id + ":" + save_block.block_id + ":"
            + str(save_block.block_version) + ":"
            + str(save_block.config_version)
        )
    );
    digest_payload: dict[str, object] = {
        "domain": EFFECT_DIGEST_DOMAIN,
        "run_id": run.run_id,
        "contract_id": run.run_contract.contract_id,
        "effect_id": effect_id,
        "workflow_revision_digest": workflow.revision_digest,
        "workflow_version": workflow.version,
        "workflow_block_contracts": _runtime_block_contracts(run),
        "block_type": save_block.block_type,
        "block_version": save_block.block_version,
        "config_version": save_block.config_version,
        "handler_version": definition.handler_version,
        "normalized_config": _canonical_config(save_block.config),
        "connector_id": "filesystem",
        "connector_implementation_version": connector_implementation_version,
        "connector_mode": run.connector_mode,
        "connector_execution_modes": {
            "calendar": _dict_string(run.context, "calendar_mode"),
            "vault": _dict_string(run.context, "vault_mode"),
            "transform": _dict_string(run.context, "transform_mode"),
            "write": "local"
        },
        "approval_generation": approval_generation,
        "approval_nonce": approval_nonce,
        "logical_target_id": LOGICAL_BRIEF_TARGET,
        "target_fingerprint": target_fingerprint,
        "prior_target_hash": prior_hash,
        "proposed_payload_hash": proposed_hash,
        "source_references_hash": source_references_hash,
        "evidence_snapshot_hashes": evidence_hashes
    };
    canonical_snapshot = json.dumps(
        digest_payload,
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=True
    );
    effect_digest = _sha256_text(canonical_snapshot);
    if persist_snapshot {
        run.contract_snapshot = canonical_snapshot;
        run.contract_snapshot_hash = effect_digest;
        run.run_contract.contract_snapshot_hash = effect_digest;
    }
    show_fixture_content = run.connector_mode == "fixture";
    proposed_excerpt = (
        _bounded(proposed, MAX_REVIEW_CONTENT_CHARS)
            if show_fixture_content
            else ("", True)
    );
    diff_excerpt = (
        _bounded(_effect_diff(prior, proposed), MAX_REVIEW_DIFF_CHARS)
            if show_fixture_content
            else ("", True)
    );
    blockers: list[str] = [];
    if not show_fixture_content {
        blockers.append(
            "Exact proposed content and diff are unavailable outside fixture mode."
        );
    }
    if proposed_excerpt[1] {
        blockers.append(
            "The proposed content exceeds the bounded exact-review limit."
        );
    }
    if diff_excerpt[1] {
        blockers.append(
            "The proposed diff exceeds the bounded exact-review limit."
        );
    }
    approval_allowed = (
        show_fixture_content
        and not proposed_excerpt[1]
        and not diff_excerpt[1]
        and bool(effect_digest)
        and bool(approval_nonce)
    );
    return EffectProposalSpec(
        state="ready",
        change_kind=change_kind,
        content_visibility=(
            "full_synthetic_fixture"
                if show_fixture_content
                else "redacted_non_fixture"
        ),
        digest_version=EFFECT_DIGEST_DOMAIN,
        contract_id=run.run_contract.contract_id,
        effect_id=effect_id,
        block_id=save_block.block_id,
        block_type=save_block.block_type,
        workflow_version=workflow.version,
        workflow_revision_digest=workflow.revision_digest,
        block_version=save_block.block_version,
        config_version=save_block.config_version,
        handler_version=definition.handler_version,
        connector_id="filesystem",
        connector_implementation_version=connector_implementation_version,
        connector_mode=run.connector_mode,
        approval_generation=approval_generation,
        approval_nonce=approval_nonce,
        target=LOGICAL_BRIEF_TARGET,
        target_fingerprint=target_fingerprint,
        prior_target_hash=prior_hash,
        proposed_payload_hash=proposed_hash,
        proposed_content_excerpt=proposed_excerpt[0],
        proposed_content_truncated=proposed_excerpt[1],
        diff_excerpt=diff_excerpt[0],
        diff_truncated=diff_excerpt[1],
        source_references=presented_source_references(
            sources, run.connector_mode
        ),
        source_references_hash=source_references_hash,
        evidence_snapshot_hashes=evidence_hashes,
        remaining_effects=["write:save-brief", "open:open-result"],
        approval_allowed=approval_allowed,
        blockers=blockers,
        effect_digest=effect_digest
    );
}


def _governed_effect(kind: EffectKind) -> bool {
    return kind in [
        EffectKind.READ,
        EffectKind.WRITE,
        EffectKind.OPEN,
        EffectKind.SEND,
        EffectKind.DELETE,
        EffectKind.PURCHASE
    ];
}


def _effect_label(kind: EffectKind, block_id: str) -> str {
    return str(kind.value) + ":" + block_id;
}


def derive_persisted_receipt(run: Run) -> RunReceiptSpec {
    planned: list[str] = [];
    performed: list[str] = [];
    deviations: list[str] = [];
    planned_write_count = 0;
    performed_write_count = 0;
    planned_open_count = 0;
    performed_open_count = 0;
    planned_read_count = 0;
    performed_read_count = 0;
    planned_send_count = 0;
    performed_send_count = 0;
    planned_delete_count = 0;
    performed_delete_count = 0;
    planned_purchase_count = 0;
    performed_purchase_count = 0;
    for step in _ordered_steps(run) {
        if _governed_effect(step.planned_effect) {
            label = _effect_label(step.planned_effect, step.block_id);
            planned.append(label);
            if step.planned_effect == EffectKind.WRITE {
                planned_write_count += 1;
            } elif step.planned_effect == EffectKind.OPEN {
                planned_open_count += 1;
            } elif step.planned_effect == EffectKind.READ {
                planned_read_count += 1;
            } elif step.planned_effect == EffectKind.SEND {
                planned_send_count += 1;
            } elif step.planned_effect == EffectKind.DELETE {
                planned_delete_count += 1;
            } elif step.planned_effect == EffectKind.PURCHASE {
                planned_purchase_count += 1;
            }
        }
        if _governed_effect(step.performed_effect) {
            label = _effect_label(step.performed_effect, step.block_id);
            performed.append(label);
            if step.performed_effect == EffectKind.WRITE {
                performed_write_count += 1;
            } elif step.performed_effect == EffectKind.OPEN {
                performed_open_count += 1;
            } elif step.performed_effect == EffectKind.READ {
                performed_read_count += 1;
            } elif step.performed_effect == EffectKind.SEND {
                performed_send_count += 1;
            } elif step.performed_effect == EffectKind.DELETE {
                performed_delete_count += 1;
            } elif step.performed_effect == EffectKind.PURCHASE {
                performed_purchase_count += 1;
            }
        }
    }
    artifacts = [run->:ProducedArtifact:->];
    artifact: Artifact | None = artifacts[0] if artifacts else None;
    open_step = _step_for_type(run, "open_result");
    open_disposition = "not_planned";
    open_reason = "";
    if open_step is not None {
        if (
            open_step.state == StepState.SUCCEEDED
            and open_step.performed_effect == EffectKind.OPEN
        ) {
            open_disposition = "performed";
        } elif open_step.state == StepState.SKIPPED {
            open_disposition = "skipped_by_profile";
            open_reason = "Fixture mode does not launch Obsidian.";
        } elif open_step.state == StepState.FAILED {
            open_disposition = "failed";
            open_reason = sanitize_public_message(open_step.error);
        } elif open_step.state == StepState.CANCELED {
            open_disposition = "skipped";
            open_reason = "The run was canceled before Open Result.";
        } else {
            open_disposition = "planned";
        }
    }
    for planned_effect in planned {
        if planned_effect not in performed {
            if (
                artifact is not None
                and artifact.write_state == "no_change"
                and planned_effect.startswith(str(EffectKind.WRITE.value) + ":")
            ) {
                continue;
            } elif (
                open_disposition in ["skipped_by_profile", "skipped"]
                and planned_effect.startswith(str(EffectKind.OPEN.value) + ":")
            ) {
                continue;
            } elif (
                open_disposition == "planned"
                and run.state in [
                    RunState.FAILED,
                    RunState.CANCELED
                ]
                and artifact is None
            ) {
                continue;
            } else {
                deviations.append(
                    "Planned effect was not performed: " + planned_effect
                );
            }
        }
    }
    for performed_effect in performed {
        if performed_effect not in planned {
            deviations.append("Undeclared effect was performed: " + performed_effect);
        }
    }

    approvals = [run->:RequiresApproval:->];
    approval: Approval | None = approvals[0] if approvals else None;
    receipt_state = "not_available";
    if run.state == RunState.SUCCEEDED {
        receipt_state = "complete";
    } elif run.state == RunState.CANCELED {
        receipt_state = "canceled";
    } elif (
        approval is not None
        and approval.state == "rejected"
        and artifact is None
    ) {
        receipt_state = "rejected_no_effect";
    } elif run.state == RunState.FAILED and artifact is not None {
        receipt_state = "partial";
    } elif run.state == RunState.FAILED {
        receipt_state = "failed_no_effect";
    } else {
        save_step = _step_for_type(run, "save_brief");
        if (
            save_step is not None
            and save_step.state == StepState.RUNNING
            and artifact is None
        ) {
            receipt_state = "unknown/reconciliation_required";
        }
    }
    receipt = RunReceiptSpec(
        state=receipt_state,
        run_id=run.run_id,
        approved_digest=(
            approval.decision_digest if approval is not None else ""
        ),
        contract_snapshot_hash=run.contract_snapshot_hash,
        planned_effects=planned,
        performed_effects=performed,
        deviations=deviations,
        planned_read_count=planned_read_count,
        performed_read_count=performed_read_count,
        planned_write_count=planned_write_count,
        performed_write_count=performed_write_count,
        planned_open_count=planned_open_count,
        performed_open_count=performed_open_count,
        open_disposition=open_disposition,
        open_reason=open_reason,
        planned_send_count=planned_send_count,
        performed_send_count=performed_send_count,
        planned_delete_count=planned_delete_count,
        performed_delete_count=performed_delete_count,
        planned_purchase_count=planned_purchase_count,
        performed_purchase_count=performed_purchase_count,
        retry_count=run.retry_count,
        duplicate_protection_state=(
            "bounded_content_hash_matched_existing"
                if artifact is not None and artifact.write_state == "no_change"
                else (
                    "bounded_single_artifact_record_unverified_replay"
                        if artifact is not None
                        else "no_effect_recorded"
                )
        ),
        effect_outcome=(
            artifact.write_state if artifact is not None else "not_performed"
        ),
        completed_at=(
            run.updated_at
                if run.state in [
                    RunState.SUCCEEDED,
                    RunState.FAILED,
                    RunState.CANCELED
                ]
                else ""
        ),
        artifact_path=artifact.path if artifact is not None else "",
        artifact_hash=artifact.content_hash if artifact is not None else "",
        source_references=presented_source_references(
            artifact.source_references if artifact is not None else [],
            run.connector_mode
        ),
        compiler_provenance=run.compiler_provenance,
        derived_from_persisted_state=True
    );
    run.receipt = receipt;
    return receipt;
}
