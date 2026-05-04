const fs = require('fs');
const path = require('path');

const firebaseAuth = require('C:/npm-global/node_modules/firebase-tools/lib/auth.js');

const PROJECT_ID = 'canil-gcm';
const DATABASE = '(default)';
const COLLECTION = 'occurrence_natures';
const SEED_FILE = path.join(__dirname, 'occurrence_natures_seed.json');

function normalizeForSearch(value) {
  return String(value || '')
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[^a-z0-9]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function firestoreValue(value) {
  if (typeof value === 'boolean') {
    return { booleanValue: value };
  }
  return { stringValue: String(value ?? '') };
}

function natureToWrite(nature) {
  const code = String(nature.code || '').trim();
  const name = String(nature.name || '').trim();
  const group = String(nature.group || '').trim();
  const active = nature.active !== false;
  const searchText = normalizeForSearch(`${code} ${name} ${group}`);

  if (!code || !name) {
    throw new Error(`Natureza inválida no seed: ${JSON.stringify(nature)}`);
  }

  return {
    update: {
      name:
        `projects/${PROJECT_ID}/databases/${DATABASE}/documents/` +
        `${COLLECTION}/${encodeURIComponent(code)}`,
      fields: {
        code: firestoreValue(code),
        name: firestoreValue(name),
        group: firestoreValue(group),
        active: firestoreValue(active),
        searchText: firestoreValue(searchText),
      },
    },
  };
}

async function accessToken() {
  const account = firebaseAuth.getGlobalDefaultAccount();
  const refreshToken = account && account.tokens && account.tokens.refresh_token;
  if (!refreshToken) {
    throw new Error('Firebase CLI não está autenticado. Rode firebase login.');
  }
  const token = await firebaseAuth.getAccessToken(refreshToken, [
    'https://www.googleapis.com/auth/cloud-platform',
  ]);
  if (!token || !token.access_token) {
    throw new Error('Não foi possível obter access token do Firebase CLI.');
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
    body: JSON.stringify({ writes }),
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`Falha no commit Firestore (${response.status}): ${text}`);
  }
}

async function main() {
  const seed = JSON.parse(fs.readFileSync(SEED_FILE, 'utf8'));
  const writes = seed.map(natureToWrite);
  const token = await accessToken();

  await commitBatch(token, writes);
  console.log(`Coleção ${COLLECTION} atualizada com ${writes.length} naturezas.`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
