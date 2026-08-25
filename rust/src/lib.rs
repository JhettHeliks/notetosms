pub mod api;
pub mod crypto;
pub mod p2p;
pub mod p2p_protocol;
pub mod storage;
mod frb_generated;

use std::sync::OnceLock;
use tokio::runtime::Runtime;

pub fn get_runtime() -> &'static Runtime {
    static RUNTIME: OnceLock<Runtime> = OnceLock::new();
    RUNTIME.get_or_init(|| {
        tokio::runtime::Builder::new_multi_thread()
            .enable_all()
            .build()
            .expect("Failed to initialize Tokio runtime")
    })
}
