use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::Path;

use nockapp::NockApp;
use tracing::info;

/// Configuration for the Three-Body server
#[derive(Debug, Deserialize, Serialize, Clone)]
pub struct ThreeBodyConfig {
    pub physics: PhysicsConfig,
    pub server: ServerConfig,
}

impl ThreeBodyConfig {
    /// Load configuration from a TOML file
    pub fn load<P: AsRef<Path>>(path: P) -> Result<Self> {
        let contents = fs::read_to_string(path.as_ref())
            .context("Failed to read config file")?;
        let config: ThreeBodyConfig = toml::from_str(&contents)
            .context("Failed to parse config TOML")?;
        Ok(config)
    }
}

/// Physics-related configuration
/// E.g., gravitational constant, time step, etc.
#[derive(Debug, Deserialize, Serialize, Clone)]
pub struct PhysicsConfig {
    pub gravitational_constant: f64,
    pub time_step: f64,
    // Initial conditions
}

#[derive(Debug, Deserialize, Serialize, Clone)]
pub struct ServerConfig {
    pub wallet_pkh: String,
    pub private_key: String,
}

/// Initialize the NockApp with configuration by poking the config into the kernel
pub async fn init_with_config(_nockapp: &mut NockApp, config: &ThreeBodyConfig) -> Result<()> {
    info!("Config loaded: wallet_pkh={}", config.server.wallet_pkh);
    info!("Physics params: G={}, dt={}", config.physics.gravitational_constant, config.physics.time_step);

    // TODO: Implement config poke into kernel
    // For now, the kernel uses default config
    info!("Using default kernel configuration");

    Ok(())
}
