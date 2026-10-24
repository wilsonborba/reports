use clap::Parser;
use reports::core::config::Settings;
use reports::presentation::api::server::run_server;
use reports::presentation::cli::{cli::Commands, Cli};
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    dotenvy::dotenv().ok();

    tracing_subscriber::registry()
        .with(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "reports=info,tower_http=info".into()),
        )
        .with(tracing_subscriber::fmt::layer())
        .init();

    let cli = Cli::parse();
    let mut settings = Settings::default();

    match cli.command {
        Commands::Serve { port, host } => {
            settings.server_port = port;
            settings.server_host = host;
            run_server(settings).await?;
        }
    }
    Ok(())
}
