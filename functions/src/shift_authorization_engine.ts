/**
 * HEALTH-V1-OP-AUTH — Engine autoritativo de associação operacional de K9.
 *
 * Possui as mutações que INTRODUZEM ou SUBSTITUEM um K9 em estado operacional.
 * Antes de qualquer write, consulta `dogs/{dogId}/operational_restrictions` e
 * aplica o guard canônico. O `health_summary/current` NUNCA é lido aqui — é
 * projeção de display (ADR-005 §13) e há teste arquitetural que falha se este
 * módulo passar a mencioná-lo.
 *
 * PRESERVAÇÃO DE SEMÂNTICA: os payloads reproduzem exatamente o que
 * `ShiftService` escreve hoje no cliente (mesmos documentos, mesmas chaves,
 * mesmo fan-out de guarnição). Esta vertical adiciona o guard; não redesenha
 * Turnos. Divergir de shape aqui quebraria Rules, telas e histórico.
 *
 * Lógica pura sobre um port de transação injetável: a MESMA implementação roda
 * em teste unitário e no emulador via Admin SDK.
 */

import {RawQuery} from "./health_readiness_evidence_logic";
import {
  decisionAllowsMutation,
  decisionRequiresAcknowledgement,
  evaluateShiftRestrictionGuard,
  ShiftRestrictionDecision,
  ShiftRestrictionView,
} from "./shift_restriction_guard";

export type JsonMap = Record<string, unknown>;

/** Ação crítica sob guard. */
export type ShiftAuthorizedAction =
  | "start_shift"
  | "switch_dog"
  | "assume_vehicle";

/**
 * Códigos de aplicação, distintos por natureza da negativa.
 *
 * `absolute_restriction_active` (certeza clínica) e
 * `restrictions_unavailable` (incerteza técnica) são deliberadamente separados:
 * colapsá-los faria o Mobile mostrar "confira sua conexão" para um bloqueio
 * clínico, ou pior, tratar falha técnica como liberação.
 */
export type ShiftAuthorizationCode =
  | "absolute_restriction_active"
  | "partial_acknowledgement_required"
  | "restrictions_unavailable"
  | "activity_restricted"
  | "k9_not_found"
  | "invalid_argument"
  | "invalid_state"
  | "idempotency_conflict";

