/**
 * Injectable local handlers for future HealthTimeline Firestore triggers.
 *
 * Gate 5C.5C.2 deliberately does not register onDocumentCreated.
 */
import type {DocumentData} from "firebase-admin/firestore";
import {
  DeterministicInvalidPayloadError,
  TransientInfrastructureError,
  assertSafeDocumentId,
  parseMealLogSource,
  parseSupplementLogSource,
  sourceDocumentPath,
  type HealthTimelineProjector,
  type HealthTimelineSourceType,
  type ProjectionRuntimeResult,
  type RuntimeClock,
  type RuntimeLogger,
  type RuntimeReasonCode,
} from "./health_timeline_runtime";

export type TriggerSnapshotLike = {
  exists: boolean;
  id: string;
  ref: {
    path: string;
  };
  data: () => DocumentData | undefined;
};

export type TriggerHandlerInput = {
  snapshot?: TriggerSnapshotLike;
  params: Record<string, unknown>;
};

export type HealthTimelineAnomaly = {
  sourceType: HealthTimelineSourceType;
  dogId: string | null;
  sourceId: string | null;
  reasonCode: RuntimeReasonCode;
  occurredAt: Date;
  context: Record<string, unknown>;
};

export type HealthTimelineAnomalySink = {
  record: (anomaly: HealthTimelineAnomaly) => Promise<void>;
};

export type TriggerHandlerResult =
  | {
    status: "projected";
    projection: ProjectionRuntimeResult;
  }
  | {
    status: "anomaly";
    reasonCode: RuntimeReasonCode;
  };

export type TriggerHandlerDependencies = {
  projector: HealthTimelineProjector;
  anomalySink: HealthTimelineAnomalySink;
  clock: RuntimeClock;
  logger: RuntimeLogger;
};

type HandlerDefinition = {
  sourceType: HealthTimelineSourceType;
  sourceParam: "mealId" | "supplementLogId";
};

function safeIdentifier(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const normalized = value.trim();
  if (normalized.length === 0) return null;
  return normalized.slice(0, 128);
}

function sourceData(
  definition: HandlerDefinition,
  raw: DocumentData,
  dogId: string,
  sourceId: string,
) {
  return definition.sourceType === "meal" ?
    {
      sourceType: "meal" as const,
      dogId,
      sourceId,
      data: parseMealLogSource(raw, dogId, sourceId),
    } :
    {
      sourceType: "supplement" as const,
      dogId,
      sourceId,
      data: parseSupplementLogSource(raw, dogId, sourceId),
    };
}

function pathMismatchReason(
  actualPath: string,
  expectedDogId: string,
): RuntimeReasonCode {
  const segments = actualPath.split("/");
  if (segments.length >= 2 && segments[0] === "dogs" &&
      segments[1] !== expectedDogId) {
    return "cross-dog-source";
  }
  return "invalid-source-path";
}

function makeCreatedHandler(
  definition: HandlerDefinition,
  dependencies: TriggerHandlerDependencies,
) {
  return async (
    input: TriggerHandlerInput,
  ): Promise<TriggerHandlerResult> => {
    const rawDogId = input.params.dogId;
    const rawSourceId = input.params[definition.sourceParam];
    const anomalyBase = {
      sourceType: definition.sourceType,
      dogId: safeIdentifier(rawDogId),
      sourceId: safeIdentifier(rawSourceId),
    };

    if (!input.snapshot || !input.snapshot.exists) {
      const error = new TransientInfrastructureError(
        "Created-event snapshot ausente.",
      );
      dependencies.logger.error("HealthTimeline transient trigger failure", {
        ...anomalyBase,
        errorName: error.name,
      });
      throw error;
    }

    try {
      const dogId = assertSafeDocumentId(rawDogId, "dog");
      const sourceId = assertSafeDocumentId(rawSourceId, "source");
      const expectedPath = sourceDocumentPath(
        definition.sourceType,
        dogId,
        sourceId,
      );
      const actualPath = input.snapshot.ref.path;
      if (actualPath !== expectedPath || input.snapshot.id !== sourceId) {
        const reasonCode = pathMismatchReason(actualPath, dogId);
        throw new DeterministicInvalidPayloadError(
          reasonCode,
          "Snapshot ref/params não correspondem ao source type esperado.",
          {
            expectedCollection: definition.sourceType,
            actualSegmentCount: actualPath.split("/").length,
          },
        );
      }

      const raw = input.snapshot.data();
      if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
        throw new DeterministicInvalidPayloadError(
          "malformed-payload",
          "Snapshot não contém payload de documento.",
        );
      }

      const projection = await dependencies.projector.project(
        sourceData(definition, raw, dogId, sourceId),
      );
      return {status: "projected", projection};
    } catch (error) {
      if (error instanceof DeterministicInvalidPayloadError) {
        const anomaly: HealthTimelineAnomaly = {
          ...anomalyBase,
          reasonCode: error.reasonCode,
          occurredAt: dependencies.clock.now(),
          context: {
            handler: definition.sourceType,
            ...error.safeContext,
          },
        };
        dependencies.logger.warn("HealthTimeline deterministic anomaly", {
          ...anomalyBase,
          reasonCode: error.reasonCode,
        });
        try {
          await dependencies.anomalySink.record(anomaly);
        } catch (sinkError) {
          dependencies.logger.error("HealthTimeline anomaly sink failure", {
            ...anomalyBase,
            reasonCode: error.reasonCode,
            errorName: sinkError instanceof Error ?
              sinkError.name :
              "UnknownError",
          });
          throw sinkError;
        }
        return {status: "anomaly", reasonCode: error.reasonCode};
      }

      dependencies.logger.error("HealthTimeline transient runtime failure", {
        ...anomalyBase,
        errorName: error instanceof Error ? error.name : "UnknownError",
      });
      throw error;
    }
  };
}

export function makeMealLogCreatedHandler(
  dependencies: TriggerHandlerDependencies,
) {
  return makeCreatedHandler(
    {sourceType: "meal", sourceParam: "mealId"},
    dependencies,
  );
}

export function makeSupplementLogCreatedHandler(
  dependencies: TriggerHandlerDependencies,
) {
  return makeCreatedHandler(
    {sourceType: "supplement", sourceParam: "supplementLogId"},
    dependencies,
  );
}
