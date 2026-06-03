#!/usr/bin/env node

const path = require('path');

const DEFAULT_PROJECT_ID = 'canil-gcm';
const ACTION_TYPES = new Set([
  'vehicle_crew_invitation',
  'signature_requested',
  'training_promotion_requested',
]);

function usage() {
  return `
Uso:
  node tools/backfill_notification_resolution.js [--apply] [--ra <RA>] [--limit <n>] [--service-account <json>]

Padrao: dry-run. Use --apply para gravar.

O que corrige:
  - action_required=true em avisos historicos vira false.
  - action_required ausente/false em pendencia real vira true.
  - pendencia real cuja acao ja aconteceu recebe resolved_at/read_at.

Exemplos:
  node tools/backfill_notification_resolution.js --service-account "C:\\tmp\\canil-gcm-firebase-admin.json"
  node tools/backfill_notification_resolution.js --apply --service-account "C:\\tmp\\canil-gcm-firebase-admin.json"
  node tools/backfill_notification_resolution.js --ra 691755 --limit 50 --apply --service-account "C:\\tmp\\canil-gcm-firebase-admin.json"

Nao deleta notificacoes. Limpeza visual e por archived_at em etapa propria.
`.trim();
}

function loadAdmin() {
  const adminPath = path.join(
    __dirname,
    '..',
    'functions',
    'node_modules',
    'firebase-admin',
  );
  try {
    return require(adminPath);
  } catch (error) {
    throw new Error(
      [
        'Nao consegui carregar firebase-admin a partir de functions/node_modules.',
        'Rode "npm install" dentro da pasta functions ou use um ambiente onde as Functions ja foram instaladas.',
        `Detalhe: ${error.message}`,
      ].join('\n'),
    );
  }
}

function parseArgs(argv) {
  const options = {
    apply: false,
    project: DEFAULT_PROJECT_ID,
    limit: Number.POSITIVE_INFINITY,
  };

  if (argv.includes('--help') || argv.includes('-h')) {
    return {help: true};
  }

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    const next = argv[index + 1];
    switch (arg) {
      case '--apply':
        options.apply = true;
        break;
      case '--ra':
      case '--user':
        options.ra = cleanString(next);
        index += 1;
        break;
      case '--limit':
        options.limit = Number(next);
        index += 1;
        break;
      case '--project':
        options.project = cleanString(next) || DEFAULT_PROJECT_ID;
        index += 1;
        break;
      case '--service-account':
        options.serviceAccount = cleanString(next);
        index += 1;
        break;
      default:
        throw new Error(`Argumento desconhecido: ${arg}\n\n${usage()}`);
    }
  }

  if (
    options.limit !== Number.POSITIVE_INFINITY &&
    (!Number.isFinite(options.limit) || options.limit <= 0)
  ) {
    throw new Error('Limit invalido.');
  }
  return options;
}

function initAdmin(admin, options) {
  const appOptions = {
    projectId: options.project || DEFAULT_PROJECT_ID,
  };

  if (options.serviceAccount) {
    const serviceAccountPath = path.resolve(options.serviceAccount);
    appOptions.credential = admin.credential.cert(require(serviceAccountPath));
  }

  if (admin.apps.length === 0) {
    admin.initializeApp(appOptions);
  }
}

function cleanString(value) {
  if (typeof value !== 'string') return null;
  const trimmed = value.trim();
  return trimmed ? trimmed : null;
}

function stringValue(value) {
  if (value === null || value === undefined) return null;
  const text = String(value).trim();
  return text ? text : null;
}

function statusValue(value) {
  return stringValue(value)?.toLowerCase() || '';
}

function arrayValue(value) {
  return Array.isArray(value) ? value : [];
}

function serverTimestamp(admin) {
  return admin.firestore.FieldValue.serverTimestamp();
}

function hasTimestamp(value) {
  return value !== null && value !== undefined;
}

