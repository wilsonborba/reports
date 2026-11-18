//! Normalized rows retain API models, ordered duplicates, scalar types and parent integrity.
use reports::{
    dal::{
        calculations::{self, CalculationVersion},
        catalog::{self, ProjectRecord},
        Db,
    },
    domain::themes::asodya_theme,
};
use serde_json::json;

#[tokio::test]
async fn nested_definition_roundtrip_and_atomic_parent_constraints() {
    let dir = tempfile::tempdir().unwrap();
    let url = std::env::var("REPORTS_NORMALIZED_TEST_DATABASE_URL").unwrap_or_else(|_| {
        format!(
            "sqlite://{}?mode=rwc",
            dir.path().join("normalized.db").display()
        )
    });
    let db = Db::connect(&url).unwrap();
    if !url.starts_with("sqlite:") {
        let identity: String = sqlx::query_scalar("SELECT CAST(current_database() AS TEXT)")
            .fetch_one(&db.pool)
            .await
            .unwrap();
        assert!(
            identity.ends_with("_test"),
            "PostgreSQL test requires a database name ending with _test"
        );
    }
    if url.starts_with("sqlite:") {
        db.create_sqlite_test_schema().await.unwrap();
    }
    db.check_schema().await.unwrap();
    let project = ProjectRecord {
        slug: "normalized-test".into(),
        name: [
            ("en".into(), "__reports_sql_null__".into()),
            ("th".into(), "ข้อมูล".into()),
        ]
        .into(),
        tagline: Default::default(),
        description: Default::default(),
        theme: asodya_theme("normalized-test"),
        is_active: true,
        website_url: None,
        repository_url: None,
        sort_order: 0,
        domain_project_id: None,
        updated_at: String::new(),
    };
    catalog::upsert_project(&db, &project).await.unwrap();
    let p = catalog::get_project(&db, &project.slug)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(p.name, project.name);
    assert_eq!(p.theme, project.theme);
    let definition = json!({
    "title":{"en":"Everything","pt":"Compatível"},"description":{"th":"รายละเอียด"},"source":"rows","equation":"x+1",
    "union":["rows","rows"],"lookups":[{"collection":"lookup","key":["a","a"],"match":["b"],"fields":["name"],"prefix":""}],
    "buckets":[{"field":"time","unit":"day","name":"day","utc_offset_minutes":-90}],
    "row_derived":[{"name":"n","expr":"1","expr_field":null}],
    "where":[{"field":"a","op":"in","value":[null,true,1,1.5,"__reports_sql_null__",{"draft":[[],{}]}]}],
    "filters":[{"field":"a","label":{"en":"Category"},"type":"category","scope":"refs"}],
    "stages":[{"group_by":["a"],"partition_by":["b"],"measures":[{"name":"n","agg":"count","fields":["a"],"where":[{"field":"a","op":"eq","value":""}],"n":2}],"derived":[{"name":"d","expr":"n+1"}],"having":[{"field":"n","op":"gt","value":0}],"windows":[{"name":"w","agg":"sum","field":"n","size":3,"order_by":"day","partition_by":["a","b"]}]}],
    "derived":[{"name":"result","expr_field":"formula"}],"having":[{"field":"n","op":"between","value":[0,2]}],
    "calculator":{"name":"series","x":{"name":"x","from":-1,"to":3,"step":0.5},"exprs":[{"name":"y","expr":"x*x"}],"draft":{"preserve":null}},
    "params":{"p":1.5},"refs":{"ref":{"dataset":"d","field":"n"}},"sort":[{"field":"n","desc":true}],"limit":5,"warm":true,
    "fields":[{"name":"n","label":{"en":"Count"},"type":"integer","role":"measure","unit":"items","decimals":0}],
    "value_labels":{"a":{"a/b~c":{"en":"Label","pt":"Rótulo"},"":{"th":"ว่าง"}}}
    });
    let mut c = CalculationVersion {
        project: project.slug.clone(),
        calculation_id: "everything".into(),
        version: 1,
        status: "draft".into(),
        input_schema: None,
        input_schema_version: None,
        inputs: vec![],
        definition: serde_json::from_value(definition).unwrap(),
        needs_review: false,
        created_at: String::new(),
        published_at: None,
    };
    calculations::save_draft(&db, &c).await.unwrap();
    let got = calculations::get(&db, &c.project, &c.calculation_id, 1)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(
        serde_json::to_value(&got.definition).unwrap(),
        serde_json::to_value(&c.definition).unwrap()
    );
    c.definition.union.clear();
    c.definition.value_labels.clear();
    c.definition.calculator = None;
    calculations::save_draft(&db, &c).await.unwrap();
    let got = calculations::get(&db, &c.project, &c.calculation_id, 1)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(
        serde_json::to_value(&got.definition).unwrap(),
        serde_json::to_value(&c.definition).unwrap()
    );
    assert!(sqlx::query("INSERT INTO calculation_unions(project_slug,calculation_id,version,row_key,parent_key,position,map_key,value) VALUES('normalized-test','everything',1,'orphan','absent',0,'','x')").execute(&db.pool).await.is_err());
    assert!(calculations::publish(&db, &c).await.unwrap());
    assert!(calculations::save_draft(&db, &c).await.is_err());
    assert!(
        calculations::delete_version(&db, &c.project, &c.calculation_id, 1)
            .await
            .unwrap()
    );
    let count: i64 = sqlx::query_scalar(
        "SELECT CAST(COUNT(*) AS BIGINT) FROM calculation_definitions WHERE project_slug='normalized-test'",
    )
    .fetch_one(&db.pool)
    .await
    .unwrap();
    assert_eq!(count, 0);
    sqlx::query("DELETE FROM catalog_projects WHERE slug='normalized-test'")
        .execute(&db.pool)
        .await
        .unwrap();
}
