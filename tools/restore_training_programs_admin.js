const fs = require("fs");
const path = require("path");

const admin = require("../functions/node_modules/firebase-admin");

const PROJECT_ID = "canil-gcm";
const DEFAULT_SERVICE_ACCOUNT = "C:\\tmp\\canil-gcm-firebase-admin.json";

const seedFiles = [
  "training_programs_busca_captura_seed.json",
  "training_programs_guarda_protecao_seed.json",
  "training_programs_deteccao_seed.json",
];

function arg(name) {
  const index = process.argv.indexOf(name);
  return index >= 0 ? process.argv[index + 1] : null;
}

function hasFlag(name) {
  return process.argv.includes(name);
}

function loadCredential(serviceAccountPath) {
  const resolved = path.resolve(serviceAccountPath);
  if (!fs.existsSync(resolved)) {
    throw new Error(`Service account nao encontrada: ${resolved}`);
  }
  return admin.credential.cert(JSON.parse(fs.readFileSync(resolved, "utf8")));
}

function auditEntry(action, source) {
  return {
    action,
    by_name: "restore_training_programs_admin",
    source,
    reason: "Restauracao de curriculos apos limpeza do banco de dados.",
    at: new Date().toISOString(),
  };
}

function withAudit(data, action, source) {
  const existing = Array.isArray(data.audit_trail) ? data.audit_trail : [];
  return {
    ...data,
    audit_trail: [...existing, auditEntry(action, source)],
    restored_at: admin.firestore.FieldValue.serverTimestamp(),
    updated_at: admin.firestore.FieldValue.serverTimestamp(),
  };
}

function validateSeed(seed, fileName) {
  if (!seed || typeof seed !== "object") {
    throw new Error(`${fileName}: seed invalido.`);
  }
  const program = seed.program || {};
  const modules = Array.isArray(seed.modules) ? seed.modules : [];
  if (!program.id || !program.name || !program.modality) {
    throw new Error(`${fileName}: program.id/name/modality obrigatorios.`);
  }
  if (program.id !== program.modality) {
    throw new Error(`${fileName}: program.id deve ser igual a modality.`);
  }
  if (!modules.length) {
    throw new Error(`${fileName}: informe ao menos um modulo.`);
  }
  for (const module of modules) {
    if (!module.id || !module.name || !Number.isInteger(module.order)) {
      throw new Error(`${fileName}: modulo invalido ${JSON.stringify(module)}`);
    }
    if (!Array.isArray(module.milestones) || !module.milestones.length) {
      throw new Error(`${fileName}: modulo sem marcos ${module.id}`);
    }
    for (const milestone of module.milestones) {
      if (!milestone.id || !milestone.label || !Number.isInteger(milestone.order)) {
        throw new Error(`${fileName}: marco invalido ${JSON.stringify(milestone)}`);
      }
    }
  }
}

async function restoreSeed(db, fileName, dryRun) {
  const seedPath = path.join(__dirname, fileName);
  const seed = JSON.parse(fs.readFileSync(seedPath, "utf8"));
  validateSeed(seed, fileName);

  const program = seed.program;
  const programRef = db.collection("training_programs").doc(program.id);
  const writes = [];
  const source = program.source || fileName;

  writes.push({
    ref: programRef,
    data: withAudit(
      {
        ...program,
        seeded_at: admin.firestore.FieldValue.serverTimestamp(),
      },
      "restore_program",
      source,
    ),
  });

  for (const module of seed.modules) {
    const { milestones, ...moduleData } = module;
    const moduleRef = programRef.collection("modules").doc(module.id);
    writes.push({
      ref: moduleRef,
      data: withAudit(
        {
          ...moduleData,
          program_id: program.id,
          modality: program.modality,
          seeded_at: admin.firestore.FieldValue.serverTimestamp(),
        },
        "restore_module",
        source,
      ),
    });

    for (const milestone of milestones) {
      writes.push({
        ref: moduleRef.collection("milestones").doc(milestone.id),
        data: withAudit(
          {
            ...milestone,
            program_id: program.id,
            module_id: module.id,
            modality: program.modality,
            seeded_at: admin.firestore.FieldValue.serverTimestamp(),
          },
          "restore_milestone",
          source,
        ),
      });
    }
  }

  if (!dryRun) {
    let batch = db.batch();
    let pending = 0;
    for (const write of writes) {
      batch.set(write.ref, write.data, { merge: true });
      pending += 1;
      if (pending >= 450) {
        await batch.commit();
        batch = db.batch();
        pending = 0;
      }
    }
    if (pending > 0) await batch.commit();
  }

  return {
    file: fileName,
    program_id: program.id,
    name: program.name,
    version: program.version,
    modules: seed.modules.length,
    milestones: seed.modules.reduce((total, item) => total + item.milestones.length, 0),
    documents: writes.length,
    dry_run: dryRun,
  };
}

async function verifyProgram(db, programId) {
  const programSnap = await db.collection("training_programs").doc(programId).get();
  const modulesSnap = await db
    .collection("training_programs")
    .doc(programId)
    .collection("modules")
    .get();
  let milestones = 0;
  for (const moduleDoc of modulesSnap.docs) {
    const milestoneSnap = await moduleDoc.ref.collection("milestones").get();
    milestones += milestoneSnap.size;
  }
  return {
    program_id: programId,
    exists: programSnap.exists,
    modules: modulesSnap.size,
    milestones,
  };
}

async function main() {
  const serviceAccount = arg("--service-account") || DEFAULT_SERVICE_ACCOUNT;
  const dryRun = hasFlag("--dry-run");
  const only = arg("--only");
  const files = only
    ? seedFiles.filter((file) => file.includes(only) || file.includes(only.replace(/_/g, "-")))
    : seedFiles;

  if (!files.length) {
    throw new Error(`Nenhum seed encontrado para --only ${only}`);
  }

  admin.initializeApp({
    credential: loadCredential(serviceAccount),
    projectId: PROJECT_ID,
  });

  const db = admin.firestore();
  const restored = [];
  for (const file of files) {
    restored.push(await restoreSeed(db, file, dryRun));
  }

  const verification = [];
  if (!dryRun) {
    for (const item of restored) {
      verification.push(await verifyProgram(db, item.program_id));
    }
  }

  console.log(
    JSON.stringify(
      {
        project: PROJECT_ID,
        applied: !dryRun,
        restored,
        verification,
      },
      null,
      2,
    ),
  );
}

main().catch((error) => {
  console.error("Falha ao restaurar curriculos de treinamento.");
  console.error(error);
  process.exitCode = 1;
});
