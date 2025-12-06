use std::error::Error;
use std::fs;

use three_body::{ThreeBodyConfig, init_with_config};
use nockapp::{http_driver, one_punch_driver};
use nockapp::driver::Operation;
use nockapp::kernel::boot;
use nockapp::kernel::boot::NockStackSize;
use nockapp::noun::slab::NounSlab;
use nockapp::NockApp;
use nockvm::noun::{D, T};
use nockvm_macros::tas;
use tracing::{info, warn};

#[tokio::main]
async fn main() -> Result<(), Box<dyn Error>> {
    let cli = boot::default_boot_cli(false);
    boot::init_default_tracing(&cli);

    // Install default crypto provider before any TLS connections
    rustls::crypto::aws_lc_rs::default_provider()
        .install_default()
        .expect("default provider already set elsewhere");

    // Load configuration from TOML file
    let config_path = "three-body-config.toml";
    let config = match ThreeBodyConfig::load(config_path) {
        Ok(cfg) => {
            info!("Successfully loaded config from {}", config_path);
            cfg
        }
        Err(e) => {
            warn!("Failed to load config from {}: {}", config_path, e);
            warn!("Falling back to hardcoded config (for development only)");
            // Fallback to hardcoded config for development
            ThreeBodyConfig {
                physics: three_body::PhysicsConfig {
                    gravitational_constant: 1.0,
                    time_step: 0.001,
                },
                server: three_body::ServerConfig {
                    wallet_pkh: "9yPePjfWAdUnzaQKyxcRXKRa5PpUzKKEwtpECBZsUYt9Jd7egSDEWoV".to_string(),
                    private_key: "PLACEHOLDER_PRIVKEY".to_string(),
                },
            }
        }
    };

    // Load kernel
    let kernel = fs::read("out.jam").map_err(|e| format!("Failed to read out.jam: {}", e))?;

    let mut nockapp: NockApp = boot::setup(&kernel, cli.clone(), &[], "blackjack", None)
        .await
        .map_err(|e| format!("Kernel setup failed: {}", e))?;

    // Initialize with config (poke config into kernel)
    if let Err(e) = init_with_config(&mut nockapp, &config).await {
        warn!("Failed to initialize with config: {}", e);
        warn!("Continuing with default kernel state");
    }

    let mut boot_config = boot::default_boot_cli(false);
    boot_config.stack_size = NockStackSize::Tiny;

    info!("Adding I/O drivers");

    // Prepare the initial poke to trigger the tx effect
    let mut poke_slab = NounSlab::new();
    let cause_noun = T(&mut poke_slab, &[D(tas!(b"born")), D(0x0)]);
    poke_slab.set_root(cause_noun);

    nockapp
        .add_io_driver(one_punch_driver(poke_slab, Operation::Poke))
        .await;
    nockapp.add_io_driver(http_driver()).await;
    info!("Starting three-body HTTP server...");
    nockapp.run().await.expect("Failed to run app");

    Ok(())
}
