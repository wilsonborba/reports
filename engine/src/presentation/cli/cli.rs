use clap::{Parser, Subcommand};

#[derive(Parser, Debug)]
#[command(name = "reports", author = "Wilson Borba", version)]
#[command(about = "Asodya Reports engine: headless JSON API behind api_for_apps", long_about = None)]
pub struct Cli {
    #[command(subcommand)]
    pub command: Commands,
}

#[derive(Subcommand, Debug)]
pub enum Commands {
    /// Start the JSON API. The database must already be migrated (scripts/migrate.sh).
    Serve {
        #[arg(short, long, env = "SERVER_PORT", default_value_t = crate::core::config::DEFAULT_PORT)]
        port: u16,

        #[arg(long, env = "SERVER_HOST", default_value = crate::core::config::DEFAULT_HOST)]
        host: String,
    },
}
