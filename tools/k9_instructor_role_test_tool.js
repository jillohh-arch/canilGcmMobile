#!/usr/bin/env node

const path = require('path');

const DEFAULT_PROJECT_ID = 'canil-gcm';
const ROLE = 'instrutor_k9';
const TOOL_SOURCE = 'tools/k9_instructor_role_test_tool.js';

function usage() {
  return `
Uso:
  node tools/k9_instructor_role_test_tool.js status --ra <RA> [--email <email>] [--project <id>] [--service-account <json>]
  node tools/k9_instructor_role_test_tool.js grant  --ra <RA> [--email <email>] [--project <id>] [--service-account <json>]
  node tools/k9_instructor_role_test_tool.js revoke --ra <RA> [--email <email>] [--project <id>] [--service-account <json>]

Exemplos:
  node tools/k9_instructor_role_test_tool.js grant --ra 691640
  node tools/k9_instructor_role_test_tool.js status --ra 691640
  node tools/k9_instructor_role_test_tool.js revoke --ra 691640

Observacao:
  Este script nao altera logica de producao. Ele escreve dados de teste no Firebase:
  custom claims do Firebase Auth e espelho em users/{ra}.
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
  const command = args.shift();

  if (!command || command === '--help' || command === '-h') {
    return {help: true};
  }

  const options = {
    command,
    project: DEFAULT_PROJECT_ID,
  };

  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    const next = args[index + 1];

    switch (arg) {
      case '--ra':
        options.ra = next;
        index += 1;
        break;
      case '--email':
        options.email = next;
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
      case '--help':
      case '-h':
        options.help = true;
        break;
      default:
        throw new Error(`Argumento desconhecido: ${arg}\n\n${usage()}`);
    }
  }

  if (!['status', 'grant', 'revoke'].includes(command)) {
    throw new Error(`Comando invalido: ${command}\n\n${usage()}`);
  }
  if (!options.ra) {
    throw new Error(`Informe --ra <RA>.\n\n${usage()}`);
  }

  options.ra = String(options.ra).trim();
  if (!options.ra) {
    throw new Error(`RA vazio.\n\n${usage()}`);
  }

  return options;
}

function defaultEmailForRa(ra) {
  return `${String(ra).trim().toLowerCase()}@gcm.com.br`;
}

function cleanString(value) {
  if (typeof value !== 'string') return null;
  const trimmed = value.trim();
  return trimmed ? trimmed : null;
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

async function resolveUser(admin, options) {
  const db = admin.firestore();
  const userRef = db.collection('users').doc(options.ra);
  const userSnap = await userRef.get();
  const userData = userSnap.exists ? userSnap.data() : {};
  const email =
    cleanString(options.email) ||
    cleanString(userData.email) ||
    defaultEmailForRa(options.ra);
  const uid =
    cleanString(userData.auth_uid) ||
    cleanString(userData.authUid) ||
    cleanString(userData.uid);

  let authUser;
  if (uid) {
    authUser = await admin.auth().getUser(uid);
  } else {
    authUser = await admin.auth().getUserByEmail(email);
  }

  return {
    authUser,
    email: authUser.email || email,
    userData,
    userRef,
    userSnap,
  };
}

function grantClaims(existingClaims) {
  const claims = {...(existingClaims || {})};
  const roles = new Set(Array.isArray(claims.roles) ? claims.roles : []);
  roles.add(ROLE);

  return {
    ...claims,
    roles: Array.from(roles).sort(),
    role: ROLE,
    instrutor_k9: true,
    training_role: ROLE,
    training_instructor: true,
  };
}

function revokeClaims(existingClaims) {
  const claims = {...(existingClaims || {})};
  const roles = new Set(Array.isArray(claims.roles) ? claims.roles : []);
  roles.delete(ROLE);

  if (roles.size > 0) {
    claims.roles = Array.from(roles).sort();
  } else {
    delete claims.roles;
  }

  if (claims.role === ROLE) delete claims.role;
  if (claims.training_role === ROLE) delete claims.training_role;
  delete claims.instrutor_k9;
  delete claims.training_instructor;

  return claims;
}

function auditEntry(admin, action, ra, uid) {
  return {
    action,
    at: admin.firestore.Timestamp.now(),
    by: 'local_test_tool',
    source: TOOL_SOURCE,
    target_ra: ra,
    target_uid: uid,
  };
}

async function writeMirror(admin, resolved, options, enabled) {
  const fields = {
    auth_uid: resolved.authUser.uid,
    email: resolved.email,
    is_k9_instructor: enabled,
    training_role: enabled ? ROLE : null,
    claim_role: enabled ? ROLE : null,
    claim_refresh_required: true,
    claim_updated_at: admin.firestore.FieldValue.serverTimestamp(),
    updated_at: admin.firestore.FieldValue.serverTimestamp(),
    audit_trail: admin.firestore.FieldValue.arrayUnion(
      auditEntry(
        admin,
        enabled ? 'test_k9_instructor_role_granted' : 'test_k9_instructor_role_revoked',
        options.ra,
        resolved.authUser.uid,
      ),
    ),
  };

  await resolved.userRef.set(fields, {merge: true});
}

function publicClaimSubset(claims) {
  const source = claims || {};
  return {
    role: source.role || null,
    roles: source.roles || null,
    instrutor_k9: source.instrutor_k9 || null,
    training_role: source.training_role || null,
    training_instructor: source.training_instructor || null,
  };
}

function mirrorSubset(userSnap, userData) {
  if (!userSnap.exists) {
    return {exists: false};
  }
  return {
    exists: true,
    auth_uid: userData.auth_uid || null,
    email: userData.email || null,
    is_k9_instructor: userData.is_k9_instructor || false,
    training_role: userData.training_role || null,
    claim_role: userData.claim_role || null,
    claim_refresh_required: userData.claim_refresh_required || false,
  };
}

async function grant(admin, options) {
  const resolved = await resolveUser(admin, options);
  const nextClaims = grantClaims(resolved.authUser.customClaims);

  await admin.auth().setCustomUserClaims(resolved.authUser.uid, nextClaims);
  await writeMirror(admin, resolved, options, true);

  console.log(`Instrutor K9 concedido para RA ${options.ra}.`);
  console.log(`UID: ${resolved.authUser.uid}`);
  console.log(`Email: ${resolved.email}`);
  console.log('Claims relevantes:', JSON.stringify(publicClaimSubset(nextClaims), null, 2));
  console.log('Importante: faca logout/login no celular do Instrutor K9 para renovar o token.');
}

async function revoke(admin, options) {
  const resolved = await resolveUser(admin, options);
  const nextClaims = revokeClaims(resolved.authUser.customClaims);

  await admin.auth().setCustomUserClaims(resolved.authUser.uid, nextClaims);
  await writeMirror(admin, resolved, options, false);

  console.log(`Instrutor K9 removido do RA ${options.ra}.`);
  console.log(`UID: ${resolved.authUser.uid}`);
  console.log(`Email: ${resolved.email}`);
  console.log('Claims relevantes:', JSON.stringify(publicClaimSubset(nextClaims), null, 2));
  console.log('Importante: faca logout/login no celular para renovar o token sem o papel.');
}

async function status(admin, options) {
  const resolved = await resolveUser(admin, options);

  console.log(`Status do RA ${options.ra}`);
  console.log(`UID: ${resolved.authUser.uid}`);
  console.log(`Email: ${resolved.email}`);
  console.log('Claims relevantes:', JSON.stringify(publicClaimSubset(resolved.authUser.customClaims), null, 2));
  console.log('Espelho users/{ra}:', JSON.stringify(mirrorSubset(resolved.userSnap, resolved.userData), null, 2));
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help) {
    console.log(usage());
    return;
  }

  const admin = loadAdmin();
  initAdmin(admin, options);

  if (options.command === 'grant') {
    await grant(admin, options);
    return;
  }
  if (options.command === 'revoke') {
    await revoke(admin, options);
    return;
  }
  await status(admin, options);
}

main().catch((error) => {
  console.error('\nFalha no ferramental de papel Instrutor K9.');
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
