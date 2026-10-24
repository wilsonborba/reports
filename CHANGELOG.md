# Changelog

All notable changes to this project are listed here. The list comes from the commit history.

## [Unreleased]

### Features

- *(dal)* [**breaking**] Persist reports in PostgreSQL, CouchDB and Redis
- *(access)* Add discoverable placeholders, grants, roles and the guest showcase
- *(catalog)* Add project links, Domain UUID composition and durable themes
- *(calc)* Version calculations, add common operators, lineage and snapshots
- *(catalog)* Add cached Domain project details and keep engine start minimal
- *(fixtures)* Own sample data by manifest and add scripts for five projects
- *(ui)* Asodya login, real engine routes, Architecture tab and full pt-BR

### Performance

- *(cache)* Avoid redundant loads and calculations, add operations view

### Documentation

- Rewrite README for the Reports engine

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

