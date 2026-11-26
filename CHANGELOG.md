# Changelog

All notable changes to this project are listed here. The list comes from the commit history.

## [Unreleased]

### Features

- *(logs)* Stream redacted engine logs from the journald writer
- *(telemetry)* Track mapped Reports controls through shared SQL telemetry
- *(storage)* Save unfinished normalized storage work (#40)
- *(access)* Add per-user ownership, source app, control authority, audiences, and user-scoped caches (#41)
- *(owner-api)* Add owner APIs for user charts/diagrams with If-Match, idempotency, limits, and reuse warning (#42)
- *(datasets)* Add dataset_meta and dataset_field_semantics tables, validation, and API meta block (#48)
- *(embeds)* Add identity-aware search, viewer embeds and immutable snapshots (#43)
- *(templates)* Add normalized versioned visual templates and card bindings (#52)
- *(render-jobs)* Add temporary question visual render jobs (#54)
- *(package)* Extract chart renderer into reports_view package (#45)
- *(catalog)* Add comparison templates (catalog items 1 to 23) (#55)
- *(catalog)* Add change over time templates (catalog items 24 to 43) (#56)
- *(catalog)* Add part of a whole templates (catalog items 44 to 54) (#57)
- *(catalog)* Add distribution templates (catalog items 55 to 64) (#58)
- *(catalog)* Add relation and correlation templates (catalog items 65 to 73) (#59)
- *(catalog)* Add flow, process, and structure diagram templates (items 74 to 89) (#60)
- *(catalog)* Add sets templates (items 90 to 92) and bump reports_view for #60/#61
- *(catalog)* Add geographic catalog templates (items 93 to 98) (#62)
- *(catalog)* Add indicators and tables catalog templates (items 99 to 104) (#63)
- *(catalog)* Add science, AI, and assessment catalog templates (items 105 to 114) (#64)
- *(reports)* Support complete aggregate snapshots
- *(reports#70)* Add reproducible aggregate_snapshot v1 schema, technical-aggregates report, and 7 dataset/card definitions
- *(ingest)* Merge aggregate consumer catalog definitions (#70)

### Bug fixes

- *(telemetry)* Replace tracking dependency with screen_trail (#39)
- *(storage)* Preserve applied migrations and legacy upgrade paths (#40)
- *(charts)* Apply null, zero, negative and missing_means rules in PDF export (#47)
- *(export)* Add restricted placeholder, axis titles, and card metadata for #51
- *(catalog)* Update reports_view goldens/layouts and add hierarchical parent slot (#55, #56, #57)
- *(distribution)* Bump reports_view to 288651e for theoretical normal qqPlot (#58)
- *(goldens)* Bump reports_view to 09e61b4 with real Ubuntu Sans and IBM Plex Sans Thai fonts (#55-#58)
- *(catalog)* Update reports_view ref and KPI PDF export (#62 #63 #64)
- *(reports)* Fix templates clippy type_complexity (#69) and bump reports_view (#62, #64)
- *(ui)* Bind report locale to framework localization
- *(locale)* Integrate reviewed host and embed locale binding (#65)

### Documentation

- *(changelog)* Record engine logging changes
- *(changelog)* Record Reports shared telemetry adoption
- *(templates)* Document template-only rendering and pin reports_view 7f001eb (#53)
- *(changelog)* Record aggregate consumer contracts (#70)

### Maintenance

- Bump reports_view to 93f8025 for real relation chart renderers (#59)
- *(ui)* Pin hosted reports_view 0.2.0
- *(ui)* Bump reports_view for C12 contrast, ROC unavailability, and C8 nulls (#62, #64)

### Other

- Back-merge v3.1.2 into feature/main
- Add Reports engine log stream (#37)
- Add shared Reports frontend telemetry (#38)
- Switch Reports telemetry to screen_trail (#39)
- Normalize storage without changing applied migrations (#40)
- Format the Rust engine and tests (#67)
- Restore the engine formatting gate (#67)
- Add HTTP cache isolation and visibility invalidation tests
- Publish owner dataset records and add two-item visibility isolation route test
- Bump reports_view to b8bc4e8 (C23 localization and learning-curve null gap)

## [3.1.2] - 2026-10-26

### Bug fixes

- *(ui)* Name api_for_apps, domain_api and FSM on the Architecture page (#27)
- *(ui)* Merge Architecture service names (#27)

### Other

- Back-merge v3.1.1 into development
- Back-merge v3.1.1 into feature/main
- Promote feature/main to development for v3.1.2
- Promote v3.1.2

## [3.1.1] - 2026-10-26

### Bug fixes

- Preserve original Reports charts and flat sharing controls (#34)
- Merge original chart embed fidelity (#34)
- Avoid keyring wait in chart preview capture (#34)
- Merge chart preview keyring fix (#34)
- *(ui)* Show rates by category as bars, not a part-to-whole donut (#36)
- *(ui)* Merge rate chart selection (#36)
- *(ui)* Scale rate bars to the whole 0 to 100% range (#36)
- *(ui)* Merge rate bar scale (#36)
- *(ui)* Report the page route and real app version in client errors (#32)
- *(ui)* Merge client error route and version (#32)
- *(ui)* Write dates as DD/MM/AAAA in pt-BR (#12)
- *(ui)* Merge pt-BR dates (#12)

### Tests

- *(ui)* Cover pt-BR letters in the PDF export (#15)
- *(ui)* Merge pt-BR PDF coverage (#15)

### Other

- Promote release/v3.1.0 to development
- Promote feature/main to development for v3.1.1
- Promote v3.1.1

## [3.1.0] - 2026-10-26

### Features

- Expose public item embeds and data-backed PNG previews (#33)
- Merge individual embed descriptors (#33)
- Add compact item views and copyable embed sharing (#34)
- Merge compact embed sharing (#34)
- Merge embed release verification (#35)

### Tests

- Verify public embed visibility and document release operations (#35)

### Other

- Back-merge v3.0.0 into development
- Back-merge v3.0.0 into feature/main
- Promote v3.1.0

## [3.0.0] - 2026-10-25

### Features

- *(engine)* Tier filter and caller access counts
- *(engine)* Card order of a report
- *(fixtures)* 4 reports of 4 sections with 4 charts per project
- *(ui)* Navigation, guest prompt, tier filters, chart share and brand colors
- Access tags, toolbar filter, soft chart colors

### Bug fixes

- *(dal)* Bind optional values as plain values for PostgreSQL
- *(population)* Compare schema fields by path so a rerun reuses the published version
- *(export)* Leave out sections without a readable card
- *(fixtures)* Fixed access cases in the sample data
- *(ui)* Remove the gradient behind the hero bands
- *(ui)* Asodya.com palette, lime with black and purple with white
- *(ui)* Opening another report from the sidebar draws its cards
- *(ui)* Calmer dashboard accents, full-width chart titles

### Maintenance

- Start the Reports platform history
- Remove the Scalar API docs

### Other

- Promote feature/main to development for v3.0.0
- Promote v3.0.0
