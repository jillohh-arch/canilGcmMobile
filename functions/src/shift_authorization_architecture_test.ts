/**
 * HEALTH-V1-OP-AUTH — provas arquiteturais load-bearing.
 *
 * Estes testes não exercitam comportamento: eles impedem que a autoridade de
 * autorização volte a ser display. São verificações estáticas sobre o texto dos
 * módulos de enforcement, porque a regressão que queremos evitar é alguém
 * "otimizar" o guard lendo `health_summary/current`, que é justamente o que
 * ADR-005 §13 proíbe.
 *
 * Falham se:
 *  - o guard ou o engine passarem a mencionar health_summary / readiness_status;
 *  - o Mobile ganhar fallback direto para o writer antigo;
 *  - a autoridade canônica desaparecer do enforcement.
 *
 * Stage HEALTH-V1-OP-AUTH — implementação local. Não deployado.
 */
import * as assert from "assert";
import * as fs from "fs";
import * as path from "path";

const SRC_DIR = __dirname.endsWith("lib") ?
  path.join(__dirname, "..", "src") :
  __dirname;
const REPO_ROOT = path.join(SRC_DIR, "..", "..");

function readSource(relative: string): string {
  return fs.readFileSync(path.join(SRC_DIR, relative), "utf8");
}

function readRepoFile(relative: string): string {
  return fs.readFileSync(path.join(REPO_ROOT, relative), "utf8");
}

/** Remove comentários, para que uma menção explicativa não gere falso positivo. */
function stripComments(source: string): string {
  return source
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/^\s*\/\/.*$/gm, "");
}

const ENFORCEMENT_MODULES = [
  "shift_restriction_guard.ts",
  "shift_authorization_engine.ts",
];

/**
 * Fontes de DISPLAY que nunca podem participar de uma decisão de autorização.
 */
const FORBIDDEN_AUTHORITY_TOKENS = [
  "health_summary",
  "readiness_status",
  "DogFitnessService",
  "calculateReadiness",
  "lastKnownGood",
  "legacy_score",
];

let failed = 0;

async function test(name: string, fn: () => void | Promise<void>): Promise<void> {
  try {
    await fn();
    console.log(`ok - ${name}`);
  } catch (error) {
    failed += 1;
    console.error(`FAIL - ${name}`);
    console.error(error);
  }
}

async function main(): Promise<void> {
  await test("enforcement não referencia nenhuma fonte de display", () => {
    for (const module of ENFORCEMENT_MODULES) {
      const code = stripComments(readSource(module));
      for (const token of FORBIDDEN_AUTHORITY_TOKENS) {
        assert.ok(
          !code.includes(token),
          `${module} não pode referenciar "${token}" — autorização vem de ` +
            "operational_restrictions, não de projeção de display.",
        );
      }
    }
  });

  await test("enforcement lê a coleção canônica operational_restrictions", () => {
    const engine = readSource("shift_authorization_engine.ts");
    assert.ok(
      engine.includes("operational_restrictions"),
      "o engine precisa consultar a autoridade canônica",
    );
    const guard = readSource("shift_restriction_guard.ts");
    assert.ok(
      guard.includes("resolveRestrictionsEvidence"),
      "o guard precisa reusar o parser canônico, não reimplementar",
    );
  });

  await test("guard trata evidência inconclusiva como negativa, não como vazio", () => {
    const guard = stripComments(readSource("shift_restriction_guard.ts"));
    assert.ok(
      guard.includes("unavailable"),
      "o guard precisa de um resultado explícito de indisponibilidade",
    );
    const engine = stripComments(readSource("shift_authorization_engine.ts"));
    assert.ok(
      engine.includes("restrictions_unavailable"),
      "o engine precisa distinguir falha técnica de bloqueio clínico",
    );
    assert.ok(
      engine.includes("absolute_restriction_active"),
      "o engine precisa de código próprio para bloqueio clínico",
    );
  });

  await test("Mobile não tem fallback para o writer direto após falha do backend", () => {
    // Invariante de segurança: se o backend nega, a operação NÃO pode voltar ao
    // caminho antigo de escrita direta no Firestore.
    const viewModel = stripComments(
      readRepoFile("lib/features/shifts/presentation/viewmodels/shift_viewmodel.dart"),
    );

    // Nenhum catch pode reinvocar o writer legado das ações migradas.
    const catchBlocks = viewModel.split(/catch\s*\(/).slice(1);
    for (const block of catchBlocks) {
      const window = block.slice(0, 600);
      for (const legacy of [
        "_shiftService.startShift",
        "_shiftService.switchDog",
      ]) {
        assert.ok(
          !window.includes(legacy),
          `fallback proibido detectado: ${legacy} dentro de catch`,
        );
      }
    }
  });

  await test("switchDog não tem mais writer client-side algum", () => {
    // Trocar K9 SEMPRE substitui a associação operacional: não há variante
    // legítima client-side.
    const viewModel = stripComments(
      readRepoFile("lib/features/shifts/presentation/viewmodels/shift_viewmodel.dart"),
    );
    assert.ok(
      !viewModel.includes("_shiftService.switchDog("),
      "switchDog deve ter migrado integralmente para a boundary backend",
    );
  });

  await test("assumeVehicle não tem mais writer client-side algum", () => {
    const viewModel = stripComments(
      readRepoFile("lib/features/shifts/presentation/viewmodels/shift_viewmodel.dart"),
    );
    assert.ok(
      !viewModel.includes("_shiftService.assumeVehicle("),
      "assumeVehicle deve ter migrado para a boundary backend",
    );
  });

  await test("startShift client-side sobrevive APENAS para turno sem K9", () => {
    // A invariante é de PROVENIÊNCIA, não de nome de função: um caminho que não
    // introduz dogId não precisa do guard. O único uso legítimo do writer antigo
    // é o turno sem K9, que grava dogId vazio.
    //
    // Se alguém passar um dogId real por aqui, este teste falha — é exatamente
    // essa a porta lateral que a vertical fecha.
    const viewModel = stripComments(
      readRepoFile("lib/features/shifts/presentation/viewmodels/shift_viewmodel.dart"),
    );
    const calls = viewModel.split("_shiftService.startShift(").slice(1);
    assert.strictEqual(
      calls.length,
      1,
      "deve existir no máximo UM startShift client-side (turno sem K9)",
    );
    const args = calls[0].slice(0, calls[0].indexOf(");"));
    assert.ok(
      /dogId:\s*''/.test(args) || /dogId:\s*""/.test(args),
      "o único startShift client-side precisa gravar dogId vazio literal, " +
        `recebido: ${args.replace(/\s+/g, " ").trim()}`,
    );
  });

  await test("Mobile não decide autorização a partir de readiness/fitness", () => {
    const screen = stripComments(
      readRepoFile("lib/features/shifts/presentation/screens/shift_assumption_screen.dart"),
    );
    // O diálogo dispensável de "não apto" não pode mais governar a operação.
    assert.ok(
      !screen.includes("DogFitnessStatus.unfit"),
      "o bypass dispensável do fitness legado não pode gatilhar a operação",
    );
  });

  if (failed > 0) {
    console.error(`\n${failed} test(s) failed`);
    process.exit(1);
  }
  console.log("shift_authorization_architecture_test: all passed");
}

void main();