async function vehicleInvitationResolution(db, userId, data) {
  const crewId =
    stringValue(data.additional_data) ||
    stringValue(data.crew_id) ||
    stringValue(data.vehicle_crew_id);
  if (!crewId) {
    return {
      resolved: true,
      action: 'vehicle_crew_invitation_missing_reference',
      metadata: {reason: 'missing_crew_id'},
    };
  }

  const memberSnap = await db
    .collection('vehicle_crews')
    .doc(crewId)
    .collection('members')
    .doc(userId)
    .get();
  if (!memberSnap.exists) {
    return {
      resolved: true,
      action: 'vehicle_crew_invitation_missing_member',
      metadata: {crew_id: crewId},
    };
  }

  const member = memberSnap.data() || {};
  const status = statusValue(member.status);
  if (status && status !== 'pending') {
    return {
      resolved: true,
      action: `vehicle_crew_invitation_${status}`,
      metadata: {crew_id: crewId, member_status: status},
    };
  }
  return {resolved: false};
}

async function signatureResolution(db, userId, data) {
  const occurrenceId = stringValue(data.occurrence_id);
  const handlerId = stringValue(data.additional_data) || userId;
  if (!occurrenceId) {
    return {
      resolved: true,
      action: 'signature_requested_missing_reference',
      metadata: {reason: 'missing_occurrence_id', handler_id: handlerId},
    };
  }

  const occurrenceSnap = await db.collection('occurrences').doc(occurrenceId).get();
  if (!occurrenceSnap.exists) {
    return {
      resolved: true,
      action: 'signature_requested_missing_occurrence',
      metadata: {occurrence_id: occurrenceId, handler_id: handlerId},
    };
  }

  const occurrence = occurrenceSnap.data() || {};
  const occurrenceStatus = statusValue(occurrence.status);
  if (occurrenceStatus !== 'awaiting_signatures') {
    return {
      resolved: true,
      action: 'signature_requested_occurrence_left_signature_flow',
      metadata: {occurrence_id: occurrenceId, handler_id: handlerId, occurrence_status: occurrenceStatus},
    };
  }

  const signedHandlerIds = arrayValue(occurrence.signed_handler_ids).map(String);
  if (signedHandlerIds.includes(handlerId)) {
    return {
      resolved: true,
      action: 'signature_added',
      metadata: {occurrence_id: occurrenceId, handler_id: handlerId},
    };
  }

  const round = Number(occurrence.signature_round || 1);
  const signatureIds = [
    handlerId,
    Number.isFinite(round) && round > 1 ? `round_${round}_${handlerId}` : null,
  ].filter(Boolean);
  const signatureSnaps = await Promise.all(
    signatureIds.map((id) =>
      db.collection('occurrences').doc(occurrenceId).collection('signatures').doc(id).get(),
    ),
  );
  for (const signatureSnap of signatureSnaps) {
    if (!signatureSnap.exists) continue;
    const signature = signatureSnap.data() || {};
    const signatureStatus = statusValue(signature.status);
    if (['signed', 'obsolete', 'expired'].includes(signatureStatus)) {
      return {
        resolved: true,
        action: `signature_${signatureStatus}`,
        metadata: {occurrence_id: occurrenceId, handler_id: handlerId, signature_status: signatureStatus},
      };
    }
  }

  const team = arrayValue(occurrence.team);
  if (team.length > 0) {
    const stillInTeam = team.some((member) => {
      if (!member || typeof member !== 'object') return false;
      return stringValue(member.handler_id) === handlerId ||
        stringValue(member.handlerId) === handlerId;
    });
    if (!stillInTeam) {
      return {
        resolved: true,
        action: 'signature_requested_handler_not_in_team',
        metadata: {occurrence_id: occurrenceId, handler_id: handlerId},
      };
    }
  }

  return {resolved: false};
}

async function trainingPromotionResolution(db, data) {
  const requestId =
    stringValue(data.promotion_request_id) ||
    stringValue(data.additional_data);
  if (!requestId) {
    return {
      resolved: true,
      action: 'training_promotion_missing_reference',
      metadata: {reason: 'missing_request_id'},
    };
  }

  const requestSnap = await db.collection('promotion_requests').doc(requestId).get();
  if (!requestSnap.exists) {
    return {
      resolved: true,
      action: 'training_promotion_missing_request',
      metadata: {request_id: requestId},
    };
  }

  const request = requestSnap.data() || {};
  const status = statusValue(request.status);
  if (status && status !== 'pending') {
    return {
      resolved: true,
      action: `training_promotion_${status}`,
      metadata: {
        request_id: requestId,
        status,
        processing_status: stringValue(request.processing_status),
      },
    };
  }
  return {resolved: false};
}

