#!/usr/bin/env node

const path = require('path');

const DEFAULT_PROJECT_ID = 'canil-gcm';

function usage() {
  return `
Uso:
  node tools/training_promotion_smoke_check.js --request <promotionRequestId> [--watch] [--timeout 120] [--interval 5] [--project <id>] [--service-account <json>]

Exemplos:
  node tools/training_promotion_smoke_check.js --request abc123
  node tools/training_promotion_smoke_check.js --request abc123 --watch --timeout 120

O script e read-only. Ele consulta:
  promotion_requests/{id}
  dogs/{dogId}/training/{modality}
  dogs/{dogId}/specialties/*
  notifications/{requesterRa}/items recentes
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
  const args = [...argv];
  const options = {
    project: DEFAULT_PROJECT_ID,
    watch: false,
    timeoutSeconds: 120,
    intervalSeconds: 5,
  };

  if (args.includes('--help') || args.includes('-h')) {
    return {help: true};
  }

  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    const next = args[index + 1];

    switch (arg) {
      case '--request':
      case '--request-id':
        options.requestId = next;
        index += 1;
        break;
      case '--project':
        options.project = next;
        index += 1;
        break;
      case '--service-account':
        options.serviceAccount = next;
        index += 1;
        break;
      case '--watch':
        options.watch = true;
        break;
      case '--timeout':
        options.timeoutSeconds = Number(next);
        index += 1;
        break;
      case '--interval':
        options.intervalSeconds = Number(next);
        index += 1;
        break;
      default:
        throw new Error(`Argumento desconhecido: ${arg}\n\n${usage()}`);
    }
  }

  if (!options.requestId || !String(options.requestId).trim()) {
    throw new Error(`Informe --request <promotionRequestId>.\n\n${usage()}`);
  }
  if (!Number.isFinite(options.timeoutSeconds) || options.timeoutSeconds <= 0) {
    throw new Error('Timeout invalido.');
  }
  if (!Number.isFinite(options.intervalSeconds) || options.intervalSeconds <= 0) {
    throw new Error('Intervalo invalido.');
  }

  options.requestId = String(options.requestId).trim();
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

function stringValue(value) {
  if (typeof value !== 'string') return null;
  const trimmed = value.trim();
  return trimmed ? trimmed : null;
}

function timestampToIso(value) {
  if (!value) return null;
  if (typeof value.toDate === 'function') return value.toDate().toISOString();
  if (value instanceof Date) return value.toISOString();
  return null;
}

function compactTimestamp(value) {
  return timestampToIso(value) || value || null;
}

function summarizeCompletedModule(module) {
  const milestones = Array.isArray(module.milestones) ? module.milestones : [];
  return {
    module_id: module.module_id || null,
    module_name: module.module_name || null,
    program_version: module.program_version || null,
    completed_at: compactTimestamp(module.completed_at),
    completed_by: module.completed_by || null,
    milestones: milestones.map((milestone) => ({
      milestone_id: milestone.milestone_id || null,
      label: milestone.label || null,
      required: milestone.required !== false,
      achieved: milestone.achieved === true,
      achieved_at: compactTimestamp(milestone.achieved_at),
      achieved_by: milestone.achieved_by || null,
    })),
  };
}

function summarizeRequest(data) {
  return {
    status: data.status || null,
    decision: data.decision || null,
    direct_instructor: data.direct_instructor === true,
    processing_status: data.processing_status || null,
    processing_error: data.processing_error || null,
    processed_at: compactTimestamp(data.processed_at),
    dog_id: data.dog_id || null,
    dog_name: data.dog_name || null,
    modality: data.modality || null,
    module_id: data.module_id || null,
    module_name: data.module_name || null,
    program_version: data.program_version || null,
    requester_ra: data.requester_ra || null,
    requester_name: data.requester_name || null,
    requested_at: compactTimestamp(data.requested_at),
    decision_by: data.decision_by || null,
    decision_by_email: data.decision_by_email || null,
    decision_reason: data.decision_reason || null,
    decided_at: compactTimestamp(data.decided_at),
    resulting_status: data.resulting_status || null,
    next_module: data.next_module || null,
    operational: data.operational === true,
  };
}

function summarizeProgress(data) {
  const completedModules = Array.isArray(data.completed_modules)
    ? data.completed_modules
    : [];
  const completedIds = Array.isArray(data.completed_module_ids)
    ? data.completed_module_ids
    : [];
  return {
    status: data.status || null,
    current_module: data.current_module || data.current_module_id || null,
    program_version: data.program_version || null,
    completed_module_ids: completedIds,
    completed_modules_count: completedModules.length,
    last_completed_module: completedModules.length > 0
      ? summarizeCompletedModule(completedModules[completedModules.length - 1])
      : null,
    operational_since: compactTimestamp(data.operational_since),
    updated_at: compactTimestamp(data.updated_at),
  };
}

function summarizeSpecialty(id, data) {
  return {
    id,
    type: data.type || null,
    name: data.name || null,
    status: data.status || data.state || null,
    current_module: data.current_module || data.current_phase || null,
    program_version: data.program_version || null,
    progress_percentage: data.progress_percentage || null,
    operational_since: compactTimestamp(data.operational_since),
    updated_at: compactTimestamp(data.updated_at),
  };
}

function summarizeNotification(id, data) {
  return {
    id,
    type: data.type || null,
    title: data.title || null,
    dog_id: data.dog_id || null,
    module_id: data.module_id || null,
    created_at: compactTimestamp(data.created_at),
    read_at: compactTimestamp(data.read_at),
  };
}

async function loadPromotionState(admin, requestId) {
  const db = admin.firestore();
  const requestRef = db.collection('promotion_requests').doc(requestId);
  const requestSnap = await requestRef.get();
  if (!requestSnap.exists) {
    throw new Error(`promotion_requests/${requestId} nao encontrado.`);
  }

  const request = requestSnap.data() || {};
  const dogId = stringValue(request.dog_id);
  const modality = stringValue(request.modality);
  const requesterRa = stringValue(request.requester_ra);

  let progress = null;
  let specialties = [];
  let notifications = [];

  if (dogId && modality) {
    const progressSnap = await db
      .collection('dogs')
      .doc(dogId)
      .collection('training')
      .doc(modality)
      .get();
    progress = progressSnap.exists ? summarizeProgress(progressSnap.data() || {}) : null;

    const specialtiesById = new Map();
    const specialtyDoc = await db
      .collection('dogs')
      .doc(dogId)
      .collection('specialties')
      .doc(modality)
      .get();
    if (specialtyDoc.exists) {
      specialtiesById.set(specialtyDoc.id, summarizeSpecialty(specialtyDoc.id, specialtyDoc.data() || {}));
    }
    const specialtyQuery = await db
      .collection('dogs')
      .doc(dogId)
      .collection('specialties')
      .where('type', '==', modality)
      .get();
    for (const doc of specialtyQuery.docs) {
      specialtiesById.set(doc.id, summarizeSpecialty(doc.id, doc.data() || {}));
    }
    specialties = Array.from(specialtiesById.values());
  }

  if (requesterRa) {
    const notificationsSnap = await db
      .collection('notifications')
      .doc(requesterRa)
      .collection('items')
      .orderBy('created_at', 'desc')
      .limit(5)
      .get();
    notifications = notificationsSnap.docs.map((doc) =>
      summarizeNotification(doc.id, doc.data() || {}),
    );
  }

  return {
    request_id: requestId,
    request: summarizeRequest(request),
    progress,
    specialties,
    recent_requester_notifications: notifications,
  };
}

function isProcessed(state) {
  const status = state.request.processing_status;
  return status === 'completed' || status === 'error';
}

function printState(state) {
  console.log(JSON.stringify(state, null, 2));
  if (state.request.status === 'approved' && !state.request.processing_status) {
    console.log('\nAprovada, mas ainda sem processing_status: aguarde a Function onTrainingPromotionRequestUpdated.');
  }
  if (state.request.processing_status === 'error') {
    console.log('\nFunction processou com erro. Veja request.processing_error acima.');
  }
  if (state.request.processing_status === 'completed') {
    console.log('\nFunction processou com sucesso.');
  }
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function watch(admin, options) {
  const started = Date.now();
  let lastState = null;
  while (Date.now() - started <= options.timeoutSeconds * 1000) {
    lastState = await loadPromotionState(admin, options.requestId);
    if (isProcessed(lastState)) {
      printState(lastState);
      return;
    }
    console.log(
      `Aguardando Function... status=${lastState.request.status || '-'} processing_status=${lastState.request.processing_status || '-'} elapsed=${Math.round((Date.now() - started) / 1000)}s`,
    );
    await sleep(options.intervalSeconds * 1000);
  }

  if (lastState) printState(lastState);
  throw new Error(`Timeout aguardando processamento da Function (${options.timeoutSeconds}s).`);
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help) {
    console.log(usage());
    return;
  }

  const admin = loadAdmin();
  initAdmin(admin, options);

  if (options.watch) {
    await watch(admin, options);
    return;
  }

  const state = await loadPromotionState(admin, options.requestId);
  printState(state);
}

main().catch((error) => {
  console.error('\nFalha no smoke check de promocao de treino.');
  console.error(error.message || error);
  console.error(
    [
      '',
      'Credenciais esperadas:',
      '- GOOGLE_APPLICATION_CREDENTIALS apontando para um JSON de service account, ou',
      '- --service-account <caminho-do-json>, ou',
      '- Application Default Credentials com permissao de leitura Firestore.',
      '',
      'Este script e read-only, mas consulta dados reais do projeto.',
    ].join('\n'),
  );
  process.exitCode = 1;
});
