# Changelog

All notable changes to this project are listed here. The list comes from the commit history.

## [Unreleased]

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

