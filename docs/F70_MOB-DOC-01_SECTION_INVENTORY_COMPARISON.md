# F70 MOB-DOC-01 — Section Inventory Comparison (Original vs Candidate)

> Frozen baseline: `38e2649` — `lib/core/services/pdf_generator/occurrence_pdf_generator.dart`
> Candidate: `7d16490` — same path, migrated to `ReportTemplateBuilder` darkTactical

## Method

Manual code-to-code mapping. Every `_build*Page` / `_build*Section` and forensic
helper in the original was located, then traced to its F70 counterpart.
Tests alone are insufficient per gate §5.

## Map

| # | Original section/helper | Candidate equivalent | Verdict |
|---|------------------------|----------------------|---------|
| 1 | `_header` (72pt dark bar, crest, docId, `PAGINA N`, accent rule) + `_footer` | `ReportPrimitives.darkTacticalHeader` (p1, ProductMark) + `darkCompactContinuationHeader` (p2..N) + `darkReportFooter` (`Página X de Y`) | **Reformatted** — visual parity via design system; `PÁGINA 0` eliminated; ProductMark now via `ReportBrandingAssets`. No field lost. |
| 2 | `_page` wrapper (fixed `pw.Page` cover+location) + `_page` location page | Unified `ReportTemplateBuilder` `pw.MultiPage` single flow | **Condensed** — intentional pagination repair (§6). Content identical, no longer two unbreakable fixed pages. |
| 3 | `_buildCoverPage` — typeName hero, nature/date/window grid, mapCard 178pt, 4 stat cards, binomio | `_buildHeroSection` + `_buildOperationalSummary` (first part) inside MultiPage | **Reformatted** — same fields (typeName, dates, duration, map location, GPS, stat counts, K9/handler). |
| 4 | `_buildLocationPage` — contextBar, map 230pt detailed, address box, coordinate box, GPS signal, admin grid (5-col + 2-col), binomio compact | `_buildLocationSection` (mapCanvasF70, infoBoxF70, coordinateBoxF70, gpsSignalF70, admin cells, vDividers) | **Reformatted** — all administrative fields present (shiftId, dates, duration, priority, sync time, vehicle context). |
| 5 | `_buildDisplacementSection` + `_displacementMapFrame` + `_paintDisplacementMap` + pins + legend | `_buildDisplacementSection` (F70) + `_displacementMapFrameF70` + same `_paintDisplacementMap` + `_displacementPinF70` | **Preserved** — identical geometry and labeling. Guard `T1-A` revalidates flex safety. |
| 6 | `_buildTimelinePage` — header, summary grid, per-event row (time+dot+card with left accent `Border` + `borderRadius` bug, photo badge), legend | `_buildTimelineSection` + `_timelineEventF70` (same structure, `borderRadius` removed from non-uniform Border per I1-B guard) | **Preserved** — event title, description, dogHandlerId note, GPS, photo count badge, color/mark mapping identical. |
| 7 | `_buildMediaPage` — mediaCount 5 cells, Wrap → chunked Rows (F40 fix), mediaCard/finalizationMediaCard 258×198, attachmentCard | `_buildMediaSection` + `_buildMediaGridF70`/`_buildFinalizationMediaGridF70` + `_mediaCardF70`/`_finalizationMediaCardF70` + `_attachmentCardF70` | **Preserved** — same counts, captions, GPS, sync badge, BO attachment logic; `Expanded` replaces fixed width for pagination. |
| 8 | `_buildReportPage` — result cards grid, transcription header, `_buildReportParagraphs` (800-char chunking), note | `_buildReportSection` + `_buildResultCardsGridF70` + `_buildReportParagraphsF70` (same 800-char splitter) | **Preserved** — result labels/descriptions, `_detailsValue` routing, `_resultMark`, `transcricao` header, forensic fallback strings. |
| 9 | `_buildValidationPage` — hashBox + verificationBox side-by-side, team/signatures (conditional), docInfo wrap | `_buildValidationSection` + `_hashBoxF70` + `_verificationBoxF70` + `_buildTeamAndSignaturesSectionF70` | **Preserved** — `integrityStateText` verbatim, QR data/URL unchanged, signature table (RA/UTC/method/hash), pending block, `_shouldShowTeamAndSignatures` gate. |
|10 | `_buildAmendmentsSection` + `_buildAmendmentEntry` + `_buildCorrectionRow` | `_buildAmendmentsSection` (F70) + `_buildAmendmentEntryF70` + `_buildCorrectionRowF70` | **Reformatted** — added `styledSectionTitle` header, same amendment fields (sequenceNumber, date, author RA/name, reason, corrections Antes/Depois with strikethrough, hash, QR `…?a=&h=`). |
|11 | Helpers: `_buildDocId`, `_operationStart/End`, `_durationLabel`, `_formatDate/Time`, `_eventTitle`, `_statusLabel`, `_boCount`, `_locationMain/Sub`, `_gpsText`, `_accuracyText`, `_shortId`, `_tinyLabel`, `_mono/_body`, `_emptyBox` | Same helpers, verbatim (or thin F70 wrapper using `ReportColors`) | **Preserved** |
|12 | `_optimizePhotoForPdf`, `_loadOptimizedPhoto`, `_buildMediaItems`, `_buildFinalizationMediaItems` | Unchanged | **Preserved** |
|13 | `formatDrugDescription` / `ForTest`, `_weaponDescription`, `_personDescription`, `_boDescription`, `_detailsValue/_detailsMap` | Restored verbatim after initial drift (` — ` / `substância` reverted to ` - ` / `substancia`) | **Preserved** — `FF-OCC-08` guard enforces. |
|14 | `_integrityStateText` + `integrityStateTextForTest` + `totalMediaCount/isEmptyMediaState` | Verbatim | **Preserved** — `FF-OCC-09` guard enforces. |
|15 | `_orderedTeam`, `_signedSignatures`, `_pendingSignatureItems`, `_vehicleInfoLine`, `_serviceDogLabel/PresenceBox`, `_teamTable`, `_signatureTable`, `_pendingSignaturesBlock`, `_pdfTableHeader/Cell`, member-name helpers | Direct F70 ports (`…F70` suffix) with `ReportColors`/`ReportToneColors` but same `TableBorder`/`FlexColumnWidth` structure | **Preserved** |
|16 | `K9_VERIFICATION_BASE_URL` (`https://canil-gcm.web.app/v`) + `_verificationCode/Url` | Unchanged | **Preserved** — no QR ownership change. |

