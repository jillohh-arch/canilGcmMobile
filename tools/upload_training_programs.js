const fs = require('fs');
const path = require('path');

const firebaseAuth = require('C:/npm-global/node_modules/firebase-tools/lib/auth.js');

const PROJECT_ID = 'canil-gcm';
const DATABASE = '(default)';
const COLLECTION = 'training_programs';
const requestedSeed = process.argv[2];
const SEED_FILE = requestedSeed
  ? path.resolve(process.cwd(), requestedSeed)
  : path.join(__dirname, 'training_programs_busca_captura_seed.json');

function firestoreValue(value) {
  if (value === null || value === undefined) return {nullValue: null};
  if (typeof value === 'boolean') return {booleanValue: value};
  if (Number.isInteger(value)) return {integerValue: String(value)};
  if (typeof value === 'number') return {doubleValue: value};
  if (Array.isArray(value)) {
    return {arrayValue: {values: value.map(firestoreValue)}};
  }
  if (typeof value === 'object') {
    return {
      mapValue: {
        fields: Object.fromEntries(
          Object.entries(value).map(([key, item]) => [key, firestoreValue(item)]),
        ),
      },
    };
  }
  return {stringValue: String(value)};
}

function fieldsFrom(data) {
  return Object.fromEntries(
    Object.entries(data).map(([key, value]) => [key, firestoreValue(value)]),
  );
}

function validateProgram(seed) {
  const program = seed.program || {};
  const modules = Array.isArray(seed.modules) ? seed.modules : [];

  if (!program.id || !program.name || !program.modality) {
    throw new Error('Seed de curriculum invalido: program.id/name/modality obrigatorios.');
  }
  if (program.id !== program.modality) {
    throw new Error('Seed de curriculum invalido: program.id deve ser igual a modality.');
  }
  if (modules.length === 0) {
    throw new Error('Seed de curriculum invalido: informe ao menos um modulo.');
  }

  for (const module of modules) {
    if (!module.id || !module.name || !Number.isInteger(module.order)) {
      throw new Error(`Modulo invalido no seed: ${JSON.stringify(module)}`);
    }
    if (!Array.isArray(module.milestones) || module.milestones.length === 0) {
      throw new Error(`Modulo sem marcos no seed: ${module.id}`);
    }
    for (const milestone of module.milestones) {
      if (!milestone.id || !milestone.label || !Number.isInteger(milestone.order)) {
        throw new Error(`Marco invalido no seed: ${JSON.stringify(milestone)}`);
      }
    }
  }
}

function docName(...segments) {
  return (
    `projects/${PROJECT_ID}/databases/${DATABASE}/documents/` +
    segments.map(encodeURIComponent).join('/')
  );
}

function buildWrites(seed) {
  validateProgram(seed);
  const writes = [];
  const now = new Date().toISOString();
  const program = seed.program;
  const programId = program.id;

  writes.push({
    update: {
      name: docName(COLLECTION, programId),
      fields: fieldsFrom({
        ...program,
        seeded_at: now,
      }),
    },
  });

  for (const module of seed.modules) {
    const {milestones, ...moduleData} = module;
    writes.push({
      update: {
        name: docName(COLLECTION, programId, 'modules', module.id),
        fields: fieldsFrom({
          ...moduleData,
          program_id: programId,
          modality: program.modality,
          seeded_at: now,
        }),
      },
    });

    for (const milestone of milestones) {
      writes.push({
        update: {
          name: docName(
            COLLECTION,
            programId,
            'modules',
            module.id,
            'milestones',
            milestone.id,
          ),
          fields: fieldsFrom({
            ...milestone,
            program_id: programId,
            module_id: module.id,
            modality: program.modality,
            seeded_at: now,
          }),
        },
      });
    }
  }

  return writes;
}

async function accessToken() {
  const account = firebaseAuth.getGlobalDefaultAccount();
  const refreshToken = account && account.tokens && account.tokens.refresh_token;
  if (!refreshToken) {
    throw new Error('Firebase CLI nao esta autenticado. Rode firebase login.');
  }
  const token = await firebaseAuth.getAccessToken(refreshToken, [
    'https://www.googleapis.com/auth/cloud-platform',
  ]);
  if (!token || !token.access_token) {
    throw new Error('Nao foi possivel obter access token do Firebase CLI.');
  }
  return token.access_token;
}

async function commitBatch(token, writes) {
  const url =
    `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/` +
    `${DATABASE}/documents:commit`;
  const response = await fetch(url, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({writes}),
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`Falha no commit Firestore (${response.status}): ${text}`);
  }
}

async function main() {
  const seed = JSON.parse(fs.readFileSync(SEED_FILE, 'utf8'));
  const writes = buildWrites(seed);
  const token = await accessToken();

  await commitBatch(token, writes);
  console.log(
    `Curriculo ${seed.program.id} atualizado em ${COLLECTION} com ${writes.length} documentos.`,
  );
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
