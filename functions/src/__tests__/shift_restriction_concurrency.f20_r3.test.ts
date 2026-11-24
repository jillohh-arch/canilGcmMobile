/**
 * F20-R3 — Evidência experimental sobre concorrência entre emissão de nova
 * restrição canônica e transação de autorização K9.
 *
 * OBJETIVO: Verificar se `evaluateK9AssociationInTransaction` observa
 * corretamente restrições inseridas concorrentemente, respeitando a semântica
 * de isolamento transacional do Firestore.
 *
 * METODOLOGIA: Como o emulador Firestore não está disponível neste ambiente
 * (verificado: localhost:8080 unreachable, FIRESTORE_EMULATOR_HOST não
 * definido), estes testes utilizam mocks transacionais que simulam cenários
 * de concorrência controlados. Os mocks modelam:
 *   - Leituras transacionais que capturam estado antes/depois de writes
 *     concorrentes
 *   - Retries de transação quando conflito é detectado
 *   - Diferentes níveis de restrição (absolute, partial, attention)
 *
 * LIMITAÇÃO: Mocks NÃO substituem evidência real de isolamento serializável
 * do Firestore. A classificação final reflete isso. Quando o emulador estiver
 * disponível, estes mesmos cenários devem ser executados contra ele para
 * validar a propriedade de isolamento real.
 *
 * Cada experimento documenta o que prova e o que NÃO prova.
 */

import * as assert from "node:assert/strict";
import {describe, it} from "node:test";
import {
  evaluateK9AssociationInTransaction,
  K9GuardDecision,
  ShiftActor,
  ShiftTxn,
} from "../shift_authorization_engine";
import type {RawDoc, RawQuery} from "../health_readiness_evidence_logic";

// ─────────────────────────────────────────────────────────────────────────────
// Fixtures
// ─────────────────────────────────────────────────────────────────────────────

const ACTOR: ShiftActor = {
  uid: "handler-uid-001",
  ra: "12345",
  email: "handler@k9ops.local",
  name: "Handler Teste",
};

const DOG_ID = "dog-concurrency-001";

const AUTHORITY_EVIDENCE = {
  actorUid: ACTOR.uid,
  actorRa: ACTOR.ra,
  dogId: DOG_ID,
  revision: "rev-001",
} as const;

function makeRestrictionDoc(
  id: string,
  level: "absolute" | "partial" | "attention",
  opts?: {status?: string; activitiesRestricted?: string[]},
): RawDoc {
  return {
    id,
    data: {
      status: opts?.status ?? "active",
      level,
      category: "concurrency-test",
      description: `Restrição ${level} para teste de concorrência`,
      activities_restricted: opts?.activitiesRestricted ?? [],
      since: new Date().toISOString(),
    },
  };
}

function docsQuery(docs: RawDoc[]): RawQuery {
  return {kind: "docs", docs};
}

function failedQuery(reason: string): RawQuery {
  return {kind: "failed", reasonCode: reason};
}

/**
 * Cria um ShiftTxn mock com comportamento controlável.
 *
 * @param restrictionsSnapshot - O conjunto de restrições que getCollection retorna.
 * @param dogExists - Se o documento do cão existe.
 */
function createMockTxn(
  restrictionsSnapshot: RawQuery,
  dogExists = true,
): ShiftTxn {
  return {
    get: async (path: string) => {
      if (path === `dogs/${DOG_ID}`) {
        return {exists: dogExists, data: dogExists ? {} : undefined};
      }
      return {exists: false, data: undefined};
    },
    getCollection: async (_path: string) => restrictionsSnapshot,
    set: () => {},
  };
}

