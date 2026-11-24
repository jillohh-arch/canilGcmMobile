/**
 * F20 Canonical K9 Guard — Transactional Firestore Adapter.
 *
 * Implements a reusable FirestoreShiftTxnAdapter over real Firebase Admin
 * Firestore transactions, mapping the ShiftTxn contract to real transactional
 * operations (get, getCollection, restriction evidence, transactional read behavior,
 * error semantics, and authority-evidence contract) without simulating transactions
 * via independent reads.
 *
 * All operations execute strictly within the passed Transaction context,
 * preserving serializable / optimistic concurrency control (OCC) semantics.
 */

import type {
  Transaction,
  Firestore,
  DocumentReference,
  CollectionReference,
} from "firebase-admin/firestore";
import type {RawQuery, RawDoc} from "./health_readiness_evidence_logic";
import {
  JsonMap,
  ShiftTxDocSnap,
  ShiftTxn,
  ShiftActor,
  K9GuardDecision,
  evaluateK9AssociationInTransaction,
} from "./shift_authorization_engine";

/**
 * Standard contract for authority evidence binding K9 operational actions.
 */
export interface AuthorityEvidenceContract {
  readonly actorUid: string;
  readonly actorRa: string;
  readonly dogId: string;
  readonly revision?: string | null;
}

/**
 * Reusable adapter binding the pure ShiftTxn port to a real Firebase Admin Transaction.
 */
export class FirestoreShiftTxnAdapter implements ShiftTxn {
  constructor(
    public readonly tx: Transaction,
    public readonly db: Firestore,
  ) {
    if (!tx) {
      throw new Error("FirestoreShiftTxnAdapter requires an active Transaction instance.");
    }
    if (!db) {
      throw new Error("FirestoreShiftTxnAdapter requires a Firestore instance.");
    }
  }

  /**
   * Reads a document within the transaction boundary.
   * Ensures read registration for OCC conflict detection.
   */
  async get(path: string): Promise<ShiftTxDocSnap> {
    const docRef = this.resolveDocRef(path);
    const snap = await this.tx.get(docRef);
    return {
      exists: snap.exists,
      data: snap.exists ? (snap.data() as JsonMap) : undefined,
    };
  }

  /**
   * Reads a collection or subcollection within the transaction boundary.
   * Fails closed: any query or permission error returns {kind: "failed"},
   * never returning an empty list that could be mistaken for "no restrictions".
   */
  async getCollection(path: string): Promise<RawQuery> {
    try {
      const colRef = this.resolveCollectionRef(path);
      const snap = await this.tx.get(colRef);
      const docs: RawDoc[] = snap.docs.map((doc) => ({
        id: doc.id,
        data: (doc.data() ?? {}) as Record<string, unknown>,
      }));
      return {
        kind: "docs",
        docs,
      };
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : String(err);
      return {
        kind: "failed",
        reasonCode: `restrictions_query_failed: ${message}`,
      };
    }
  }

  /**
   * Queues a document set operation inside the transaction.
   */
  set(path: string, data: JsonMap, options?: {merge?: boolean}): void {
    const docRef = this.resolveDocRef(path);
    if (options?.merge) {
      this.tx.set(docRef, data, {merge: true});
    } else {
      this.tx.set(docRef, data);
    }
  }

  /**
   * Queues a document update operation inside the transaction.
   */
  update(path: string, data: JsonMap): void {
    const docRef = this.resolveDocRef(path);
    this.tx.update(docRef, data);
  }

  /**
   * Queues a document delete operation inside the transaction.
   */
  delete(path: string): void {
    const docRef = this.resolveDocRef(path);
    this.tx.delete(docRef);
  }

  /**
   * Resolves and validates a DocumentReference from a string path.
   */
  resolveDocRef(path: string): DocumentReference {
    const normalized = path.replace(/^\/+|\/+$/g, "").trim();
    if (!normalized) {
      throw new Error("Document path cannot be empty.");
    }
    const segments = normalized.split("/").filter((s) => s.length > 0);
    if (segments.length % 2 !== 0) {
      throw new Error(
        `Invalid document path "${path}". Expected even number of segments, got ${segments.length}.`,
      );
    }
    return this.db.doc(normalized);
  }

  /**
   * Resolves and validates a CollectionReference from a string path.
   */
  resolveCollectionRef(path: string): CollectionReference {
    const normalized = path.replace(/^\/+|\/+$/g, "").trim();
    if (!normalized) {
      throw new Error("Collection path cannot be empty.");
    }
    const segments = normalized.split("/").filter((s) => s.length > 0);
    if (segments.length % 2 === 0) {
      throw new Error(
        `Invalid collection path "${path}". Expected odd number of segments, got ${segments.length}.`,
      );
    }
    return this.db.collection(normalized);
  }
}

/**
 * Factory for creating a FirestoreShiftTxnAdapter over an active transaction.
 */
export function createFirestoreShiftTxnAdapter(
  tx: Transaction,
  db: Firestore,
): FirestoreShiftTxnAdapter {
  return new FirestoreShiftTxnAdapter(tx, db);
}

/**
 * Validates the authority-evidence contract binding actor UID/RA and dog ID.
 */
export function validateAuthorityEvidenceContract(
  evidence: AuthorityEvidenceContract | null | undefined,
  actor: ShiftActor | null | undefined,
  targetDogId: string,
): {readonly valid: boolean; readonly reason?: string} {
  if (!evidence) {
    return {valid: false, reason: "missing_authority_evidence"};
  }
  if (!actor || !actor.uid || !actor.ra) {
    return {valid: false, reason: "missing_trusted_actor"};
  }
  const cleanTargetDog = targetDogId.trim();
  if (!cleanTargetDog) {
    return {valid: false, reason: "target_dog_id_empty"};
  }
  if (evidence.actorUid !== actor.uid) {
    return {valid: false, reason: "authority_actor_uid_mismatch"};
  }
  if (evidence.actorRa !== actor.ra) {
    return {valid: false, reason: "authority_actor_ra_mismatch"};
  }
  if (evidence.dogId !== cleanTargetDog) {
    return {valid: false, reason: "authority_dog_id_mismatch"};
  }
  return {valid: true};
}

/**
 * Fetches canonical operational restrictions evidence within the transaction boundary.
 */
export async function fetchRestrictionsEvidenceInTxn(
  txn: ShiftTxn,
  dogId: string,
): Promise<RawQuery> {
  const cleanDogId = dogId.trim();
  if (!cleanDogId) {
    return {kind: "failed", reasonCode: "invalid_dog_id"};
  }
  return txn.getCollection(`dogs/${cleanDogId}/operational_restrictions`);
}

/**
 * Transactional runner for canonical K9 restriction evaluation.
 */
export async function evaluateCanonicalK9GuardInTxn(input: {
  readonly txn: ShiftTxn;
  readonly actor: ShiftActor | null | undefined;
  readonly dogId?: string | null;
  readonly associationIntent: "NO_K9_ASSOCIATION" | "K9_ASSOCIATION_REQUESTED";
  readonly authorityEvidence?: AuthorityEvidenceContract | null;
  readonly acknowledgedRestrictionIds?: readonly string[];
  readonly operationContext?: string | null;
  readonly now?: Date;
}): Promise<K9GuardDecision> {
  return evaluateK9AssociationInTransaction({
    transaction: input.txn,
    trustedActor: input.actor,
    dogId: input.dogId,
    associationIntent: input.associationIntent,
    acknowledgedRestrictionIds: input.acknowledgedRestrictionIds,
    operationContext: input.operationContext,
    currentAuthorityEvidence: input.authorityEvidence,
    now: input.now,
  });
}
