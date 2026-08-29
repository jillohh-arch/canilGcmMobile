/**
 * Adapter de Storage para o HealthDocument canônico (B0-B / B0-B.R).
 *
 * Isola o Admin Storage atrás de um seam para que o engine/callable seja
 * exercitável por unit test sem bucket real e sem emulador de Storage — que
 * este repo não declara em `firebase.json`.
 *
 * Precedente de leitura de metadata server-side: `sha256FromStorageUrl` em
 * `index.ts` já usa `bucket.file(path).getMetadata()` em produção.
 *
 * ── Por que existe um selo (B0-B.R) ──────────────────────────────────────────
 *
 * `allow create` das Firebase Storage Rules NÃO garante que os bytes de um
 * objeto existente não possam ser substituídos: um segundo upload no mesmo
 * path é avaliado como create e troca o conteúdo (comprovado no emulador,
 * comportamento idêntico em `health_attachments` e `documentos`).
 *
 * Portanto o cliente sobe para STAGING e o backend SELA para o namespace
 * canônico usando preconditions do próprio Cloud Storage — a garantia real de
 * create-only que as Rules não oferecem.
 */

import * as admin from "firebase-admin";

import {
  HealthDocumentStorageAdapter,
} from "./health_document_callables";
import {StorageObjectMetadata} from "./health_document_logic";

/**
 * Erros de "objeto ausente" do GCS.
 *
 * Um objeto inexistente é resultado LEGÍTIMO da verificação (o cliente não
 * subiu o arquivo) e vira `{exists: false}`; qualquer outra falha é propagada,
 * nunca convertida em ausência — do contrário um erro de permissão ou de rede
 * viraria "arquivo não existe", exatamente a degradação silenciosa proibida.
 */
function isObjectMissing(err: unknown): boolean {
  if (!err || typeof err !== "object") return false;
  const code = (err as {code?: unknown}).code;
  if (code === 404) return true;
  if (typeof code === "string" && code === "404") return true;
  const status = (err as {status?: unknown}).status;
  return status === 404;
}

/**
 * Falha de precondition (412) ou conflito (409).
 *
 * É o sinal de que a precondition fez seu trabalho: a generation da fonte
 * mudou, ou já existe objeto vivo no destino.
 */
export function isPreconditionFailure(err: unknown): boolean {
  if (!err || typeof err !== "object") return false;
  const code = (err as {code?: unknown}).code;
  if (code === 412 || code === 409) return true;
  if (typeof code === "string" && (code === "412" || code === "409")) {
    return true;
  }
  const status = (err as {status?: unknown}).status;
  return status === 412 || status === 409;
}

export function createAdminHealthDocumentStorageAdapter(
  bucketName?: string,
): HealthDocumentStorageAdapter {
  function resolveBucket() {
    return bucketName ?
      admin.storage().bucket(bucketName) :
      admin.storage().bucket();
  }

  async function readMetadata(
    path: string,
    generation?: string,
  ): Promise<StorageObjectMetadata> {
    const bucket = resolveBucket();
    // `generation` no FileOptions prende a leitura a uma versão exata.
    const file = generation ?
      bucket.file(path, {generation: Number(generation)}) :
      bucket.file(path);
    try {
      const [metadata] = await file.getMetadata();
      return {
        exists: true,
        contentType: metadata.contentType,
        size: metadata.size,
        md5Hash: metadata.md5Hash,
        crc32c: metadata.crc32c,
        generation: metadata.generation,
        // `metadata.metadata` é o mapa de custom metadata do GCS — onde vive o
        // selo server-owned.
        customMetadata: metadata.metadata as
          | Record<string, string>
          | undefined,
      };
    } catch (err) {
      if (isObjectMissing(err)) return {exists: false};
      throw err;
    }
  }

  return {
    getObjectMetadata: (path: string) => readMetadata(path),

    /**
     * Sela o objeto de staging no path canônico.
     *
     * Duas preconditions, ambas suportadas pelo `@google-cloud/storage`:
     *
     * 1. FONTE — `bucket.file(path, {generation})` prende a cópia à generation
     *    observada na validação. Se os bytes do staging mudarem entre a
     *    verificação e a cópia, a operação falha em vez de selar evidência
     *    diferente da que foi submetida.
     *
     * 2. DESTINO — `preconditionOpts.ifGenerationMatch: 0` só prossegue se não
     *    houver objeto vivo no destino. É a garantia create-only real,
     *    impossível de expressar via Rules.
     *
     * Retorna `sealed: false` quando a precondition de destino recusa por já
     * existir objeto canônico — caso legítimo de recuperação que o chamador
     * resolve comparando checksums, nunca sobrescrevendo.
     */
    sealObject: async (params: {
      sourcePath: string;
      sourceGeneration: string;
      destinationPath: string;
      sealMetadata: Record<string, string>;
    }): Promise<{sealed: boolean}> => {
      const bucket = resolveBucket();
      const source = bucket.file(params.sourcePath, {
        generation: Number(params.sourceGeneration),
      });
      const destination = bucket.file(params.destinationPath);
      try {
        await source.copy(destination, {
          preconditionOpts: {ifGenerationMatch: 0},
          // `CopyOptions.metadata` é serializado como o corpo do `rewriteTo`,
          // que é um Object resource — e nele a chave `metadata` É o mapa de
          // custom metadata. Portanto o mapa vai FLAT aqui (aninhar produziria
          // `metadata.metadata` no recurso).
          //
          // O selo nasce junto com os bytes canônicos, no mesmo request: não
          // há janela em que o objeto exista sem selo. Nunca copiado do
          // staging — o cliente controla o staging, então um selo de origem
          // cliente não provaria nada.
          metadata: params.sealMetadata,
        });
        return {sealed: true};
      } catch (err) {
        if (isPreconditionFailure(err)) return {sealed: false};
        throw err;
      }
    },

    getSealedMetadata: (path: string) => readMetadata(path),

    /** Limpeza best-effort do staging: falha nunca invalida o canônico. */
    deleteStagingObject: async (path: string): Promise<void> => {
      const bucket = resolveBucket();
      await bucket.file(path).delete({ignoreNotFound: true});
    },
  };
}
