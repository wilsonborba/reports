use clap::Parser;
use reports::core::config::Settings;
use reports::presentation::api::server::run_server;
use reports::presentation::cli::{cli::Commands, Cli};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    dotenvy::dotenv().ok();

    let cli = Cli::parse();
    let mut settings = Settings::default();
    reports::core::logs::init(&settings, reports::core::logs::sender());

    match cli.command {
        Commands::Serve { port, host } => {
            settings.server_port = port;
            settings.server_host = host;
            run_server(settings).await?;
        }
    }
    Ok(())
}
