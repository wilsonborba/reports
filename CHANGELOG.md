## [Unreleased]

### Features

- *(logs)* Stream redacted engine logs from the journald writer
- *(telemetry)* Track mapped Reports controls through shared SQL telemetry

### Documentation

- *(changelog)* Record engine logging changes

### Other

- Back-merge v3.1.2 into feature/main
- Add Reports engine log stream (#37)


# Changelog

All notable changes to this project are listed here. The list comes from the commit history.

## [3.1.2] - 2026-10-27

### Bug fixes

- *(ui)* Name api_for_apps, domain_api and FSM on the Architecture page (#27)
- *(ui)* Merge Architecture service names (#27)

### Other

- Back-merge v3.1.1 into development
- Back-merge v3.1.1 into feature/main
- Promote feature/main to development for v3.1.2


## [3.1.1] - 2026-10-27

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



## [3.0.0] - 2026-10-25

### Features

- *(dal)* [**breaking**] Persist reports in PostgreSQL, CouchDB and Redis
- *(access)* Add discoverable placeholders, grants, roles and the guest showcase
- *(catalog)* Add project links, Domain UUID composition and durable themes
- *(calc)* Version calculations, add common operators, lineage and snapshots
- *(catalog)* Add cached Domain project details and keep engine start minimal
- *(fixtures)* Own sample data by manifest and add scripts for five projects
- *(ui)* Asodya login, real engine routes, Architecture tab and full pt-BR
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

### Performance

- *(cache)* Avoid redundant loads and calculations, add operations view

### Documentation

- Rewrite README for the Reports engine
- Generate the CHANGELOG from the commit history with git-cliff

### Tests

- *(engine)* Cover durable stores, ingestion, access and caching
- *(access)* Cover showcase skeletons, hidden resources, grants and roles
- *(catalog)* Cover Domain links, caching, outages, themes and report tier
- *(calc)* Representative metrics of the five projects and version history
- *(e2e)* Live gateway check, guest browser check and access matrix gaps

### Maintenance

- *(scripts)* Add explicit migrate.sh and a service-only installer
- Remove old project scripts and untrack local assistant docs
- Ignore local assistant docs in engine/alignment
- Remove the Scalar API docs

### Other

- Promote feature/main to development for v3.0.0

## [2.0.0] - 2026-10-24

### Features

- Initial commit of domain-agnostic reports platform
- Implement Asodya reports platform
- Expose network readiness status
- Align runtime defaults with Asodya infrastructure
- Use Asodya gateway SSO identity
- Hydrate network catalog on startup
- *(ui)* Show deployment timestamp in public footer
- *(ui)* Adopt Asodya Ubuntu Sans typography
- *(platform)* Decouple reports platform with guest discovery and synthetic launch fixtures

### Bug fixes

- Align package imports and test assertions with reports namespace
- Reconcile Cloudflare Pages DNS during deploy
- Make Cloudflare deploy find Flutter under sudo
- Proxy reports Pages domain like Asodya apps
- Verify Pages domain before enabling proxy
- *(ui)* Make Reports landing public and fully branded
- *(engine)* Align gateway routes and network config
- Keep Reports catalog available in browser

### Refactoring

- Retire embedded storage engines
- Separate catalog population from migrations

### Documentation

- Add Asodya reports architectural alignment
- Align SSO and network storage guidance

### Tests

- *(auth)* Sort provider keys assertion to match BTreeMap ordering

### Maintenance

- Format reports authentication errors
- Add explicit network storage provisioning
- Add reports install and deployment scripts
- Use Reports service naming
- *(dal)* Remove architecture schema from migrations