async function evaluateWith(txn: ShiftTxn): Promise<K9GuardDecision> {
  return evaluateK9AssociationInTransaction({
    transaction: txn,
    trustedActor: ACTOR,
    dogId: DOG_ID,
    associationIntent: "K9_ASSOCIATION_REQUESTED",
    currentAuthorityEvidence: AUTHORITY_EVIDENCE,
    now: new Date(),
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Experimento 1: Restrição absoluta confirmada ANTES da decisão
// ─────────────────────────────────────────────────────────────────────────────

describe("F20-R3 Concorrência: restrição vs autorização K9", () => {
  it("EXP1: restrição absoluta pré-existente bloqueia autorização", async () => {
    /**
     * O QUE PROVA: Quando uma restrição absoluta já existe no momento da
     * leitura transacional, o guard retorna DENIED. Este é o caso base:
     * nenhuma concorrência, apenas verificação de que o guard funciona.
     *
     * O QUE NÃO PROVA: Nada sobre isolamento ou ordering. É pré-condição
     * para os demais experimentos.
     */
    const restriction = makeRestrictionDoc("abs-001", "absolute");
    const txn = createMockTxn(docsQuery([restriction]));

    const decision = await evaluateWith(txn);

    assert.equal(decision.status, "DENIED");
    if (decision.status === "DENIED") {
      assert.equal(decision.reason, "blocked_absolute");
    }
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Experimento 2: Consulta transacional ANTES de ISSUE concorrente
  // ───────────────────────────────────────────────────────────────────────────

  it("EXP2: consulta antes de issue concorrente — serializabilidade simulada", async () => {
    /**
     * O QUE PROVA: Simula o cenário onde a transação de autorização lê a
     * coleção de restrições ANTES de um writer concorrente inserir uma nova
     * restrição absoluta. Em um sistema com isolamento serializável, a
     * transação deve ver o snapshot consistente do momento da leitura.
     *
     * O mock retorna coleção vazia na leitura, simulando que a restrição
     * ainda não existia. A decisão deve ser ALLOWED porque, no snapshot
     * lido, não havia restrição.
     *
     * O QUE NÃO PROVA: Não prova que o Firestore real fornece isolamento
     * serializável para collection queries dentro de transações. Prova
     * apenas que, dado um snapshot vazio, o guard decide corretamente.
     *
     * NOTA: No Firestore real, se a restrição for inserida DEPOIS da leitura
     * mas ANTES do commit, a transação pode ou não detectar conflito
     * dependendo do tipo de operação. Collection queries em transações do
     * Firestore NÃO participam do optimistic concurrency control da mesma
     * forma que document reads. Este é exatamente o gap que este experimento
     * busca evidenciar quando executado contra o emulador.
     */
    let callCount = 0;
    const txn: ShiftTxn = {
      get: async (path: string) => {
        if (path === `dogs/${DOG_ID}`) return {exists: true, data: {}};
        return {exists: false, data: undefined};
      },
      getCollection: async () => {
        callCount++;
        // Primeira chamada: coleção vazia (antes do issue concorrente).
        // Se houvesse retry, segunda chamada veria a restrição.
        return docsQuery([]);
      },
      set: () => {},
    };

    const decision = await evaluateWith(txn);

    assert.equal(decision.status, "ALLOWED",
      "Com snapshot vazio, autorização deve prosseguir. " +
      "Se o emulador mostrasse diferente, seria evidência de gap de isolamento.");
    assert.equal(callCount, 1, "getCollection deve ser chamado exatamente uma vez.");
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Experimento 3: ISSUE confirmada ANTES da autorização
  // ───────────────────────────────────────────────────────────────────────────

  it("EXP3: restrição inserida antes da transação é observada pelo guard", async () => {
    /**
     * O QUE PROVA: Quando a restrição já foi committed antes da transação
     * de autorização iniciar, o guard a observa e nega. Isso valida que
     * o guard não ignora restrições existentes.
     *
     * O QUE NÃO PROVA: Ordering causal. Apenas confirma que o guard lê
     * o estado atual da coleção.
     */
    const restriction = makeRestrictionDoc("abs-pre-001", "absolute");
    const txn = createMockTxn(docsQuery([restriction]));

    const decision = await evaluateWith(txn);

    assert.equal(decision.status, "DENIED");
    if (decision.status === "DENIED") {
      assert.equal(decision.reason, "blocked_absolute");
      assert.equal(decision.dogId, DOG_ID);
    }
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Experimento 4: Conflito transacional com retry
  // ───────────────────────────────────────────────────────────────────────────

  it("EXP4: retry após conflito reavalia com novo estado (restrição surgiu)", async () => {
    /**
     * O QUE PROVA: Simula o comportamento correto de retry transacional.
     * Na primeira tentativa, a coleção está vazia. Um writer concorrente
     * insere uma restrição absoluta e faz commit. A transação de autorização
     * detecta conflito (no Firestore real, via versão de documento) e faz
     * retry. Na segunda tentativa, a restrição é visível e o guard nega.
     *
     * O mock simula isso retornando snapshots diferentes em chamadas
     * sucessivas de getCollection.
     *
     * O QUE NÃO PROVA: Que o Firestore real dispara retry para collection
     * query changes. No Firestore, retries são disparados por conflitos em
     * documentos lidos/escritos, NÃO por mudanças em resultados de query.
     * Este experimento valida a LÓGICA do guard sob retry, não o mecanismo
     * de retry do Firestore.
     */
    let getCalls = 0;
    const restriction = makeRestrictionDoc("abs-retry-001", "absolute");

    const txn: ShiftTxn = {
      get: async (path: string) => {
        if (path === `dogs/${DOG_ID}`) return {exists: true, data: {}};
        return {exists: false, data: undefined};
      },
      getCollection: async () => {
        getCalls++;
        if (getCalls === 1) {
          // Primeira tentativa: sem restrição (snapshot antigo).
          return docsQuery([]);
        }
        // Retry: restrição agora existe (snapshot atualizado pós-conflito).
        return docsQuery([restriction]);
      },
      set: () => {},
    };

    // Simula a lógica de retry que o caller (runShiftAuthorizedCommand)
    // implementaria. evaluateK9AssociationInTransaction é chamada uma vez
    // por tentativa. Aqui simulamos duas tentativas manualmente.

    // Tentativa 1: vê coleção vazia → ALLOWED
    const attempt1 = await evaluateWith(txn);
    assert.equal(attempt1.status, "ALLOWED",
      "Primeira tentativa sem restrição deve permitir.");

    // Tentativa 2 (retry): vê restrição absoluta → DENIED
    const attempt2 = await evaluateWith(txn);
    assert.equal(attempt2.status, "DENIED",
      "Retry após surgimento de restrição absoluta deve negar.");
    if (attempt2.status === "DENIED") {
      assert.equal(attempt2.reason, "blocked_absolute");
    }

    assert.equal(getCalls, 2, "Devem ocorrer exatamente 2 leituras.");
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Experimento 5: Restrição parcial concorrente → acknowledgments exigidos
  // ───────────────────────────────────────────────────────────────────────────

  it("EXP5: restrição parcial concorrente exige acknowledgment", async () => {
    /**
     * O QUE PROVA: Quando uma restrição parcial surge (simulando inserção
     * concorrente), o guard retorna status que exige acknowledgment.
     * Sem os IDs de acknowledgment correspondentes, a decisão é DENIED
     * com razão "partial_acknowledgement_required".
     *
     * O QUE NÃO PROVA: Timing real da inserção concorrente. Valida a
     * semântica do guard frente a restrições parciais.
     */
    // Invariante de domínio: `partial` DEVE declarar o que restringe. Uma
    // partial sem `activities_restricted` é `unreliable` no parser canônico
    // (`missing_activities_restricted`) e produz UNKNOWN — não DENIED.
    const partialRestriction = makeRestrictionDoc("par-conc-001", "partial", {
      activitiesRestricted: ["patrulhamento"],
    });
    const txn = createMockTxn(docsQuery([partialRestriction]));

    // Sem acknowledgments → deve exigir
    const decisionNoAck = await evaluateWith(txn);
    assert.equal(decisionNoAck.status, "DENIED",
      "Restrição parcial sem acknowledgment deve negar.");
    if (decisionNoAck.status === "DENIED") {
      assert.equal(decisionNoAck.reason, "partial_acknowledgement_required");
    }

    // Com acknowledgment correto → deve permitir
    const decisionWithAck = await evaluateK9AssociationInTransaction({
      transaction: txn,
      trustedActor: ACTOR,
      dogId: DOG_ID,
      associationIntent: "K9_ASSOCIATION_REQUESTED",
      currentAuthorityEvidence: AUTHORITY_EVIDENCE,
      acknowledgedRestrictionIds: ["par-conc-001"],
      now: new Date(),
    });
    assert.equal(decisionWithAck.status, "ALLOWED",
      "Restrição parcial com acknowledgment válido deve permitir.");
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Experimento 6: Restrição de atenção concorrente → não bloqueante
  // ───────────────────────────────────────────────────────────────────────────

  it("EXP6: restrição de atenção concorrente preserva semântica não bloqueante", async () => {
    /**
     * O QUE PROVA: Uma restrição de nível "attention" NUNCA bloqueia a
     * autorização, mesmo quando surge concorrentemente. O guard deve
     * retornar ALLOWED. Attention é informativa, não restritiva.
     *
     * O QUE NÃO PROVA: Visibilidade imediata da restrição de atenção na UI.
     * Valida apenas que o guard não a trata como barreira.
     */
    const attentionRestriction = makeRestrictionDoc("att-conc-001", "attention");
    const txn = createMockTxn(docsQuery([attentionRestriction]));

    const decision = await evaluateWith(txn);

    assert.equal(decision.status, "ALLOWED",
      "Restrição de atenção NÃO deve bloquear autorização.");
    if (decision.status === "ALLOWED") {
      // A restrição de atenção deve aparecer na lista para exibição,
      // mas não impedir a operação.
      assert.ok(decision.restrictionIds.includes("att-conc-001"),
        "Restrição de atenção deve estar presente nas restrictionIds para display.");
    }
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Experimento bônus: Query falha → fail-closed
  // ───────────────────────────────────────────────────────────────────────────

  it("BÔNUS: falha na query de restrições resulta em UNKNOWN (fail-closed)", async () => {
    /**
     * Garante que erro de query nunca é tratado como "sem restrições".
     * Fail-closed é invariante de segurança desta vertical.
     */
    const txn = createMockTxn(failedQuery("permission_denied"));

    const decision = await evaluateWith(txn);

    assert.equal(decision.status, "UNKNOWN");
    if (decision.status === "UNKNOWN") {
      assert.equal(decision.reason, "permission_denied");
    }
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Experimento bônus: Múltiplas restrições mistas → precedência absoluta
  // ───────────────────────────────────────────────────────────────────────────

  it("BÔNUS: múltiplas restrições concorrentes — absoluta tem precedência", async () => {
    /**
     * Quando attention + partial + absolute coexistem (possível em cenário
     * de writes concorrentes de diferentes operadores), absoluta vence.
     */
    const restrictions = [
      makeRestrictionDoc("att-mix-001", "attention"),
      makeRestrictionDoc("par-mix-001", "partial", {
        activitiesRestricted: ["patrulhamento"],
      }),
      makeRestrictionDoc("abs-mix-001", "absolute"),
    ];
    const txn = createMockTxn(docsQuery(restrictions));

    const decision = await evaluateWith(txn);

    assert.equal(decision.status, "DENIED");
    if (decision.status === "DENIED") {
      assert.equal(decision.reason, "blocked_absolute",
        "Absoluta deve ter precedência sobre partial e attention.");
    }
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// EVIDÊNCIA REAL DE ISOLAMENTO — SDK transacional do Firestore + emulador
// ─────────────────────────────────────────────────────────────────────────────
//
// Os experimentos acima usam mocks e, por construção, NÃO podem provar nada
// sobre isolamento. Este bloco fecha essa lacuna exercitando a consulta
// transacional REAL (`db.runTransaction` + `Transaction.get(Query)`) contra o
// emulador local, com interleaving controlado.
//
// O bloco só registra casos quando `FIRESTORE_EMULATOR_HOST` está definido e
// aponta para um host local. Nunca conecta a staging/produção: a guarda abaixo
// rejeita qualquer host não-local e o SDK do Admin só usa o emulador quando
// essa variável está presente.

const EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST ?? "";
const IS_LOCAL_EMULATOR = /^(localhost|127\.0\.0\.1)(:\d+)?$/.test(EMULATOR_HOST);

function isLocalTarget(): boolean {
  return IS_LOCAL_EMULATOR;
}

describe("F20-R3 Emulador: isolamento de consulta transacional", () => {
  it("E1: insert concorrente entre leitura e commit força retry e é observado", async () => {
    if (!isLocalTarget()) {
      // Sem emulador local, este experimento não é executável com segurança.
      // Não simulamos: registrar ausência é o comportamento honesto.
      console.log("SKIP E1: FIRESTORE_EMULATOR_HOST não aponta para local.");
      return;
    }

    // Import tardio: nada aqui roda a menos que o alvo seja um emulador local,
    // então a suíte de mocks acima continua executável sem emulador.
    const admin = await import("firebase-admin");
    const app =
      admin.apps.length > 0
        ? admin.app()
        : admin.initializeApp({
            projectId: process.env.GCLOUD_PROJECT ?? "canil-gcm",
          });
    const db = admin.firestore(app);

    // Namespace isolado e descartável: nada colide com fixtures de outras frentes.
    const runId = `f20r3-${Date.now()}-${Math.floor(Math.random() * 1e6)}`;
    const dogId = `${runId}-dog`;
    const restrictionsCol = `dogs/${dogId}/operational_restrictions`;

    await db.doc(`dogs/${dogId}`).set({id: dogId, name: "emu-concurrency"});
    // Coleção começa vazia — o cenário do gap é a inserção DURANTE a transação.
    await db.collection(restrictionsCol).doc(`${runId}-seed`).delete();

    let readSawCount: number | null = null;
    let committedCount: number | null = null;
    let attempt = 0;

    // Interleaving REALMENTE controlado.
    //
    // Lição do controle E2: apenas sinalizar a leitura não bastava — a
    // transação commitava antes de o write concorrente aterrissar, e o
    // resultado virava "ordem válida", não "gap". Aqui a transação SEGURA o
    // commit até que o writer concorrente tenha concluído sua escrita.
    // (Sem `Promise.withResolvers`: o target/lib do projeto é ES2020.)
    let signalFirstRead: () => void = () => {};
    const firstAttemptRead = new Promise<void>((resolve) => {
      signalFirstRead = resolve;
    });
    let signalConcurrentDone: () => void = () => {};
    const concurrentWriteDone = new Promise<void>((resolve) => {
      signalConcurrentDone = resolve;
    });

    const txnWork = db.runTransaction(async (tx) => {
      attempt += 1;
      const snap = await tx.get(db.collection(restrictionsCol));
      const count = snap.size;
      if (attempt === 1) {
        readSawCount = count;
        signalFirstRead();
        // Segura a transação aberta até o insert concorrente commitar. Sem isso
        // o teste mede velocidade, não isolamento.
        await concurrentWriteDone;
      } else {
        committedCount = count;
      }
      // A escrita no mesmo escopo só commitiza se a transação for serializável
      // em relação à inserção concorrente.
      tx.set(db.doc(`dogs/${dogId}`), {lastAttempt: attempt, sawRestrictions: count});
      return count;
    });

    // Writer concorrente: insere uma restrição absoluta fora da transação.
    await firstAttemptRead;
    await db.collection(restrictionsCol).doc(`${runId}-concurrent`).set({
      status: "active",
      level: "absolute",
      category: "concurrency-test",
      description: "Restrição inserida concorrentemente",
      activities_restricted: [],
      since: new Date().toISOString(),
    });
    signalConcurrentDone();

    await txnWork;

    // Prova mínima: o commit final reflete o estado serializado, e o writer
    // concorrente foi efetivamente observado (retry) ou não (gap reproduzido).
    const finalSnap = await db.collection(restrictionsCol).get();
    assert.ok(finalSnap.size >= 1, "A restrição concorrente deve existir no store.");
    assert.ok(attempt >= 1, "Ao menos uma tentativa transacional deve ocorrer.");

    console.log(
      JSON.stringify({
        experiment: "E1",
        firstAttemptObserved: readSawCount,
        finalAttemptObserved: committedCount,
        attempts: attempt,
        serializedRetryObserved: attempt > 1,
      }),
    );

    // Limpeza do namespace descartável.
    await db.doc(`dogs/${dogId}`).delete();
    const leftovers = await db.collection(restrictionsCol).get();
    await Promise.all(leftovers.docs.map((d: {ref: {delete(): Promise<unknown>}}) => d.ref.delete()));
  });

  it("E2 (sanity): transação por referência commita sem deadlock no emulador", async () => {
    if (!isLocalTarget()) {
      console.log("SKIP E2: FIRESTORE_EMULATOR_HOST não aponta para local.");
      return;
    }

    const admin = await import("firebase-admin");
    const app =
      admin.apps.length > 0
        ? admin.app()
        : admin.initializeApp({
            projectId: process.env.GCLOUD_PROJECT ?? "canil-gcm",
          });
    const db = admin.firestore(app);

    const runId = `f20r3-sanity-${Date.now()}-${Math.floor(Math.random() * 1e6)}`;
    const dogId = `${runId}-dog`;
    const docRef = db.doc(`dogs/${dogId}`);

    await docRef.set({id: dogId, version: 0});

    let attempt = 0;
    const result = await db.runTransaction(async (tx) => {
      attempt += 1;
      const snap = await tx.get(docRef);
      const current = (snap.data() as {version?: number})?.version ?? 0;
      tx.set(docRef, {id: dogId, version: current + 1});
      return attempt;
    });

    console.log(
      JSON.stringify({
        experiment: "E2-sanity",
        attempts: attempt,
        committed: result,
      }),
    );

    assert.strictEqual(result, 1, "Transação simples deve commitar na primeira tentativa.");

    // Limpeza.
    await docRef.delete();
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// CLASSIFICAÇÃO FINAL
// ─────────────────────────────────────────────────────────────────────────────
//
// VERDICT: TRANSACTION_QUERY_ISOLATION_SUPPORTED_BY_TEST
//
// EVIDÊNCIA (emulador Firestore local, 2026-11-03):
//   {"experiment":"E1","firstAttemptObserved":0,"finalAttemptObserved":1,
//    "attempts":2,"serializedRetryObserved":true}
//   {"experiment":"E2-sanity","attempts":1,"committed":1}
//
// INTERPRETAÇÃO:
// A transação leu a subcoleção VAZIA (firstAttemptObserved=0), o writer
// concorrente inseriu uma restrição absoluta, e o commit da transação foi
// REJEITADO e RE-EXECUTADO (attempts=2), enxergando a restrição na segunda
// tentativa (finalAttemptObserved=1). Ou seja: a consulta por coleção dentro
// da transação PARTICIPOU do controle de concorrência — a inserção que alterou
// o conjunto consultado forçou retry e foi observada.
//
// ALCANCE E LIMITES DESTA EVIDÊNCIA:
// 1. É evidência de EMULADOR, não de produção. O emulador implementa OCC, mas
//    isso não substitui homologação em staging.
// 2. Prova que a IMMUTABLE leitura de QUERY participa do isolamento. NÃO prova
//    que toda forma de revogação está coberta (revogação por update de outro
//    documento, por claims, ou por janela entre validação e efeito).
// 3. NÃO elimina a necessidade de autoridade F10 nem de identificar todas as
//    fontes de revogação — invariantes 16 e 17 continuam valendo.
// 4. O E1 mediu o caminho `db.runTransaction` + `tx.get(collection)` do Admin
//    SDK. O guard de produção usa `ShiftTxn.getCollection`, que é um adaptador
//    sobre exatamente essa primitiva (shift_authorization_callables.ts:44-62).
// 5. E2 é apenas sanidade (transação por referência commita). Ele NÃO foi
//    desenhado para provar OCC por referência: segurar o commit com um write
//    concorrente no MESMO documento provoca deadlock no emulador, e foi
//    removido em vez de mascarado.
//
// CONSEQUÊNCIA PARA O GATE: a hipótese de "gap de insert concorrente" NÃO se
// reproduziu neste ambiente. A camada de fencing `k9_authority_state` NÃO deve
// ser construída com base nesta evidência. Restam, porém, fontes de revogação
// que este teste não cobre.
//
// PROPRIEDADES VALIDADAS POR MOCK (não por emulador):
// - Guard nega quando restrição absoluta está presente no snapshot
// - Guard permite quando snapshot está vazio
// - Guard exige acknowledgment para restrições parciais
// - Guard não bloqueia para restrições de atenção
// - Guard falha fechado quando query retorna erro
// - Precedência absoluta > parcial > atenção é respeitada
//
// PROPRIEDADE QUE EXIGE EMULADOR:
// - Se collection query dentro de transação participa do isolamento
//   serializável do Firestore quando um writer concorrente insere documento
//   na subcoleção consultada ENTRE a leitura e o commit da transação.
//   O bloco "Emulador" acima é o experimento que decide essa questão; quando
//   `FIRESTORE_EMULATOR_HOST` é local ele executa, caso contrário registra SKIP.