export class ShiftAuthorizationError extends Error {
  constructor(
    readonly httpCode:
      | "failed-precondition"
      | "permission-denied"
      | "not-found"
      | "invalid-argument"
      | "unavailable",
    readonly appCode: ShiftAuthorizationCode,
    message: string,
    readonly details?: JsonMap,
  ) {
    super(message);
    this.name = "ShiftAuthorizationError";
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Ports
// ─────────────────────────────────────────────────────────────────────────────

export interface ShiftTxDocSnap {
  readonly exists: boolean;
  readonly data: JsonMap | undefined;
}

export interface ShiftTxn {
  get(path: string): Promise<ShiftTxDocSnap>;
  /** Query de subcoleção DENTRO da transação, para leitura consistente. */
  getCollection(path: string): Promise<RawQuery>;
  set(path: string, data: JsonMap, options?: {merge?: boolean}): void;
}

export interface ShiftEngineDeps {
  runTransaction<T>(fn: (txn: ShiftTxn) => Promise<T>): Promise<T>;
  createEntityId(): string;
  serverTimestamp(): unknown;
  timestampFromDate(date: Date): unknown;
  arrayUnion(...items: unknown[]): unknown;
  deleteField(): unknown;
  /** Lista de RAs de membros ativos da guarnição, exceto o handler informado. */
  activeCrewMemberRas(vehicleId: string, excludingRa: string): Promise<readonly string[]>;
  /**
   * Lê o `vehicle_id` do turno ativo do handler, para resolver o fan-out antes
   * da transação (o port de transação não faz query de coleção arbitrária).
   *
   * Isto NÃO é decisão de autorização — é só descoberta de destinatários. A
   * autoridade continua sendo a leitura de restrições feita DENTRO da transação.
   */
  activeShiftVehicleId(ra: string): Promise<string | null>;
}

export interface ShiftActor {
  readonly uid: string;
  readonly ra: string;
  readonly email: string;
  readonly name: string;
}

export interface VehicleInput {
  readonly id: string;
  readonly label: string | null;
  readonly prefix: string | null;
  readonly modelName: string | null;
  readonly unit: string | null;
  readonly crewSize: number | null;
}

export interface ShiftCommandInput {
  readonly action: ShiftAuthorizedAction;
  readonly dogId: string;
  readonly operationId: string;
  /**
   * Ciência explícita de restrição parcial.
   *
   * Vinculada aos IDs de restrição efetivamente vistos pelo operador. Um
   * boolean solto seria inauditável e permitiria aceite "às cegas" de uma
   * restrição criada depois da decisão exibida.
   */
  readonly acknowledgedRestrictionIds?: readonly string[];
  readonly startedAt?: Date;
  readonly handlerName?: string | null;
  readonly shiftGroupId?: string | null;
  readonly shiftGroupCode?: string | null;
  readonly shiftGroupLabel?: string | null;
  readonly vehicle?: VehicleInput | null;
  readonly role?: string | null;
}

export interface ShiftCommandResult {
  readonly action: ShiftAuthorizedAction;
  readonly dogId: string;
  readonly decision: ShiftRestrictionDecision["outcome"];
  readonly restrictions: readonly ShiftRestrictionView[];
  readonly acknowledgementRecorded: boolean;
  readonly shiftId: string | null;
  readonly wasNoOp: boolean;
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers de payload — espelham ShiftService 1:1
// ─────────────────────────────────────────────────────────────────────────────

export function nonEmpty(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed === "" ? null : trimmed;
}

const VALID_CREW_ROLES = [
  "titular",
  "motorista",
  "encarregado",
  "auxiliar_1",
  "auxiliar_2",
  "k9",
] as const;

export function isValidCrewRole(role: string): boolean {
  return (VALID_CREW_ROLES as readonly string[]).includes(role);
}

function vehicleFields(
  vehicle: VehicleInput | null | undefined,
  deps: ShiftEngineDeps,
  joinedAt?: unknown,
): JsonMap {
  if (!vehicle) {
    return {
      vehicle_id: null,
      vehicle_label: null,
      vehicle_prefix: null,
      vehicle_model: null,
      vehicle_unit: null,
      vehicle_joined_at: null,
    };
  }
  return {
    vehicle_id: vehicle.id,
    vehicle_label: vehicle.label,
    vehicle_prefix: vehicle.prefix,
    vehicle_model: vehicle.modelName,
    vehicle_unit: vehicle.unit,
    vehicle_joined_at: joinedAt ?? deps.serverTimestamp(),
  };
}

function shiftGroupFields(input: ShiftCommandInput): JsonMap {
  const out: JsonMap = {};
  const id = nonEmpty(input.shiftGroupId);
  const code = nonEmpty(input.shiftGroupCode);
  const label = nonEmpty(input.shiftGroupLabel);
  if (id !== null) out.shift_group_id = id;
  if (code !== null) out.shift_group_code = code;
  if (label !== null) out.shift_group_label = label;
  return out;
}

function crewFields(crewId: string, role: string, status: string): JsonMap {
  return {
    vehicle_crew_id: crewId,
    crew_id: crewId,
    crew_role: role,
    crew_status: status,
  };
}

/** Identificação do handler aceita por `active_shifts`/`shift_logs` (sem `name`). */
function handlerFieldsBasic(actor: ShiftActor): JsonMap {
  return {
    auth_uid: actor.uid,
    handler_email: actor.email.toLowerCase(),
  };
}

/** Identificação aceita por `members/{ra}` (com `name`). */
function handlerFieldsWithName(
  actor: ShiftActor,
  handlerName: string | null | undefined,
): JsonMap {
  return {
    auth_uid: actor.uid,
    handler_email: actor.email.toLowerCase(),
    name: nonEmpty(handlerName) ?? actor.name,
  };
}

function readShiftDogId(data: JsonMap | undefined): string {
  if (!data) return "";
  return (
    nonEmpty(data.service_dog_id) ??
    nonEmpty(data.serviceDogId) ??
    nonEmpty(data.dogId) ??
    nonEmpty(data.currentDogId) ??
    ""
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Guard + receipt
// ─────────────────────────────────────────────────────────────────────────────

const RESTRICTIONS_SUBCOLLECTION = "operational_restrictions";

/**
 * Traduz a decisão do guard em erro de aplicação, ou devolve a decisão quando a
 * mutação pode prosseguir.
 *
 * Fail-closed é explícito: `unavailable` termina em erro, jamais em liberação.
 */
export function enforceDecision(
  decision: ShiftRestrictionDecision,
  acknowledgedIds: readonly string[],
): void {
  if (decision.outcome === "unavailable") {
    throw new ShiftAuthorizationError(
      "unavailable",
      "restrictions_unavailable",
      "Não foi possível verificar as restrições operacionais do K9. " +
        "A operação não foi realizada.",
      {reasonCode: decision.reasonCode},
    );
  }

  if (decision.outcome === "blocked_absolute") {
    throw new ShiftAuthorizationError(
      "failed-precondition",
      "absolute_restriction_active",
      "K9 temporariamente inapto para operação: existe restrição operacional " +
        "absoluta ativa. A associação ao turno não foi realizada.",
      {restrictions: decision.restrictions as unknown as JsonMap[]},
    );
  }

  if (decision.outcome === "blocked_activity") {
    throw new ShiftAuthorizationError(
      "failed-precondition",
      "activity_restricted",
      `Atividade "${decision.activity}" está restrita para este K9.`,
      {restrictions: decision.restrictions as unknown as JsonMap[]},
    );
  }

  if (decisionRequiresAcknowledgement(decision)) {
    // Ciência precisa cobrir TODAS as restrições parciais vigentes agora. Se
    // uma nova restrição surgiu depois da decisão exibida, o aceite antigo não
    // a cobre e a operação volta para ciência — não passa em silêncio.
    const partialIds = decision.restrictions
      .filter((view) => view.level === "partial")
      .map((view) => view.id);
    const missing = partialIds.filter((id) => !acknowledgedIds.includes(id));
    if (missing.length > 0) {
      throw new ShiftAuthorizationError(
        "failed-precondition",
        "partial_acknowledgement_required",
        "K9 apto com restrições. É necessária a ciência do responsável " +
          "antes de prosseguir.",
        {
          restrictions: decision.restrictions as unknown as JsonMap[],
          pendingAcknowledgementIds: missing,
        },
      );
    }
  }

  if (!decisionAllowsMutation(decision)) {
    // Defensivo: nenhum outcome deve escapar da classificação acima.
    throw new ShiftAuthorizationError(
      "failed-precondition",
      "invalid_state",
      "Decisão de restrição não reconhecida.",
    );
  }
}

/**
 * Impressão digital do comando, para detectar reuso de `operationId` com
 * payload diferente. Sem isso, um retry adulterado herdaria a autorização.
 */
export function fingerprintCommand(input: ShiftCommandInput): string {
  return [
    input.action,
    input.dogId,
    nonEmpty(input.vehicle?.id) ?? "",
    nonEmpty(input.role) ?? "",
  ].join("|");
}

export interface ShiftGuardContext {
  readonly decision: ShiftRestrictionDecision;
  readonly acknowledgementRecorded: boolean;
}

/** Lê restrições canônicas dentro da transação e aplica o guard. */
async function guardWithinTransaction(
  txn: ShiftTxn,
  input: ShiftCommandInput,
  now: Date,
): Promise<ShiftGuardContext> {
  // Leitura DENTRO da transação: fecha o TOCTOU entre autorizar e mutar.
  const restrictions = await txn.getCollection(
    `dogs/${input.dogId}/${RESTRICTIONS_SUBCOLLECTION}`,
  );

  const decision = evaluateShiftRestrictionGuard({
    restrictions,
    requestedActivity: null, // TAXONOMY GAP: sem contrato de atividade runtime.
    now,
  });

  const acknowledgedIds = input.acknowledgedRestrictionIds ?? [];
  enforceDecision(decision, acknowledgedIds);

  return {
    decision,
    acknowledgementRecorded: decisionRequiresAcknowledgement(decision),
  };
}

function auditPayload(
  deps: ShiftEngineDeps,
  actor: ShiftActor,
  input: ShiftCommandInput,
  context: ShiftGuardContext,
  summary: string,
): JsonMap {
  const now = deps.serverTimestamp();
  return {
    action: `shift_${input.action}`,
    entity_type: "shifts",
    entity_id: actor.ra,
    summary,
    actor: {uid: actor.uid, email: actor.email, ra: actor.ra, name: actor.name},
    metadata: {
      dog_id: input.dogId,
      operation_id: input.operationId,
      guard_decision: context.decision.outcome,
      active_restriction_ids:
        context.decision.outcome === "unavailable" ?
          [] :
          context.decision.restrictions.map((view) => view.id),
      partial_acknowledged:
        context.acknowledgementRecorded ?
          (input.acknowledgedRestrictionIds ?? []) :
          [],
      // Torna explícito no registro que a autoridade foi a coleção canônica.
      authority: RESTRICTIONS_SUBCOLLECTION,
    },
    source: "functions",
    performed_at: now,
    createdAt: now,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Comando
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Executa uma ação crítica de associação de K9 sob guard canônico.
 *
 * Ordem: receipt → K9 existe → restrições canônicas → guard → writes → audit.
 * Tudo em uma única boundary transacional, então nenhuma decisão é tomada fora
 * da transação que efetiva a mutação.
 */
export async function runShiftAuthorizedCommand(
  deps: ShiftEngineDeps,
  actor: ShiftActor,
  input: ShiftCommandInput,
  now: Date,
): Promise<ShiftCommandResult> {
  const dogId = nonEmpty(input.dogId);
  if (dogId === null) {
    throw new ShiftAuthorizationError(
      "invalid-argument",
      "invalid_argument",
      "dogId é obrigatório para uma ação operacional com K9.",
    );
  }
  const operationId = nonEmpty(input.operationId);
  if (operationId === null) {
    throw new ShiftAuthorizationError(
      "invalid-argument",
      "invalid_argument",
      "operationId é obrigatório.",
    );
  }
  const role = nonEmpty(input.role) ?? "motorista";
  if (!isValidCrewRole(role)) {
    throw new ShiftAuthorizationError(
      "invalid-argument",
      "invalid_argument",
      `Função inválida: ${role}.`,
    );
  }

  const normalized: ShiftCommandInput = {...input, dogId, operationId, role};
  const fingerprint = fingerprintCommand(normalized);
  const receiptPath = `shift_operations/${operationId}`;

  // O fan-out precisa da lista de membros da guarnição. Firestore não permite
  // query de coleção arbitrária dentro de uma transação com este port, então a
  // lista é resolvida antes; o dogId gravado nela vem da decisão autorizada, e
  // um membro que entre depois é reconciliado pelo próprio fluxo de convite.
  let crewMemberRas: readonly string[] = [];
  if (normalized.action === "switch_dog") {
    const vehicleId = await deps.activeShiftVehicleId(actor.ra);
    if (vehicleId !== null && vehicleId !== "") {
      crewMemberRas = await deps.activeCrewMemberRas(vehicleId, actor.ra);
    }
  }

  return deps.runTransaction(async (txn) => {
    // 1. Receipt ANTES de qualquer escrita (durable replay).
    const receiptSnap = await txn.get(receiptPath);
    if (receiptSnap.exists) {
      const data = receiptSnap.data ?? {};
      if (data.fingerprint !== fingerprint) {
        throw new ShiftAuthorizationError(
          "failed-precondition",
          "idempotency_conflict",
          "operationId já usado por outra operação de turno.",
        );
      }
      const result = (data.result ?? {}) as JsonMap;
      return {
        action: normalized.action,
        dogId,
        decision: (result.decision as ShiftCommandResult["decision"]) ?? "allowed",
        restrictions: (result.restrictions ?? []) as readonly ShiftRestrictionView[],
        acknowledgementRecorded: result.acknowledgementRecorded === true,
        shiftId: (result.shiftId as string | null) ?? null,
        wasNoOp: true,
      };
    }

    // 2. K9 existe.
    const dogSnap = await txn.get(`dogs/${dogId}`);
    if (!dogSnap.exists) {
      throw new ShiftAuthorizationError(
        "not-found",
        "k9_not_found",
        "K9 não encontrado.",
      );
    }

    // 3+4. Restrições canônicas + guard, na mesma transação da mutação.
    const context = await guardWithinTransaction(txn, normalized, now);

    // 5. Writes equivalentes ao fluxo atual.
    const shiftId = await applyMutation(
      txn,
      deps,
      actor,
      normalized,
      role,
      crewMemberRas,
      now,
    );

    // 6. Auditoria no owner canônico.
    txn.set(
      `auditLogs/${deps.createEntityId()}`,
      auditPayload(
        deps,
        actor,
        normalized,
        context,
        summaryFor(normalized, actor, context),
      ),
    );

    const result: ShiftCommandResult = {
      action: normalized.action,
      dogId,
      decision: context.decision.outcome,
      restrictions:
        context.decision.outcome === "unavailable" ?
          [] :
          context.decision.restrictions,
      acknowledgementRecorded: context.acknowledgementRecorded,
      shiftId,
      wasNoOp: false,
    };

    txn.set(receiptPath, {
      fingerprint,
      action: normalized.action,
      dog_id: dogId,
      actor_ra: actor.ra,
      created_at: deps.serverTimestamp(),
      result: result as unknown as JsonMap,
    });

    return result;
  });
}

function summaryFor(
  input: ShiftCommandInput,
  actor: ShiftActor,
  context: ShiftGuardContext,
): string {
  const suffix =
    context.decision.outcome === "allowed_with_restrictions" ?
      " (apto com restrições, ciência registrada)" :
      "";
  if (input.action === "start_shift") {
    return `Turno iniciado: condutor ${actor.ra} com K9 ${input.dogId}${suffix}`;
  }
  if (input.action === "switch_dog") {
    return `K9 do turno alterado: condutor ${actor.ra} para K9 ${input.dogId}${suffix}`;
  }
  return `Viatura assumida: condutor ${actor.ra} com K9 ${input.dogId}${suffix}`;
}

/** Aplica os writes da ação, preservando shape atual. Retorna o shiftId. */
async function applyMutation(
  txn: ShiftTxn,
  deps: ShiftEngineDeps,
  actor: ShiftActor,
  input: ShiftCommandInput,
  role: string,
  crewMemberRas: readonly string[],
  now: Date,
): Promise<string | null> {
  if (input.action === "start_shift") {
    return applyStartShift(txn, deps, actor, input, role, now);
  }
  if (input.action === "switch_dog") {
    return applySwitchDog(txn, deps, actor, input, crewMemberRas, now);
  }
  return applyAssumeVehicle(txn, deps, actor, input, role, now);
}

function applyStartShift(
  txn: ShiftTxn,
  deps: ShiftEngineDeps,
  actor: ShiftActor,
  input: ShiftCommandInput,
  role: string,
  now: Date,
): string {
  const shiftId = deps.createEntityId();
  const vehicle = input.vehicle ?? null;
  const crewId = vehicle === null ? null : vehicle.id.trim();
  const startedAt = deps.timestampFromDate(input.startedAt ?? now);
  const groupFields = shiftGroupFields(input);
  const basic = handlerFieldsBasic(actor);
  const vFields = vehicleFields(vehicle, deps);

  txn.set(`shift_logs/${shiftId}`, {
    id: shiftId,
    handlerId: actor.ra,
    ...basic,
    ...groupFields,
    initialDogId: input.dogId,
    currentDogId: input.dogId,
    service_dog_id: input.dogId,
    ...vFields,
    vehicle_crew_id: crewId,
    crew_id: crewId,
    crew_role: role,
    crew_status: "active",
    status: "active",
    startedAt,
    endedAt: null,
    dogSwitches: [],
    vehicleChanges: [],
    createdAt: deps.serverTimestamp(),
    updatedAt: deps.serverTimestamp(),
  });

  txn.set(`active_shifts/${actor.ra}`, {
    shiftId,
    handlerId: actor.ra,
    ...basic,
    ...groupFields,
    dogId: input.dogId,
    service_dog_id: input.dogId,
    ...vFields,
    vehicle_crew_id: crewId,
    crew_id: crewId,
    crew_role: role,
    crew_status: "active",
    status: "active",
    startedAt,
    updatedAt: deps.serverTimestamp(),
  });

  if (vehicle !== null && crewId !== null) {
    txn.set(
      `vehicle_crews/${crewId}`,
      {
        id: crewId,
        vehicle_id: vehicle.id,
        vehicle_label: vehicle.label,
        vehicle_prefix: vehicle.prefix,
        vehicle_model: vehicle.modelName,
        vehicle_unit: vehicle.unit,
        crew_size: vehicle.crewSize,
        service_dog_id: input.dogId,
        titular_handler_id: actor.ra,
        active: true,
        created_at: deps.serverTimestamp(),
        updated_at: deps.serverTimestamp(),
        ended_at: deps.deleteField(),
      },
      {merge: true},
    );
    txn.set(
      `vehicle_crews/${crewId}/members/${actor.ra}`,
      {
        handler_id: actor.ra,
        ...handlerFieldsWithName(actor, input.handlerName),
        role,
        status: "active",
        dog_id: input.dogId,
        joined_at: deps.serverTimestamp(),
      },
      {merge: true},
    );
  }

  return shiftId;
}

async function applySwitchDog(
  txn: ShiftTxn,
  deps: ShiftEngineDeps,
  actor: ShiftActor,
  input: ShiftCommandInput,
  crewMemberRas: readonly string[],
  now: Date,
): Promise<string | null> {
  const activePath = `active_shifts/${actor.ra}`;
  const activeSnap = await txn.get(activePath);
  const activeData = activeSnap.data;

  if (!activeSnap.exists || !activeData || activeData.status !== "active") {
    throw new ShiftAuthorizationError(
      "failed-precondition",
      "invalid_state",
      "Turno ativo não encontrado para trocar o K9.",
    );
  }

  const shiftId = nonEmpty(activeData.shiftId);
  const fromDogId = readShiftDogId(activeData);
  const crewId = nonEmpty(activeData.vehicle_crew_id);
  const switchedAt = deps.timestampFromDate(now);

  txn.set(
    activePath,
    {
      dogId: input.dogId,
      service_dog_id: input.dogId,
      status: "active",
      lastDogSwitchAt: switchedAt,
      updatedAt: deps.serverTimestamp(),
    },
    {merge: true},
  );

  // Fan-out de guarnição preservado: os demais membros ativos acompanham o K9.
  for (const ra of crewMemberRas) {
    if (ra === actor.ra) continue;
    txn.set(
      `active_shifts/${ra}`,
      {
        dogId: input.dogId,
        service_dog_id: input.dogId,
        lastDogSwitchAt: switchedAt,
        updatedAt: deps.serverTimestamp(),
      },
      {merge: true},
    );
  }

  if (shiftId !== null) {
    txn.set(
      `shift_logs/${shiftId}`,
      {
        currentDogId: input.dogId,
        service_dog_id: input.dogId,
        dogSwitches: deps.arrayUnion({
          dogId: input.dogId,
          switchedAt,
        }),
        dog_changes: deps.arrayUnion({
          at: switchedAt,
          from: fromDogId,
          to: input.dogId,
        }),
        updatedAt: deps.serverTimestamp(),
      },
      {merge: true},
    );
  }

  if (crewId !== null) {
    txn.set(
      `vehicle_crews/${crewId}`,
      {
        service_dog_id: input.dogId,
        updated_at: deps.serverTimestamp(),
        dog_changes: deps.arrayUnion({
          at: switchedAt,
          from: fromDogId,
          to: input.dogId,
          by: actor.ra,
        }),
      },
      {merge: true},
    );
  }

  return shiftId;
}

async function applyAssumeVehicle(
  txn: ShiftTxn,
  deps: ShiftEngineDeps,
  actor: ShiftActor,
  input: ShiftCommandInput,
  role: string,
  now: Date,
): Promise<string | null> {
  const vehicle = input.vehicle;
  if (!vehicle) {
    throw new ShiftAuthorizationError(
      "invalid-argument",
      "invalid_argument",
      "vehicle é obrigatório para assumir viatura.",
    );
  }

  const activePath = `active_shifts/${actor.ra}`;
  const activeSnap = await txn.get(activePath);
  const activeData = activeSnap.data;
  if (!activeSnap.exists || !activeData || activeData.status !== "active") {
    throw new ShiftAuthorizationError(
      "failed-precondition",
      "invalid_state",
      "Turno ativo não encontrado para assumir viatura.",
    );
  }

  const crewId = vehicle.id.trim();
  const shiftId = nonEmpty(activeData.shiftId);
  const previousVehicleId = nonEmpty(activeData.vehicle_id);
  const joinedAt = deps.timestampFromDate(now);

  // Invariante preservada: guarnição ATIVA já com K9 embarcado rejeita.
  const crewSnap = await txn.get(`vehicle_crews/${crewId}`);
  const crewData = crewSnap.data;
  if (crewData?.active === true) {
    const crewDogId = nonEmpty(crewData.service_dog_id);
    if (crewDogId !== null && crewDogId !== input.dogId) {
      throw new ShiftAuthorizationError(
        "failed-precondition",
        "invalid_state",
        "Guarnição já possui K9 embarcado. Máximo 1 cão por guarnição.",
      );
    }
  }

  const vFields = vehicleFields(vehicle, deps, joinedAt);
  const cFields = crewFields(crewId, role, "active");
  const basic = handlerFieldsBasic(actor);

  txn.set(
    activePath,
    {
      ...vFields,
      ...cFields,
      ...basic,
      // O K9 autorizado é gravado explicitamente: é esta operação que pode
      // introduzir o cão quando o turno estava sem K9.
      dogId: input.dogId,
      service_dog_id: input.dogId,
      vehicle_joined_at: joinedAt,
      updatedAt: deps.serverTimestamp(),
    },
    {merge: true},
  );

  if (shiftId !== null) {
    const payload: JsonMap = {
      ...vFields,
      ...cFields,
      ...basic,
      currentDogId: input.dogId,
      service_dog_id: input.dogId,
      vehicle_joined_at: joinedAt,
      updatedAt: deps.serverTimestamp(),
    };
    if (previousVehicleId !== null && previousVehicleId !== vehicle.id) {
      payload.vehicleChanges = deps.arrayUnion({
        from_vehicle_id: previousVehicleId,
        to_vehicle_id: vehicle.id,
        at: joinedAt,
      });
    }
    txn.set(`shift_logs/${shiftId}`, payload, {merge: true});
  }

  txn.set(
    `vehicle_crews/${crewId}`,
    {
      id: crewId,
      vehicle_id: vehicle.id,
      vehicle_label: vehicle.label,
      vehicle_prefix: vehicle.prefix,
      vehicle_model: vehicle.modelName,
      vehicle_unit: vehicle.unit,
      crew_size: vehicle.crewSize,
      service_dog_id: input.dogId,
      titular_handler_id: nonEmpty(activeData.titular_handler_id) ?? actor.ra,
      active: true,
      updated_at: deps.serverTimestamp(),
      // ended_at / created_at NÃO são tocados aqui — só a abertura limpa.
    },
    {merge: true},
  );

  txn.set(
    `vehicle_crews/${crewId}/members/${actor.ra}`,
    {
      handler_id: actor.ra,
      ...handlerFieldsWithName(actor, input.handlerName),
      role,
      status: "active",
      dog_id: input.dogId,
      joined_at: deps.serverTimestamp(),
      responded_at: deps.serverTimestamp(),
    },
    {merge: true},
  );

  return shiftId;
}