## Intentionally condensed / reformatted (non-forensic)

- Fixed cover/location `pw.Page` → flow inside single `MultiPage` (pagination repair).
- `_header`/`_footer` → `darkTacticalHeader`/`darkCompactContinuationHeader`/`darkReportFooter` (design system).
- `_contextBar`/`_gridBox`/`_metaCell`/`_statCard` → `_buildOperationalSummary` metric row + period/status container using `ReportPrimitives`.
- Decorative glyphs `◉ ⬡ 📍` → `O <> P` (Helvetica fallback has no emoji; IBM Plex still renders via embedded subset when available).
- Timeline card `Border`+`borderRadius` → `Border` without radius (pdf engine forbids non-uniform Border with radius).
- Media cards from `width: 258, height: 198` fixed → `Expanded` 2-per-row (breaks without `TooManyPagesException`).
- Section titles now via `ReportPrimitives.styledSectionTitle` (`K9 / OPS / LOC / MAP / TL / MID / RES / REL / INT / EQ / ADI` badges).

## Omitted information

**None.** Every forensic field and status in the frozen baseline has an equivalent in the candidate. Any future field added to the occurrence model must be routed through this comparison gate.

## Risk note

Visual density differs because `build/` PDFs embed IBM Plex TrueType (`/ToUnicode`) while the harness previously fell back to Helvetica/Courier. Typography and line breaking WILL differ on-device vs test; only owner device homologation closes that gap.
