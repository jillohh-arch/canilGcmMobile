/**
 * Testes do contrato de adminPatchHumanPhoto (atualizacao de foto de pessoal).
 *
 * Usa o runner nativo do Node (node:test). Exercita:
 *  - Autorizacao previa
 *  - Validacao estrita de payload (fail-closed, allowlist de chaves)
 *  - Recusa de campos de outros dominios (pessoal, acesso, auth, turno)
 *  - Validacao de formato de RA e URL segura
 *  - Condicoes de existencia e integridade (nao encontrado, arquivado)
 *  - Escrita canonica dos espelhos de foto, timestamps e trilha de auditoria
 */

import * as assert from "node:assert/strict";
import {test} from "node:test";
import {HttpsError} from "firebase-functions/v2/https";

import {
  HumanPhotoTransaction,
  patchHumanPhoto,
  PatchHumanPhotoCaller,
  PatchHumanPhotoDeps,
} from "../src/admin_patch_human_photo";

type JsonMap = Record<string, unknown>;

const CALLER: PatchHumanPhotoCaller = {
  uid: "uid-admin",
  email: "admin@gcm.com.br",
  ra: "1234",
  name: "Admin Teste",
};

const SERVER_TIMESTAMP = Symbol("serverTimestamp");
const VALID_PHOTO_URL =
  "https://firebasestorage.googleapis.com/v0/b/k9-test.appspot.com/o/profile_photos%2Fhuman-9001-1700000000000.jpg?alt=media";

interface Recorded {
  authorizeCalls: number;
  patches: Array<{ra: string; patch: JsonMap}>;
  auditEntries: Array<{action: string; caller: PatchHumanPhotoCaller}>;
  transactions: number;
}

interface HarnessOptions {
  authorizeError?: HttpsError;
  user?: JsonMap | null;
}

function existingUser(overrides: JsonMap = {}): JsonMap {
  return {
    ra: "9001",
    name: "Joao da Silva",
    active: true,
    created_at: "CREATED_AT",
    updated_at: 1_700_000_000_000,
    ...overrides,
  };
}

function harness(options: HarnessOptions = {}): {
  deps: PatchHumanPhotoDeps;
  recorded: Recorded;
} {
  const recorded: Recorded = {
    authorizeCalls: 0,
    patches: [],
    auditEntries: [],
    transactions: 0,
  };
  const user = options.user === undefined ? existingUser() : options.user;

  const deps: PatchHumanPhotoDeps = {
    authorize: async () => {
      recorded.authorizeCalls += 1;
      if (options.authorizeError) throw options.authorizeError;
      return CALLER;
    },
    runTransaction: async (handler) => {
      recorded.transactions += 1;
      const tx: HumanPhotoTransaction = {
        getUser: async () => ({exists: user !== null, data: user}),
        patchUser: (ra, patch) => {
          recorded.patches.push({ra, patch});
        },
      };
      return handler(tx);
    },
    serverTimestamp: () => SERVER_TIMESTAMP,
    auditEntry: (action, caller) => {
      recorded.auditEntries.push({action, caller});
      return {action, by: caller.uid, by_ra: caller.ra};
    },
    arrayUnion: (value) => ({__arrayUnion: value}),
  };

  return {deps, recorded};
}

test("atualiza foto com sucesso e grava espelhos canonicos e auditoria", async () => {
  const {deps, recorded} = harness();
  const result = await patchHumanPhoto(deps, {
    ra: "9001",
    photoUrl: VALID_PHOTO_URL,
  });

  assert.equal(result.ra, "9001");
  assert.equal(result.photoUrl, VALID_PHOTO_URL);
  assert.equal(result.updated, true);

  assert.equal(recorded.authorizeCalls, 1);
  assert.equal(recorded.transactions, 1);
  assert.equal(recorded.patches.length, 1);

  const {ra, patch} = recorded.patches[0];
  assert.equal(ra, "9001");
  assert.equal(patch.photoUrl, VALID_PHOTO_URL);
  assert.equal(patch.photoURL, VALID_PHOTO_URL);
  assert.equal(patch.profileImageUrl, VALID_PHOTO_URL);
  assert.equal(patch.image_url, VALID_PHOTO_URL);
  assert.equal(patch.updated_at, SERVER_TIMESTAMP);
  assert.equal(patch.updatedAt, SERVER_TIMESTAMP);
  assert.deepEqual(patch.audit_trail, {
    __arrayUnion: {action: "photo_updated", by: CALLER.uid, by_ra: CALLER.ra},
  });
});

test("bloqueia chamada quando caller nao e autorizado", async () => {
  const {deps, recorded} = harness({
    authorizeError: new HttpsError("permission-denied", "Sem permissao."),
  });

  await assert.rejects(
    async () =>
      patchHumanPhoto(deps, {
        ra: "9001",
        photoUrl: VALID_PHOTO_URL,
      }),
    (err: unknown) => {
      assert.ok(err instanceof HttpsError);
      assert.equal(err.code, "permission-denied");
      return true;
    },
  );

  assert.equal(recorded.authorizeCalls, 1);
  assert.equal(recorded.transactions, 0);
  assert.equal(recorded.patches.length, 0);
});

