use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::Path;

use nockapp::noun::slab::NounSlab;
use nockapp::utils::make_tas;
use nockapp::NockApp;
use nockchain_math::noun_ext::NounMathExt;
use nockvm::noun::{Noun, D, T, YES, NO};
use nockvm_macros::tas;
use tracing::info;

/// Configuration for the Three-Body server
#[derive(Debug, Deserialize, Serialize, Clone)]
pub struct ThreeBodyConfig {
    pub physics: PhysicsConfig,
    pub server: ServerConfig,
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
