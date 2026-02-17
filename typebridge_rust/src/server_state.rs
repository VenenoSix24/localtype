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

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct TrustedClient {
    pub id: String,
    pub name: String,
    pub token: String,
    pub last_seen: u64,
}

#[derive(Clone)]
pub struct ServerState {
    pub trusted_clients: Arc<Mutex<HashMap<String, TrustedClient>>>,
    pub pending_pair_codes: Arc<Mutex<HashMap<String, (String, Instant)>>>, // ClientID -> (Code, Expiry)
    config_path: PathBuf,
}

impl ServerState {
    pub fn new() -> Self {
        let proj_dirs = ProjectDirs::from("com", "localtype", "rustserver")
            .expect("Could not determine config directory");
        let config_dir = proj_dirs.config_dir();
        fs::create_dir_all(config_dir).ok();
        let config_path = config_dir.join("trusted_devices.json");

        let trusted_clients = Self::load_trusted_clients(&config_path).unwrap_or_else(|_| HashMap::new());

        ServerState {
            trusted_clients: Arc::new(Mutex::new(trusted_clients)),
            pending_pair_codes: Arc::new(Mutex::new(HashMap::new())),
            config_path,
        }
    }

    fn load_trusted_clients(path: &PathBuf) -> anyhow::Result<HashMap<String, TrustedClient>> {
        let file = File::open(path)?;
        let reader = BufReader::new(file);
        let clients: HashMap<String, TrustedClient> = serde_json::from_reader(reader)?;
        Ok(clients)
    }

    pub fn save_trusted_clients(&self) -> anyhow::Result<()> {
        let clients = self.trusted_clients.lock().unwrap();
        let file = File::create(&self.config_path)?;
        serde_json::to_writer_pretty(file, &*clients)?;
        Ok(())
    }

    pub fn is_trusted(&self, client_id: &str, token: &str) -> bool {
        let clients = self.trusted_clients.lock().unwrap();
        if let Some(client) = clients.get(client_id) {
            // Simple token match. In production, use hash comparison.
            return client.token == token;
        }
        false
    }

    pub fn generate_pairing_code(&self, client_id: &str) -> String {
        let mut rng = rand::thread_rng();
        let code: String = (0..6).map(|_| rng.gen_range(0..10).to_string()).collect();
        
        let mut pending = self.pending_pair_codes.lock().unwrap();
        pending.insert(client_id.to_string(), (code.clone(), Instant::now() + Duration::from_secs(60)));
        
        println!("==== PAIRING CODE ====");
        println!("Client {} requested pairing.", client_id);
        println!("Code: {}", code);
        println!("======================");

        code
    }

    pub fn verify_pairing_code(&self, client_id: &str, code: &str, client_name: &str) -> Option<String> {
        let mut pending = self.pending_pair_codes.lock().unwrap();
        
        if let Some((stored_code, expiry)) = pending.get(client_id) {
            if Instant::now() > *expiry {
                pending.remove(client_id);
                return None;
            }
            if stored_code == code {
                // Generate Token
                let token: String = rand::thread_rng()
                    .sample_iter(&rand::distributions::Alphanumeric)
                    .take(32)
                    .map(char::from)
                    .collect();

                // Trust client
                let mut clients = self.trusted_clients.lock().unwrap();
                clients.insert(client_id.to_string(), TrustedClient {
                    id: client_id.to_string(),
                    name: client_name.to_string(),
                    token: token.clone(),
                    last_seen: 0, 
                });
                
                // Save to disk
                drop(clients); // Unlock before saving to avoid deadlock if save takes long (though here it's fine)
                let _ = self.save_trusted_clients(); // Ignore error for now

                pending.remove(client_id);
                return Some(token);
            }
        }
        None
    }
}