test("recusa payload que nao e objeto plano", async () => {
  const {deps} = harness();
  await assert.rejects(
    () => patchHumanPhoto(deps, "invalido"),
    /Payload invalido/,
  );
  await assert.rejects(
    () => patchHumanPhoto(deps, null),
    /Payload invalido/,
  );
  await assert.rejects(
    () => patchHumanPhoto(deps, [1, 2, 3]),
    /Payload invalido/,
  );
});

test("recusa chaves desconhecidas (fail-closed)", async () => {
  const {deps} = harness();
  await assert.rejects(
    () =>
      patchHumanPhoto(deps, {
        ra: "9001",
        photoUrl: VALID_PHOTO_URL,
        extraField: "hack",
      }),
    /Chave desconhecida no payload: extraField/,
  );
});

test("recusa campos de outros dominios com erro descritivo", async () => {
  const {deps} = harness();

  await assert.rejects(
    () =>
      patchHumanPhoto(deps, {
        ra: "9001",
        photoUrl: VALID_PHOTO_URL,
        fullName: "Outro Nome",
      }),
    /Campo fullName pertence ao dominio pessoal/,
  );

  await assert.rejects(
    () =>
      patchHumanPhoto(deps, {
        ra: "9001",
        photoUrl: VALID_PHOTO_URL,
        accessProfile: "admin",
      }),
    /Campo accessProfile pertence ao dominio provisionamento de acesso/,
  );

  await assert.rejects(
    () =>
      patchHumanPhoto(deps, {
        ra: "9001",
        photoUrl: VALID_PHOTO_URL,
        password: "secretpassword",
      }),
    /Campo password pertence ao dominio conta de autenticacao/,
  );
});

test("valida RA obrigatorio e formato numerico", async () => {
  const {deps} = harness();

  await assert.rejects(
    () => patchHumanPhoto(deps, {photoUrl: VALID_PHOTO_URL}),
    /Campo obrigatorio ausente: ra/,
  );
  await assert.rejects(
    () => patchHumanPhoto(deps, {ra: "", photoUrl: VALID_PHOTO_URL}),
    /Campo ra nao pode ser vazio/,
  );
  await assert.rejects(
    () => patchHumanPhoto(deps, {ra: "abc", photoUrl: VALID_PHOTO_URL}),
    /RA deve conter apenas numeros/,
  );
  await assert.rejects(
    () => patchHumanPhoto(deps, {ra: "12", photoUrl: VALID_PHOTO_URL}),
    /RA deve conter apenas numeros/,
  );
});

test("valida photoUrl obrigatoria, formato e esquema seguro", async () => {
  const {deps} = harness();

  await assert.rejects(
    () => patchHumanPhoto(deps, {ra: "9001"}),
    /Campo obrigatorio ausente: photoUrl/,
  );
  await assert.rejects(
    () => patchHumanPhoto(deps, {ra: "9001", photoUrl: ""}),
    /Campo photoUrl nao pode ser vazio/,
  );
  await assert.rejects(
    () => patchHumanPhoto(deps, {ra: "9001", photoUrl: "not-a-url"}),
    /photoUrl deve ser uma URL valida/,
  );
  await assert.rejects(
    () =>
      patchHumanPhoto(deps, {
        ra: "9001",
        photoUrl: "javascript:alert(1)",
      }),
    /photoUrl deve ser uma URL valida/,
  );
  await assert.rejects(
    () =>
      patchHumanPhoto(deps, {
        ra: "9001",
        photoUrl: "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAA",
      }),
    /photoUrl deve ser uma URL valida/,
  );
});

test("retorna not-found se integrante nao existe", async () => {
  const {deps} = harness({user: null});

  await assert.rejects(
    () =>
      patchHumanPhoto(deps, {
        ra: "9001",
        photoUrl: VALID_PHOTO_URL,
      }),
    (err: unknown) => {
      assert.ok(err instanceof HttpsError);
      assert.equal(err.code, "not-found");
      assert.match(err.message, /Integrante nao encontrado/);
      return true;
    },
  );
});

test("retorna failed-precondition se integrante esta arquivado ou deletado", async () => {
  const {deps: depsInactive} = harness({
    user: existingUser({active: false}),
  });
  await assert.rejects(
    () =>
      patchHumanPhoto(depsInactive, {
        ra: "9001",
        photoUrl: VALID_PHOTO_URL,
      }),
    (err: unknown) => {
      assert.ok(err instanceof HttpsError);
      assert.equal(err.code, "failed-precondition");
      assert.match(err.message, /Integrante arquivado nao pode ter a foto alterada/);
      return true;
    },
  );

  const {deps: depsDeleted} = harness({
    user: existingUser({deleted_at: 1_700_000_000_000}),
  });
  await assert.rejects(
    () =>
      patchHumanPhoto(depsDeleted, {
        ra: "9001",
        photoUrl: VALID_PHOTO_URL,
      }),
    (err: unknown) => {
      assert.ok(err instanceof HttpsError);
      assert.equal(err.code, "failed-precondition");
      return true;
    },
  );
});
