#!/usr/bin/env node

const path = require('path');

const DEFAULT_PROJECT_ID = 'canil-gcm';
const ROLE = 'instrutor_k9';
const TOOL_SOURCE = 'tools/set_k9_instructor.js';

function usage() {
  return `
Uso:
  node tools/set_k9_instructor.js --ra <RA> [--service-account <json>]
  node tools/set_k9_instructor.js --email <email> [--service-account <json>]
  node tools/set_k9_instructor.js --uid <uid> [--service-account <json>]

O comando acima concede o papel Instrutor K9.

Opcoes:
  --remove              Remove o papel Instrutor K9.
  --project <id>        Projeto Firebase. Padrao: canil-gcm.
  --service-account     Caminho para JSON de service account.

Exemplos:
  node tools/set_k9_instructor.js --ra 691640
  node tools/set_k9_instructor.js --email 691640@gcm.com.br
  node tools/set_k9_instructor.js --uid abcFirebaseUid123
  node tools/set_k9_instructor.js --ra 691640 --remove

Este script e ferramental de teste. Ele nao altera app, rules ou Functions,
mas grava custom claims no Auth e espelha o papel em users/{ra}.
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
    enabled: true,
    project: DEFAULT_PROJECT_ID,
  };

  if (argv.length === 0 || argv.includes('--help') || argv.includes('-h')) {
    return {help: true};
  }

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    const next = argv[index + 1];
    switch (arg) {
      case '--ra':
        options.ra = cleanString(next);
        index += 1;
        break;
      case '--email':
        options.email = cleanString(next)?.toLowerCase();
        index += 1;
        break;
      case '--uid':
        options.uid = cleanString(next);
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
      case '--remove':
      case '--revoke':
      case '--disable':
        options.enabled = false;
        break;
      default:
        throw new Error(`Argumento desconhecido: ${arg}\n\n${usage()}`);
    }
  }

  const identifiers = [options.ra, options.email, options.uid].filter(Boolean);
  if (identifiers.length !== 1) {
    throw new Error(
      `Informe exatamente um identificador: --ra, --email ou --uid.\n\n${usage()}`,
    );
  }

  return options;
}

function cleanString(value) {
  if (typeof value !== 'string') return null;
  const trimmed = value.trim();
  return trimmed ? trimmed : null;
}

function emailForRa(ra) {
  return `${String(ra).trim().toLowerCase()}@gcm.com.br`;
}

function raFromEmail(email) {
  const normalized = cleanString(email)?.toLowerCase();
  if (!normalized) return null;
  if (normalized.endsWith('@gcm.com.br')) {
    return normalized.replace('@gcm.com.br', '');
  }
  if (normalized.endsWith('@canilgcm.com')) {
    return normalized.replace('@canilgcm.com', '');
  }
  return null;
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

async function firstUserDocBy(db, field, value) {
  if (!value) return null;
  const snapshot = await db.collection('users').where(field, '==', value).limit(1).get();
  if (snapshot.empty) return null;
  return snapshot.docs[0];
}

async function resolveUserDocByAuthUser(db, authUser) {
  const uid = authUser.uid;
  const email = cleanString(authUser.email)?.toLowerCase();
  const candidates = [
    await firstUserDocBy(db, 'auth_uid', uid),
    await firstUserDocBy(db, 'authUid', uid),
    await firstUserDocBy(db, 'uid', uid),
    await firstUserDocBy(db, 'email', email),
  ].filter(Boolean);
  if (candidates.length > 0) return candidates[0];

  const ra = raFromEmail(email);
  if (!ra) return null;
  const snap = await db.collection('users').doc(ra).get();
  return snap.exists ? snap : null;
}

async function resolveTarget(admin, options) {
  const db = admin.firestore();
  let authUser;
  let userSnap;
  let ra = options.ra;

  if (options.ra) {
    const userRef = db.collection('users').doc(options.ra);
    userSnap = await userRef.get();
    if (!userSnap.exists) {
      throw new Error(
        `users/${options.ra} nao existe. Crie/sincronize o usuario antes, como o callable setK9InstructorRole exige.`,
      );
    }

    const userData = userSnap.data() || {};
    const uid =
      cleanString(userData.auth_uid) ||
      cleanString(userData.authUid) ||
      cleanString(userData.uid);
    const email =
      cleanString(userData.email)?.toLowerCase() ||
      emailForRa(options.ra);

    authUser = uid
      ? await admin.auth().getUser(uid)
      : await admin.auth().getUserByEmail(email);
  } else {
    authUser = options.uid
      ? await admin.auth().getUser(options.uid)
      : await admin.auth().getUserByEmail(options.email);
    userSnap = await resolveUserDocByAuthUser(db, authUser);
    if (!userSnap || !userSnap.exists) {
      throw new Error(
        'Nao encontrei users/{ra} correspondente ao e-mail/UID informado. ' +
          'Passe --ra de um usuario existente ou sincronize o cadastro antes.',
      );
    }
    ra = userSnap.id;
  }

  const userData = userSnap.data() || {};
  const email =
    cleanString(authUser.email)?.toLowerCase() ||
    cleanString(userData.email)?.toLowerCase() ||
    emailForRa(ra);

  return {
    authUser,
    email,
    ra,
    userData,
    userRef: userSnap.ref,
  };
}

function nextClaimsLikeCallable(existingClaims, enabled) {
  const source = existingClaims || {};
  const roles = new Set(Array.isArray(source.roles) ? source.roles.map(String) : []);
  if (enabled) {
    roles.add(ROLE);
  } else {
    roles.delete(ROLE);
  }

  const nextClaims = {
    ...source,
    roles: Array.from(roles),
  };

  if (enabled) {
    nextClaims.role = ROLE;
    nextClaims.instrutor_k9 = true;
    nextClaims.training_role = ROLE;
    nextClaims.training_instructor = true;
  } else {
    delete nextClaims.instrutor_k9;
    delete nextClaims.training_role;
    delete nextClaims.training_instructor;
    if (nextClaims.role === ROLE) delete nextClaims.role;
  }

  return nextClaims;
}

function relevantClaimsAreSet(claims, enabled) {
  const roles = Array.isArray(claims?.roles) ? claims.roles.map(String) : [];
  if (enabled) {
    return (
      roles.includes(ROLE) &&
      claims.role === ROLE &&
      claims.instrutor_k9 === true &&
      claims.training_role === ROLE &&
      claims.training_instructor === true
    );
  }
  return (
    !roles.includes(ROLE) &&
    claims?.role !== ROLE &&
    claims?.instrutor_k9 !== true &&
    claims?.training_role !== ROLE &&
    claims?.training_instructor !== true
  );
}

function relevantMirrorIsSet(target, enabled) {
  const data = target.userData || {};
  if (data.auth_uid !== target.authUser.uid) return false;
  if (cleanString(data.email)?.toLowerCase() !== target.email) return false;
  if (enabled) {
    return (
      data.is_k9_instructor === true &&
      data.training_role === ROLE &&
      data.claim_role === ROLE
    );
  }
  return (
    data.is_k9_instructor === false &&
    (data.training_role === null || data.training_role === undefined) &&
    (data.claim_role === null || data.claim_role === undefined)
  );
}

function auditEntry(admin, action, target) {
  const now = admin.firestore.Timestamp.now();
  return {
    action,
    at: now,
    by: 'local_test_tool',
    by_name: TOOL_SOURCE,
    by_ra: 'local_test_tool',
    performed_by: 'local_test_tool',
    performed_at: now.toDate().toISOString(),
    target_ra: target.ra,
    target_uid: target.authUser.uid,
  };
}

function mirrorPayload(admin, target, enabled) {
  return {
    auth_uid: target.authUser.uid,
    email: target.email,
    is_k9_instructor: enabled,
    training_role: enabled ? ROLE : null,
    claim_role: enabled ? ROLE : null,
    claim_refresh_required: true,
    claim_updated_at: admin.firestore.FieldValue.serverTimestamp(),
    updated_at: admin.firestore.FieldValue.serverTimestamp(),
    audit_trail: admin.firestore.FieldValue.arrayUnion(
      auditEntry(
        admin,
        enabled ? 'k9_instructor_role_granted' : 'k9_instructor_role_revoked',
        target,
      ),
    ),
  };
}

function claimSummary(claims) {
  const source = claims || {};
  return {
    role: source.role || null,
    roles: source.roles || [],
    instrutor_k9: source.instrutor_k9 === true,
    training_role: source.training_role || null,
    training_instructor: source.training_instructor === true,
  };
}

function mirrorSummary(data) {
  const source = data || {};
  return {
    auth_uid: source.auth_uid || null,
    email: source.email || null,
    is_k9_instructor: source.is_k9_instructor === true,
    training_role: source.training_role || null,
    claim_role: source.claim_role || null,
    claim_refresh_required: source.claim_refresh_required === true,
  };
}

async function applyRole(admin, options) {
  const target = await resolveTarget(admin, options);
  const beforeClaims = target.authUser.customClaims || {};
  const beforeMirror = mirrorSummary(target.userData);
  const needsAuthUpdate = !relevantClaimsAreSet(beforeClaims, options.enabled);
  const needsMirrorUpdate = !relevantMirrorIsSet(target, options.enabled);
  const nextClaims = nextClaimsLikeCallable(beforeClaims, options.enabled);

  if (needsAuthUpdate) {
    await admin.auth().setCustomUserClaims(target.authUser.uid, nextClaims);
  }

  if (needsMirrorUpdate) {
    await target.userRef.set(mirrorPayload(admin, target, options.enabled), {merge: true});
  }

  const afterUserSnap = await target.userRef.get();

  return {
    project: options.project || DEFAULT_PROJECT_ID,
    action: options.enabled ? 'grant_instrutor_k9' : 'remove_instrutor_k9',
    changed_auth_claims: needsAuthUpdate,
    changed_user_mirror: needsMirrorUpdate,
    token_refresh_required: needsAuthUpdate,
    ra: target.ra,
    uid: target.authUser.uid,
    email: target.email,
    custom_claims_before: claimSummary(beforeClaims),
    custom_claims_after: claimSummary(nextClaims),
    user_mirror_before: beforeMirror,
    user_mirror_after: mirrorSummary(afterUserSnap.data() || {}),
    note: needsAuthUpdate
      ? 'O app precisa renovar o ID token. Para teste limpo, faca logout/login no aparelho.'
      : 'Claims ja estavam no estado esperado; se o aparelho ainda nao reconhece, faca logout/login.',
  };
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help) {
    console.log(usage());
    return;
  }

  const admin = loadAdmin();
  initAdmin(admin, options);

  const result = await applyRole(admin, options);
  console.log(JSON.stringify(result, null, 2));
}

main().catch((error) => {
  console.error('\nFalha ao setar Instrutor K9.');
  console.error(error.message || error);
  console.error(
    [
      '',
      'Credenciais esperadas:',
      '- GOOGLE_APPLICATION_CREDENTIALS apontando para um JSON de service account, ou',
      '- --service-account <caminho-do-json>, ou',
      '- Application Default Credentials com permissao Firebase Admin/Auth.',
      '',
      'Nao committe JSON de service account.',
    ].join('\n'),
  );
  process.exitCode = 1;
});
