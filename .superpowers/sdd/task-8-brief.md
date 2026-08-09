### Task 8: Pipeline ImageGen et intégration raster

**Files:**
- Create: `Art/ImageGen/*.png`, `Art/imagegen-provenance.json`
- Create: `scripts/build_imagegen_assets.rb`, `scripts/verify_imagegen_assets.rb`
- Test: `scripts/verify_imagegen_assets_test.rb`
- Create: `NovaStationPinball/Resources/Assets.xcassets/AppIcon.appiconset/*`
- Create: `NovaStationPinball/Resources/Art/*.png`
- Modify: `NovaStationPinball/Game/PinballScene.swift`

**Interfaces:**
- Produces: masters et dérivés PNG nommés, hachés, inspectés et liés aux rôles runtime.

- [ ] Écrire le contrat Ruby qui échoue en absence des masters, de provenance, de dimensions/alpha/profil et en présence de SVG/PDF.
- [ ] Exporter le guide greybox et l’utiliser comme référence ImageGen pour la composition maître 4:3.
- [ ] Générer par ImageGen icon, key art, table, CRT, panneaux, batteurs, bumpers, cibles, rampes, portails, lampes, menus, HUD et créatifs Store.
- [ ] Inspecter chaque master à taille réelle ; rejeter perspective, texte ou géométrie incompatibles.
- [ ] Inscrire prompt/date/dimensions/rôle/source/SHA-256 dans le manifeste.
- [ ] Normaliser les dérivés PNG de façon reproductible et faire passer le contrat.
- [ ] Remplacer tout nœud greybox visible par un sprite raster ; conserver seulement collisions, masques et VFX procéduraux invisibles/dynamiques.
- [ ] Vérifier la correspondance pixel/art mécanique par overlay du guide.
