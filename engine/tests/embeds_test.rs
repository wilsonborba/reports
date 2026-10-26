mod common;
use common::*;
use axum::{body::{Body,to_bytes},http::{Request,StatusCode}};
use serde_json::json;
use tower::ServiceExt;
#[tokio::test]
async fn item_descriptor_preserves_state_and_png_never_leaks_private_rows(){
 let t=TestApp::new().await;t.seed_cortex().await;
 t.ingest(json!([event("preview","ollama","local",100,10,true)])).await;
 let base="/projects/cortex/showcase/token-usage/cards/tokens-by-provider";
 let (status,value,_)=t.call("GET",&format!("{base}/embed?view=table&f.provider=ollama&lang=en"),&[],None).await;
 assert_eq!(status,StatusCode::OK,"{value}");
 assert!(value["embed_url"].as_str().unwrap().contains("/v1/embed/"));assert!(value["embed_url"].as_str().unwrap().contains("view=table"));assert!(value["html"].as_str().unwrap().contains("&amp;"));
 let response=t.app.clone().oneshot(Request::builder().uri(format!("{base}/thumbnail.png?view=table")).body(Body::empty()).unwrap()).await.unwrap();
 assert_eq!(response.status(),StatusCode::OK);assert_eq!(response.headers()["content-type"],"image/png");
 let bytes=to_bytes(response.into_body(),2_000_000).await.unwrap();assert_eq!(&bytes[..8],b"\x89PNG\r\n\x1a\n");
 let (status,_) = t.service("PUT","/projects/cortex/admin/reports/token-usage/datasets/tokens-by-provider",dataset("tokens-by-provider","restricted")).await;assert_eq!(status,StatusCode::OK);
 let (status,_,_)=t.call("GET",&format!("{base}/embed"),&[],None).await;assert!(!status.is_success());
 let response=t.app.clone().oneshot(Request::builder().uri(format!("{base}/thumbnail.png")).body(Body::empty()).unwrap()).await.unwrap();assert!(!response.status().is_success());
}
