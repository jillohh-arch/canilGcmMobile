/**
 * HEALTH-V1-OP-AUTH — matriz do guard canônico de restrições.
 *
 * Cobre S-01..S-10 (autorização por nível/lifecycle), F-01..F-05 (fail-closed) e
 * a política de atividade parcial.
 *
 * Stage HEALTH-V1-OP-AUTH — implementação local. Não deployado.
 *
 * Harness idiomático dos testes de functions: `assert` puro, helper `test()`
 * local, um `main()`, exit não-zero em falha.
 */
import * as assert from "assert";
import {
  RawQuery,
} from "./health_readiness_evidence_logic";
import {
  decisionAllowsMutation,
  decisionRequiresAcknowledgement,
  evaluateShiftRestrictionGuard,
  ShiftRestrictionDecision,
} from "./shift_restriction_guard";

const NOW = new Date("2026-08-13T12:00:00.000Z");
const MILLIS_PER_DAY = 86_400_000;

/**
 * Timestamp Firestore duck-typed.
 *
 * O parser canônico aceita Timestamp ou string ISO e rejeita um `Date` cru —
 * então o fixture usa o formato de wire real. Um `Date` aqui produziria
 * `malformed_since` e todo caso "restrição ativa válida" viraria `unavailable`,
 * mascarando a matriz inteira.
 */
function timestamp(date: Date): {toDate: () => Date} {
  return {toDate: () => date};
}

function daysAgo(days: number): {toDate: () => Date} {
  return timestamp(new Date(NOW.getTime() - days * MILLIS_PER_DAY));
}

function daysAhead(days: number): {toDate: () => Date} {
  return timestamp(new Date(NOW.getTime() + days * MILLIS_PER_DAY));
}

/**
 * Documento de restrição no formato de wire real (snake_case), como o Firestore
 * devolve. Escrever o wire literal aqui é deliberado: se o contrato persistido
 * mudar, este teste tem de sentir.
 */
function restrictionDoc(
  id: string,
  overrides: Record<string, unknown>,
): {readonly id: string; readonly data: Record<string, unknown>} {
  return {
    id,
    data: {
      status: "active",
      level: "attention",
      description: "Restrição registrada por profissional externo.",
      category: "injury",
      activities_restricted: [],
      issued_at: daysAgo(3),
      ...overrides,
    },
  };
}

function docs(
  ...list: readonly {readonly id: string; readonly data: Record<string, unknown>}[]
): RawQuery {
  return {kind: "docs", docs: list};
}

function decide(
  query: RawQuery,
  requestedActivity: string | null = null,
): ShiftRestrictionDecision {
  return evaluateShiftRestrictionGuard({
    restrictions: query,
    requestedActivity,
    now: NOW,
  });
}

let failed = 0;

async function test(name: string, fn: () => void | Promise<void>): Promise<void> {
  try {
    await fn();
    console.log(`ok - ${name}`);
  } catch (error) {
    failed += 1;
    console.error(`FAIL - ${name}`);
    console.error(error);
  }
}

