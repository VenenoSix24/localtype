use std::{
    collections::HashMap,
    fs::{self, File},
    io::BufReader,
    path::PathBuf,
    sync::{Arc, Mutex},
    time::{Duration, Instant},
};

use directories::ProjectDirs;
use rand::Rng;
use serde::{Deserialize, Serialize};
use std::sync::atomic::{AtomicU64, Ordering};
use tokio::sync::mpsc;

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct TrustedClient {
    pub id: String,
    pub name: String,
    pub alias: Option<String>,
    pub os: Option<String>,
    pub token: String,
    pub last_seen: u64,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct AppConfig {
    pub device_name: String,
}

impl Default for AppConfig {
    fn default() -> Self {
        Self {
            device_name: hostname::get()
                .map(|h| h.to_string_lossy().into_owned())
                .unwrap_or_else(|_| "TypeBridge Desktop".to_string()),
        }
    }
}

#[derive(Clone)]
pub struct ServerState {
    pub trusted_clients: Arc<Mutex<HashMap<String, TrustedClient>>>,
    pub config: Arc<Mutex<AppConfig>>,
    pub pending_pair_codes: Arc<Mutex<HashMap<String, (String, Instant)>>>,
    pub active_sessions: Arc<Mutex<HashMap<String, (String, u64)>>>, // device_id -> (IP, session_id)
    pub active_connections: Arc<Mutex<HashMap<String, mpsc::UnboundedSender<String>>>>, // device_id -> sender
    pub session_counter: Arc<AtomicU64>,
    devices_path: PathBuf,
    config_path: PathBuf,
}

impl ServerState {
    pub fn new() -> Self {
        let proj_dirs = ProjectDirs::from("com", "typebridge", "desktop")
            .expect("Could not determine config directory");
        let config_dir = proj_dirs.config_dir();
        fs::create_dir_all(config_dir).ok();
        
        let devices_path = config_dir.join("trusted_devices.json");
        let config_path = config_dir.join("config.json");

        let trusted_clients = Self::load_trusted_clients(&devices_path)
            .unwrap_or_else(|_| HashMap::new());
            
        let config = Self::load_config(&config_path)
            .unwrap_or_default();

        ServerState {
            trusted_clients: Arc::new(Mutex::new(trusted_clients)),
            config: Arc::new(Mutex::new(config)),
            pending_pair_codes: Arc::new(Mutex::new(HashMap::new())),
            active_sessions: Arc::new(Mutex::new(HashMap::new())),
            active_connections: Arc::new(Mutex::new(HashMap::new())),
            session_counter: Arc::new(AtomicU64::new(0)),
            devices_path,
            config_path,
        }
    }

    pub fn next_session_id(&self) -> u64 {
        self.session_counter.fetch_add(1, Ordering::SeqCst)
    }

    fn load_config(path: &PathBuf) -> Option<AppConfig> {
        let file = File::open(path).ok()?;
        let reader = BufReader::new(file);
        serde_json::from_reader(reader).ok()
    }

    pub fn save_config(&self) -> anyhow::Result<()> {
        let config = self.config.lock().unwrap();
        let file = File::create(&self.config_path)?;
        serde_json::to_writer_pretty(file, &*config)?;
        Ok(())
    }

    fn load_trusted_clients(path: &PathBuf) -> anyhow::Result<HashMap<String, TrustedClient>> {
        let file = File::open(path)?;
        let reader = BufReader::new(file);
        let clients: HashMap<String, TrustedClient> = serde_json::from_reader(reader)?;
        Ok(clients)
    }

    pub fn save_trusted_clients(&self) -> anyhow::Result<()> {
        let clients = self.trusted_clients.lock().unwrap();
        let file = File::create(&self.devices_path)?;
        serde_json::to_writer_pretty(file, &*clients)?;
        Ok(())
    }

    pub fn is_trusted(&self, client_id: &str, token: &str) -> bool {
        let clients = self.trusted_clients.lock().unwrap();
        if let Some(client) = clients.get(client_id) {
            return client.token == token;
        }
        false
    }

    pub fn generate_pairing_code(&self, client_id: &str) -> String {
        let mut rng = rand::thread_rng();
        let code: String = (0..6).map(|_| rng.gen_range(0..10).to_string()).collect();

        let mut pending = self.pending_pair_codes.lock().unwrap();
        pending.insert(
            client_id.to_string(),
            (code.clone(), Instant::now() + Duration::from_secs(60)),
        );

        log::info!("==== 配对码: {} (设备: {}) ====", code, client_id);
        code
    }

    pub fn verify_pairing_code(
        &self,
        client_id: &str,
        code: &str,
        client_name: &str,
        os: Option<String>,
    ) -> Option<String> {
        let mut pending = self.pending_pair_codes.lock().unwrap();

        if let Some((stored_code, expiry)) = pending.get(client_id) {
            if Instant::now() > *expiry {
                pending.remove(client_id);
                return None;
            }
            if stored_code == code {
                let token: String = rand::thread_rng()
                    .sample_iter(&rand::distributions::Alphanumeric)
                    .take(32)
                    .map(char::from)
                    .collect();

                let mut clients = self.trusted_clients.lock().unwrap();
                clients.insert(
                    client_id.to_string(),
                    TrustedClient {
                        id: client_id.to_string(),
                        name: client_name.to_string(),
                        alias: None,
                        os,
                        token: token.clone(),
                        last_seen: 0,
                    },
                );

                drop(clients);
                let _ = self.save_trusted_clients();
                pending.remove(client_id);
                return Some(token);
            }
        }
        None
    }

    /// 获取已信任设备列表（用于前端展示）
    pub fn get_device_list(&self) -> Vec<TrustedClient> {
        let clients = self.trusted_clients.lock().unwrap();
        clients.values().cloned().collect()
    }

    /// 移除已信任设备
    pub fn remove_device(&self, device_id: &str) {
        let mut clients = self.trusted_clients.lock().unwrap();
        clients.remove(device_id);
        drop(clients);
        let _ = self.save_trusted_clients();
        
        // 同时也尝试断开活跃连接并正式通知解除配对
        self.unpair_device(device_id);
    }

    /// 断开特定设备的连接并发送解除配对通知
    pub fn unpair_device(&self, device_id: &str) {
        let mut connections = self.active_connections.lock().unwrap();
        if let Some(tx) = connections.remove(device_id) {
            let _ = tx.send("unpaired".to_string());
        }
    }

    /// 仅断开旧连接（重连场景）
    pub fn kick_device(&self, device_id: &str) {
        let mut connections = self.active_connections.lock().unwrap();
        if let Some(tx) = connections.remove(device_id) {
            let _ = tx.send("kick".to_string());
        }
    }

    /// 更新设备操作系统信息
    pub fn update_client_os(&self, device_id: &str, os: &str) {
        let mut clients = self.trusted_clients.lock().unwrap();
        if let Some(client) = clients.get_mut(device_id) {
            if client.os.as_deref() != Some(os) {
                client.os = Some(os.to_string());
                drop(clients);
                let _ = self.save_trusted_clients();
            }
        }
    }
}
