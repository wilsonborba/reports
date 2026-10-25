use utoipa::OpenApi;

use super::{admin, public, server, viewer};

#[derive(OpenApi)]
#[openapi(
    info(
        title = "Reports API",
        version = "2.0.0",
        description = r#"# Reports API

Reports is the Asodya reporting product: project reports, statistics and dashboards. The Flutter
web app builds the PDF, Markdown and CSV ZIP exports in the browser from these responses.

## Request path

Browsers call the api_for_apps gateway. The gateway removes `/apps/reports/v1` and forwards
the rest to this engine on `127.0.0.1:8109`:

```
https://api.asodya.com/apps/reports/v1/projects/cortex/reports  ->  http://localhost:8109/projects/cortex/reports
```

## Stores

- PostgreSQL `asodya_reports`: projects, reports, datasets, versioned schemas, roles.
- CouchDB `reports_documents`: received records (idempotent by key).
- Redis: temporary cache of results. A Redis failure is a cache miss.

`scripts/migrate.sh` owns the database structure. The engine runs no migration at start;
it stops with a clear message when the schema is missing or outdated.

## Access

- Guest routes (`/catalog`, `/projects/{project}`, `/projects/{project}/reports`, ...) never read identity.
- Session routes get the real `x-uuid` from the gateway session. Super admin is
  `x-access-level: 1` together with `x-uuid`. Project admins come from `user_project_roles`.
- Visibility: `public`, `signed_in`, `restricted`. The effective value of a dataset is the stricter of
  its report and its own value. Guests get 401 (login may help); sessions get 403 (access limited).
- Local operator tools use the `x-reports-service-key` header.

## Languages

`?lang=en|pt-BR|th`, else `Accept-Language`, else English.
"#
    ),
    paths(
        server::health,
        server::ready,
        public::list_projects,
        public::project_detail,
        public::project_theme,
        public::list_reports,
        public::global_stats,
        public::project_stats,
        public::showcase,
        public::showcase_card,
        viewer::me,
        viewer::my_reports,
        viewer::report_view,
        viewer::dataset_page,
        admin::put_project,
        admin::put_theme,
        admin::put_report,
        admin::delete_report,
        admin::put_dataset,
        admin::delete_dataset,
        admin::list_schemas,
        admin::post_schema,
        admin::publish_schema,
        admin::retire_schema,
        admin::ingest_records,
        admin::post_calculation,
        admin::validate_calculation,
        admin::publish_calculation,
        admin::retire_calculation,
        admin::list_calculations,
        admin::post_snapshot,
        admin::list_snapshots,
        admin::delete_fixture,
        admin::operations,
        admin::put_role,
        admin::delete_role,
        admin::list_roles,
        admin::post_grant,
        admin::list_grants,
        admin::delete_grant,
    ),
    components(schemas(
        crate::domain::models::ProjectSummary,
        crate::domain::models::ReportSummary,
        crate::domain::models::ReportView,
        crate::domain::models::ReportPeriod,
        crate::domain::models::Paged<crate::domain::models::ProjectSummary>,
        crate::domain::models::Paged<crate::domain::models::ReportSummary>,
        crate::domain::datasets::DatasetDescriptor,
        crate::domain::datasets::DatasetPage,
        crate::domain::datasets::FieldInfo,
        crate::domain::datasets::FilterInfo,
        crate::domain::datasets::FilterOption,
        crate::domain::datasets::spec::DataTier,
        crate::domain::auth::Visibility,
        crate::domain::themes::ProjectTheme,
        crate::domain::themes::ThemeTokens,
        crate::domain::stats::ProjectStats,
        crate::domain::stats::GlobalStats,
        crate::domain::stats::ReportCount,
        crate::domain::stats::DayCount,
        crate::domain::guardrail::SchemaField,
        crate::domain::guardrail::ValidationError,
        crate::domain::guardrail::ValidationViolationType,
        crate::domain::ingest::SchemaDraftRequest,
        crate::domain::ingest::IngestRequest,
        crate::domain::ingest::IngestRecord,
        crate::domain::ingest::IngestResponse,
        crate::dal::InsertOutcome,
        crate::dal::SchemaVersion,
        crate::dal::ProjectRecord,
        crate::dal::ReportRecord,
        crate::dal::ReportMetadata,
        crate::dal::PeriodSource,
        admin::ProjectBody,
        admin::ReportBody,
        admin::DatasetBody,
        admin::RoleBody,
        admin::FixtureRemoval,
        admin::OperationsView,
        crate::domain::datasets::service::LoadedCollection,
        admin::GrantBody,
        crate::dal::Grant,
        crate::dal::CalculationVersion,
        crate::dal::InputRef,
        crate::domain::calculations::CalculationDraftRequest,
        crate::domain::datasets::service::Lineage,
        crate::domain::datasets::service::Watermark,
        crate::dal::domain_api::DomainProject,
        crate::dal::domain_api::DomainProjectDetail,
        crate::dal::domain_api::DomainLink,
        crate::dal::domain_api::DomainCategory,
        crate::dal::domain_api::DomainStatistic,
        crate::dal::domain_api::DomainCollaborator,
        crate::domain::composition::DomainDetails,
        crate::domain::composition::DomainStatus,
        crate::dal::ProjectRole,
        crate::domain::reports::ShowcaseView,
        crate::domain::models::AccessSummary,
        crate::domain::reports::ShowcaseCard,
        crate::domain::reports::Skeleton,
        viewer::MeResponse,
        server::HealthResponse,
        crate::domain::datasets::service::CacheCounters,
    )),
    tags(
        (name = "Projects", description = "Selected Asodya projects, themes and statistics"),
        (name = "Reports", description = "Reports and dataset rows with the access rules applied"),
        (name = "Session", description = "The signed-in caller"),
        (name = "Admin", description = "Catalog writes, versioned schemas and record ingestion"),
        (name = "Health", description = "Liveness and readiness"),
    )
)]
pub struct ApiDoc;