async function main(): Promise<void> {
  // ── S-01 ──────────────────────────────────────────────────────────────────
  await test("S-01 nenhuma restrição ativa -> permitido", () => {
    const decision = decide(docs());
    assert.strictEqual(decision.outcome, "allowed");
    assert.strictEqual(decisionAllowsMutation(decision), true);
    assert.strictEqual(decisionRequiresAcknowledgement(decision), false);
  });

  // ── S-02 ──────────────────────────────────────────────────────────────────
  await test("S-02 absolute ativa -> bloqueado", () => {
    const decision = decide(
      docs(restrictionDoc("r1", {level: "absolute"})),
    );
    assert.strictEqual(decision.outcome, "blocked_absolute");
    assert.strictEqual(decisionAllowsMutation(decision), false);
  });

  // ── S-03 ──────────────────────────────────────────────────────────────────
  await test("S-03 partial ativa -> permitido com restrições", () => {
    const decision = decide(
      docs(
        restrictionDoc("r1", {
          level: "partial",
          activities_restricted: ["busca", "guarda"],
        }),
      ),
    );
    assert.strictEqual(decision.outcome, "allowed_with_restrictions");
    assert.strictEqual(decisionAllowsMutation(decision), true);
    // O aceite de ciência é exigido — e é o que fica auditado.
    assert.strictEqual(decisionRequiresAcknowledgement(decision), true);
    assert.deepStrictEqual(
      decision.outcome === "allowed_with_restrictions" ?
        decision.restrictions[0].activitiesRestricted :
        null,
      ["busca", "guarda"],
    );
  });

  // ── S-04 ──────────────────────────────────────────────────────────────────
  await test("S-04 attention ativa -> permitido, sem exigir aceite", () => {
    const decision = decide(
      docs(restrictionDoc("r1", {level: "attention"})),
    );
    assert.strictEqual(decision.outcome, "allowed");
    assert.strictEqual(decisionAllowsMutation(decision), true);
    assert.strictEqual(decisionRequiresAcknowledgement(decision), false);
    // Continua informando: a restrição viaja para a UI mesmo sem bloquear.
    assert.strictEqual(
      decision.outcome === "allowed" ? decision.restrictions.length : -1,
      1,
    );
  });

  // ── S-05 ──────────────────────────────────────────────────────────────────
  await test("S-05 absolute + partial -> bloqueado (absolute vence)", () => {
    const decision = decide(
      docs(
        restrictionDoc("r-partial", {
          level: "partial",
          activities_restricted: ["faro"],
        }),
        restrictionDoc("r-absolute", {level: "absolute"}),
      ),
    );
    assert.strictEqual(decision.outcome, "blocked_absolute");
  });

  // ── S-06 ──────────────────────────────────────────────────────────────────
  await test("S-06 absolute ended -> permitido", () => {
    const decision = decide(
      docs(
        restrictionDoc("r1", {
          level: "absolute",
          status: "ended",
          actual_end: daysAgo(1),
        }),
      ),
    );
    assert.strictEqual(decision.outcome, "allowed");
  });

  // ── S-07 ──────────────────────────────────────────────────────────────────
  await test("S-07 absolute cancelled -> permitido", () => {
    const decision = decide(
      docs(restrictionDoc("r1", {level: "absolute", status: "cancelled"})),
    );
    assert.strictEqual(decision.outcome, "allowed");
  });

  // ── S-08 ──────────────────────────────────────────────────────────────────
  await test("S-08 absolute active com expected_end vencido -> ainda bloqueia", () => {
    const decision = decide(
      docs(
        restrictionDoc("r1", {
          level: "absolute",
          expected_end: daysAgo(10),
        }),
      ),
    );
    assert.strictEqual(decision.outcome, "blocked_absolute");
    // Vencida sinaliza reavaliação; não encerra a restrição.
    assert.strictEqual(
      decision.outcome === "blocked_absolute" ?
        decision.restrictions[0].isOverdue :
        null,
      true,
    );
  });

  await test("S-08b absolute active com expected_end futuro -> bloqueia sem overdue", () => {
    const decision = decide(
      docs(
        restrictionDoc("r1", {
          level: "absolute",
          expected_end: daysAhead(10),
        }),
      ),
    );
    assert.strictEqual(decision.outcome, "blocked_absolute");
    assert.strictEqual(
      decision.outcome === "blocked_absolute" ?
        decision.restrictions[0].isOverdue :
        null,
      false,
    );
  });

  // ── S-09 ──────────────────────────────────────────────────────────────────
  // LOAD-BEARING: o guard não tem nem como olhar o summary. Um summary dizendo
  // "operational" é irrelevante — a autoridade é a restrição canônica.
  await test("S-09 summary diria operational mas absolute canônica ativa -> BLOQUEADO", () => {
    const decision = decide(
      docs(restrictionDoc("r1", {level: "absolute"})),
    );
    assert.strictEqual(decision.outcome, "blocked_absolute");
  });

  // ── S-10 ──────────────────────────────────────────────────────────────────
  // Inverso do S-09: display stale não pode bloquear. Sem restrição ativa, a
  // autorização canônica permite, ainda que o badge diga temporarily_unfit.
  await test("S-10 summary diria temporarily_unfit sem restrição ativa -> permitido", () => {
    const decision = decide(docs());
    assert.strictEqual(decision.outcome, "allowed");
  });

  // ── Atividade parcial ─────────────────────────────────────────────────────
  await test("P-06 partial + atividade restrita solicitada -> atividade bloqueada", () => {
    const decision = decide(
      docs(
        restrictionDoc("r1", {
          level: "partial",
          activities_restricted: ["busca", "guarda"],
        }),
      ),
      "busca",
    );
    assert.strictEqual(decision.outcome, "blocked_activity");
    assert.strictEqual(
      decision.outcome === "blocked_activity" ? decision.activity : null,
      "busca",
    );
    assert.strictEqual(decisionAllowsMutation(decision), false);
  });

  await test("partial + atividade NÃO restrita -> permitido com restrições", () => {
    const decision = decide(
      docs(
        restrictionDoc("r1", {
          level: "partial",
          activities_restricted: ["busca"],
        }),
      ),
      "faro",
    );
    assert.strictEqual(decision.outcome, "allowed_with_restrictions");
  });

  await test("partial + início genérico de turno (sem atividade) -> permitido com alerta", () => {
    const decision = decide(
      docs(
        restrictionDoc("r1", {
          level: "partial",
          activities_restricted: ["busca"],
        }),
      ),
      null,
    );
    assert.strictEqual(decision.outcome, "allowed_with_restrictions");
    assert.strictEqual(decisionRequiresAcknowledgement(decision), true);
  });

  await test("atividade restrita compara tolerante a caixa e espaço", () => {
    const decision = decide(
      docs(
        restrictionDoc("r1", {
          level: "partial",
          activities_restricted: ["  Busca  "],
        }),
      ),
      "BUSCA",
    );
    assert.strictEqual(decision.outcome, "blocked_activity");
  });

  await test("attention com activities_restricted não bloqueia atividade", () => {
    // Só `partial` restringe atividade. `attention` informa.
    const decision = decide(
      docs(
        restrictionDoc("r1", {
          level: "attention",
          activities_restricted: ["busca"],
        }),
      ),
      "busca",
    );
    assert.strictEqual(decision.outcome, "allowed");
  });

  // ── F-01 ──────────────────────────────────────────────────────────────────
  await test("F-01 query falhou -> unavailable, NUNCA lista vazia", () => {
    const decision = decide({kind: "failed", reasonCode: "permission_denied"});
    assert.strictEqual(decision.outcome, "unavailable");
    assert.strictEqual(decisionAllowsMutation(decision), false);
    assert.strictEqual(
      decision.outcome === "unavailable" ? decision.reasonCode : null,
      "permission_denied",
    );
  });

  // ── F-02 ──────────────────────────────────────────────────────────────────
  await test("F-02 restrição malformada relevante -> não libera silenciosamente", () => {
    const decision = decide(
      docs(restrictionDoc("r1", {level: "absolute", description: ""})),
    );
    assert.strictEqual(decision.outcome, "unavailable");
    assert.strictEqual(decisionAllowsMutation(decision), false);
  });

  // ── F-03 ──────────────────────────────────────────────────────────────────
  await test("F-03 nível desconhecido -> não assume attention", () => {
    const decision = decide(
      docs(restrictionDoc("r1", {level: "quarentena_total"})),
    );
    assert.strictEqual(decision.outcome, "unavailable");
    assert.strictEqual(decisionAllowsMutation(decision), false);
  });

  // ── F-04 ──────────────────────────────────────────────────────────────────
  await test("F-04 status desconhecido -> não assume ended", () => {
    const decision = decide(
      docs(restrictionDoc("r1", {level: "absolute", status: "suspensa"})),
    );
    assert.strictEqual(decision.outcome, "unavailable");
    assert.strictEqual(decisionAllowsMutation(decision), false);
  });

  await test("F-04b partial ativa sem activities_restricted -> unavailable", () => {
    // Invariante de domínio: uma parcial precisa dizer o que restringe.
    const decision = decide(
      docs(
        restrictionDoc("r1", {level: "partial", activities_restricted: []}),
      ),
    );
    assert.strictEqual(decision.outcome, "unavailable");
  });

  await test("malformado em restrição ended também é fail-closed no lifecycle", () => {
    // O status é lido ANTES de qualquer outro campo, então um documento ended
    // com corpo malformado é legitimamente ignorado — mas status ilegível não.
    const decision = decide(
      docs(restrictionDoc("r1", {status: 42, level: "absolute"})),
    );
    assert.strictEqual(decision.outcome, "unavailable");
  });

  // ── Precedência sob incerteza ─────────────────────────────────────────────
  await test("uma malformada entre válidas contamina a decisão inteira", () => {
    // Descartar só a malformada poderia apresentar um K9 restrito como apto.
    const decision = decide(
      docs(
        restrictionDoc("ok", {level: "attention"}),
        restrictionDoc("bad", {level: "???"}),
      ),
    );
    assert.strictEqual(decision.outcome, "unavailable");
  });

  await test("restrições ended/cancelled malformadas não impedem operação", () => {
    const decision = decide(
      docs(
        restrictionDoc("r1", {status: "ended", level: "absolute", description: ""}),
      ),
    );
    assert.strictEqual(decision.outcome, "allowed");
  });

  if (failed > 0) {
    console.error(`\n${failed} test(s) failed`);
    process.exit(1);
  }
  console.log("shift_restriction_guard_test: all passed");
}

void main();
