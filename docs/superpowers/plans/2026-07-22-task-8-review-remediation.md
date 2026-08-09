# Task 8 Review Remediation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Corriger les rôles/crops ImageGen refusés et rendre le contrat incapable d'accepter une recette arbitraire ou un PNG au faux profil.

**Architecture:** Le manifeste reste la provenance lisible, mais le vérificateur possède une table de recettes attendues indépendante et compare chaque rôle exactement. Le builder reste mécanique et borné; les tests vérifient les pixels, les chemins et l'ordre temporel avant de reconstruire les dérivés.

**Tech Stack:** Ruby/Minitest, ImageMagick, PNG chunks/iCCP, Xcode 26.

## Global Constraints

- Masters ImageGen immuables; dérivés PNG mécaniques uniquement.
- Aucun SVG/PDF, aucun commit/push, aucune modification Swift pour cette remediation.
- Toute modification de production suit RED puis GREEN.

---

### Task 1: Rôles et recettes exactes

**Files:**
- Modify: `scripts/verify_imagegen_assets_test.rb`
- Modify: `scripts/verify_imagegen_assets.rb`
- Modify: `Art/imagegen-provenance.json`

- [x] Ajouter un test qui refuse l'ancien crop portal/CRT et toute recette modifiée.
- [x] Observer le RED sur le manifeste actuel.
- [x] Définir la table exacte rôle → source/opérations dans le vérificateur.
- [x] Corriger portal vers le cercle central et ramp vers un objet complet.
- [x] Observer le GREEN ciblé.

### Task 2: Alpha et inspection

**Files:**
- Modify: `scripts/verify_imagegen_assets_test.rb`
- Modify: `Art/imagegen-provenance.json`
- Rebuild: `NovaStationPinball/Resources/Art/*.png`

- [x] Étendre le test magenta à tous les dérivés alpha et observer le RED.
- [x] Ajouter la recette defringe exacte à tous les crops alpha appropriés.
- [x] Rebuild et observer le GREEN.
- [x] Générer et inspecter les composites noir/blanc de tous les crops alpha, puis le portal original.

### Task 3: Profil, confinement et temps

**Files:**
- Modify: `scripts/verify_imagegen_assets_test.rb`
- Modify: `scripts/verify_imagegen_assets.rb`
- Modify: `Art/imagegen-provenance.json`

- [x] Ajouter les tests négatifs iCCP arbitraire, chemins échappés et `generated_at` antérieur.
- [x] Observer les RED attendus.
- [x] Valider le nom/profil iCCP sRGB, tous les chemins manifest/opérations et l'ordre temporel.
- [x] Mettre `generated_at` après le dernier master/review et observer le GREEN.

### Task 4: Porte finale et rapport

**Files:**
- Modify: `.superpowers/sdd/task-8-report.md`

- [x] Rebuilder deux fois et comparer tous les SHA.
- [x] Exécuter verifier, suite Ruby complète, release contract et build générique.
- [x] Mettre à jour le rapport avec les RED/GREEN, inspections, commandes et limites.
- [x] Vérifier l'état Git sans commit/push.
