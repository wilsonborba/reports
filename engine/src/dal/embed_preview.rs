//! Captures the actual Reports Flutter card through Chrome DevTools.
use crate::core::{config::Settings, error::ReportError};
use base64::Engine;
use futures_util::{SinkExt, StreamExt};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::{sync::OnceLock, time::Duration};
use tokio::{net::TcpStream, sync::Semaphore};
use tokio_tungstenite::{tungstenite::Message, MaybeTlsStream, WebSocketStream};
fn unavailable() -> ReportError {
    ReportError::Unavailable("Reports preview renderer unavailable".into())
}
pub fn cache_key(url: &str, page: &crate::domain::datasets::DatasetPage) -> String {
    let content = serde_json::to_vec(page).unwrap_or_default();
    format!(
        "embed-original-v1:{}",
        hex::encode(Sha256::digest([url.as_bytes(), &content].concat()))
    )
}
struct Browser {
    socket: WebSocketStream<MaybeTlsStream<TcpStream>>,
    id: u64,
    session: Option<String>,
}
impl Browser {
    async fn call(&mut self, method: &str, params: Value) -> Result<Value, ReportError> {
        self.id += 1;
        let mut message = json!({"id":self.id,"method":method,"params":params});
        if let Some(session) = &self.session {
            message["sessionId"] = json!(session);
        }
        self.socket
            .send(Message::Text(message.to_string().into()))
            .await
            .map_err(|_| unavailable())?;
        while let Some(message) = self.socket.next().await {
            let message = message.map_err(|_| unavailable())?;
            if let Message::Text(text) = message {
                let value: Value = serde_json::from_str(&text).map_err(|_| unavailable())?;
                if value["id"] == self.id {
                    if value.get("error").is_some() {
                        return Err(unavailable());
                    }
                    return Ok(value["result"].clone());
                }
            }
        }
        Err(unavailable())
    }
}
pub async fn capture(settings: &Settings, url: &str) -> Result<Vec<u8>, ReportError> {
    let parsed = url::Url::parse(url).map_err(|_| unavailable())?;
    if parsed.scheme() != "https"
        || parsed.host_str() != Some("reports.asodya.com")
        || !parsed.path().starts_with("/v1/embed/")
    {
        return Err(unavailable());
    }
    // Isolated tests seed a captured fixture; they never browse production.
    if settings.environment == "test" {
        return Err(unavailable());
    }
    static GATE: OnceLock<Semaphore> = OnceLock::new();
    let _permit = tokio::time::timeout(
        Duration::from_secs(2),
        GATE.get_or_init(|| Semaphore::new(1)).acquire(),
    )
    .await
    .map_err(|_| unavailable())?
    .map_err(|_| unavailable())?;
    let directory = tempfile::tempdir().map_err(|_| unavailable())?;
    let mut child = tokio::process::Command::new(&settings.embed_chrome_binary)
        .args([
            "--headless",
            "--no-first-run",
            "--no-default-browser-check",
            "--hide-scrollbars",
            "--disable-dev-shm-usage",
            // Without a session keyring, Chrome otherwise waits on D-Bus before the first request.
            "--password-store=basic",
            "--remote-debugging-port=0",
        ])
        .arg(format!("--user-data-dir={}", directory.path().display()))
        .arg("about:blank")
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .kill_on_drop(true)
        .spawn()
        .map_err(|_| unavailable())?;
    let result=tokio::time::timeout(Duration::from_secs(25),async {
        let address=loop {
            if let Ok(port_file)=tokio::fs::read_to_string(directory.path().join("DevToolsActivePort")).await {
                let mut lines=port_file.lines();
                if let (Some(port),Some(path))=(lines.next(),lines.next()) { break format!("ws://127.0.0.1:{port}{path}"); }
            }
            tokio::time::sleep(Duration::from_millis(50)).await;
        };
        let (socket,_)=tokio_tungstenite::connect_async(address).await.map_err(|_|unavailable())?;
        let mut browser=Browser{socket,id:0,session:None};
        let target=browser.call("Target.createTarget",json!({"url":"about:blank"})).await?;
        let session=browser.call("Target.attachToTarget",json!({"targetId":target["targetId"],"flatten":true})).await?;
        browser.session=Some(session["sessionId"].as_str().ok_or_else(unavailable)?.into());
        browser.call("Page.enable",json!({})).await?;
        browser.call("Emulation.setDeviceMetricsOverride",json!({"width":800,"height":480,"deviceScaleFactor":1,"mobile":false})).await?;
        browser.call("Page.navigate",json!({"url":url})).await?;
        loop {
            let state=browser.call("Runtime.evaluate",json!({"expression":"document.documentElement.getAttribute('data-reports-embed-ready') === 'true'","returnByValue":true})).await?;
            if state["result"]["value"]==true {break;}
            tokio::time::sleep(Duration::from_millis(100)).await;
        }
        tokio::time::sleep(Duration::from_millis(400)).await;
        let image=browser.call("Page.captureScreenshot",json!({"format":"png","captureBeyondViewport":false,"fromSurface":true})).await?;
        let bytes=base64::engine::general_purpose::STANDARD.decode(image["data"].as_str().ok_or_else(unavailable)?).map_err(|_|unavailable())?;
        browser.session=None;
        let _=browser.call("Browser.close",json!({})).await;
        if bytes.len()>8_000_000 || !bytes.starts_with(b"\x89PNG\r\n\x1a\n") { return Err(unavailable()); }
        Ok(bytes)
    }).await.map_err(|_|unavailable()).and_then(|v|v);
    let _ = child.kill().await;
    let _ = child.wait().await;
    result
}