async function resolutionForAction(db, userId, data) {
  const type = stringValue(data.type);
  switch (type) {
    case 'vehicle_crew_invitation':
      return vehicleInvitationResolution(db, userId, data);
    case 'signature_requested':
      return signatureResolution(db, userId, data);
    case 'training_promotion_requested':
      return trainingPromotionResolution(db, data);
    default:
      return {resolved: false};
  }
}

async function updateForNotification(admin, db, userId, data) {
  const type = stringValue(data.type);
  const update = {};
  const reasons = [];

  if (!type) return {update, reasons};

  const isActionType = ACTION_TYPES.has(type);
  if (!isActionType) {
    if (data.action_required === true) {
      update.action_required = false;
      reasons.push('notice_type_not_actionable');
    }
    return {update, reasons};
  }

  if (data.action_required !== true) {
    update.action_required = true;
    reasons.push('action_type_marked_action_required');
  }

  if (hasTimestamp(data.resolved_at)) {
    return {update, reasons};
  }

  const resolution = await resolutionForAction(db, userId, data);
  if (resolution.resolved) {
    update.resolved_at = serverTimestamp(admin);
    if (!hasTimestamp(data.read_at)) {
      update.read_at = serverTimestamp(admin);
    }
    update.resolution_source = 'backfill';
    update.resolution_action = resolution.action;
    update.resolution_metadata = resolution.metadata || {};
    reasons.push('action_already_resolved');
  }

  return {update, reasons};
}

function hasUpdate(update) {
  return Object.keys(update).length > 0;
}

async function commitIfNeeded(state, force = false) {
  if (state.pendingWrites === 0) return;
  if (!force && state.pendingWrites < 450) return;
  await state.batch.commit();
  state.batch = state.db.batch();
  state.pendingWrites = 0;
}

async function run() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help) {
    console.log(usage());
    return;
  }

  const admin = loadAdmin();
  initAdmin(admin, options);
  const db = admin.firestore();
  const notificationUsers = options.ra
    ? [db.collection('notifications').doc(options.ra)]
    : await db.collection('notifications').listDocuments();

  const state = {
    db,
    batch: db.batch(),
    pendingWrites: 0,
  };
  const summary = {
    project: options.project,
    mode: options.apply ? 'apply' : 'dry-run',
    users_scanned: 0,
    notifications_scanned: 0,
    notifications_to_update: 0,
    notifications_updated: 0,
    by_reason: {},
    samples: [],
  };

  for (const userRef of notificationUsers) {
    if (summary.notifications_scanned >= options.limit) break;
    summary.users_scanned += 1;
    const userId = userRef.id;
    const snapshot = await userRef.collection('items').get();
    for (const doc of snapshot.docs) {
      if (summary.notifications_scanned >= options.limit) break;
      summary.notifications_scanned += 1;
      const data = doc.data() || {};
      const {update, reasons} = await updateForNotification(admin, db, userId, data);
      if (!hasUpdate(update)) continue;

      summary.notifications_to_update += 1;
      for (const reason of reasons) {
        summary.by_reason[reason] = (summary.by_reason[reason] || 0) + 1;
      }
      if (summary.samples.length < 20) {
        summary.samples.push({
          path: doc.ref.path,
          type: data.type || null,
          reasons,
        });
      }
      if (options.apply) {
        state.batch.set(doc.ref, update, {merge: true});
        state.pendingWrites += 1;
        summary.notifications_updated += 1;
        await commitIfNeeded(state);
      }
    }
  }

  if (options.apply) {
    await commitIfNeeded(state, true);
  }

  console.log(JSON.stringify(summary, null, 2));
}

run().catch((error) => {
  console.error('Falha no backfill de notificacoes.');
  console.error(error?.stack || error?.message || error);
  console.error('\n' + usage());
  process.exitCode = 1;
});
