use std::{
    net::SocketAddr,
    sync::{Arc, atomic::{AtomicBool, Ordering}},
};

use futures_util::{StreamExt, SinkExt};
use log::{info, error, debug};
use tokio::net::{TcpListener, UdpSocket};
use tokio_tungstenite::tungstenite::Message;
use serde::{Deserialize, Serialize};
use native_dialog::{DialogBuilder, MessageLevel};

use tray_icon::{
    menu::{Menu, MenuEvent, MenuItem, PredefinedMenuItem},
    TrayIconBuilder,
};
use tao::event_loop::{ControlFlow, EventLoopBuilder};
use enigo::{Enigo, Settings, Keyboard, Key, Direction};

use tokio_rustls::rustls::{ServerConfig, Certificate, PrivateKey};
use tokio_rustls::TlsAcceptor;

// Core configuration
const WSS_PORT: u16 = 8765;
const UDP_PORT: u16 = 45678;

mod server_state;
use server_state::ServerState;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    env_logger::init_from_env(env_logger::Env::default().default_filter_or("info"));
    info!("TypeBridge Server Starting...");

    let event_loop = EventLoopBuilder::new().build();

    let tray_menu = Menu::new();
    let status_i = MenuItem::new("状态: 就绪", false, None);
    let pause_i = MenuItem::new("暂停注入", true, None);
    let quit_i = MenuItem::new("退出", true, None);
    
    tray_menu.append(&status_i)?;
    tray_menu.append(&pause_i)?;
    tray_menu.append(&PredefinedMenuItem::separator())?;
    tray_menu.append(&quit_i)?;

    let mut tray_icon = Some(
        TrayIconBuilder::new()
            .with_menu(Box::new(tray_menu))
            .with_tooltip("TypeBridge Server")
            .with_icon(load_icon())
            .build()?,
    );

    let is_paused = Arc::new(AtomicBool::new(false));
    let is_paused_server = is_paused.clone();

    // Use a channel to send status updates to the main thread
    let (status_tx, mut status_rx) = tokio::sync::mpsc::unbounded_channel::<String>();

    // Spawn server thread
    std::thread::spawn(move || {
        let rt = tokio::runtime::Runtime::new().unwrap();
        rt.block_on(async {
            let state = ServerState::new();

            // TLS Configuration
            let tls_acceptor = match get_tls_acceptor() {
                Ok(a) => a,
                Err(e) => {
                    error!("TLS Setup Error: {}", e);
                    return;
                }
            };

            // Start UDP Discovery
            tokio::spawn(async move {
                if let Err(e) = run_discovery_service().await {
                    error!("UDP Discovery Error: {}", e);
                }
            });

            // Start WSS Server
            let addr = format!("0.0.0.0:{}", WSS_PORT);
            let listener = TcpListener::bind(&addr).await.unwrap();
            info!("WSS listening on: {}", addr);

            while let Ok((stream, addr)) = listener.accept().await {
                let state = state.clone();
                let status_tx = status_tx.clone();
                let is_paused = is_paused_server.clone();
                let acceptor = tls_acceptor.clone();
                
                tokio::spawn(async move {
                    match acceptor.accept(stream).await {
                        Ok(tls_stream) => {
                             accept_connection(tls_stream, addr, state, status_tx, is_paused).await;
                        }
                        Err(e) => error!("TLS handshake error from {}: {}", addr, e),
                    }
                });
            }
        });
    });

    // Run Event Loop
    let menu_channel = MenuEvent::receiver();
    
    event_loop.run(move |_event, _, control_flow| {
        *control_flow = ControlFlow::Wait;

        // Poll for menu events
        if let Ok(event) = menu_channel.try_recv() {
            if event.id == quit_i.id() {
                tray_icon.take(); // Remove icon
                *control_flow = ControlFlow::Exit;
            } else if event.id == pause_i.id() {
                let current = is_paused.load(Ordering::Relaxed);
                let new_state = !current;
                is_paused.store(new_state, Ordering::Relaxed);
                
                let _ = pause_i.set_text(if new_state { "恢复注入" } else { "暂停注入" });
                info!("Injection {}", if new_state { "Paused" } else { "Resumed" });
            }
        }

        // Poll for status updates
        while let Ok(new_status) = status_rx.try_recv() {
            let _ = status_i.set_text(new_status);
        }
    });
}

fn load_icon() -> tray_icon::Icon {
    let width = 32;
    let height = 32;
    let mut rgba = Vec::with_capacity((width * height * 4) as usize);
    
    // Indigo-like color for the background (Material 3 seed color theme)
    let bg_r = 63;
    let bg_g = 81;
    let bg_b = 181;

    for y in 0..height {
        for x in 0..width {
            // Draw a blocky white 'T'
            let is_t = (y >= 6 && y <= 10 && x >= 6 && x <= 26) // Top bar of T
                    || (y >= 10 && y <= 26 && x >= 14 && x <= 18); // Vertical bar of T
            
            if is_t {
                rgba.extend_from_slice(&[255, 255, 255, 255]);
            } else {
                rgba.extend_from_slice(&[bg_r, bg_g, bg_b, 255]);
            }
        }
    }
    tray_icon::Icon::from_rgba(rgba, width, height).unwrap()
}

async fn run_discovery_service() -> std::io::Result<()> {
    let socket = UdpSocket::bind(format!("0.0.0.0:{}", UDP_PORT)).await?;
    socket.set_broadcast(true)?;
    info!("Discovery service listening on UDP {}", UDP_PORT);

    let mut buf = [0u8; 1024];

    loop {
        // Find local IP address to respond with
        let local_ip = local_ip_address::local_ip().unwrap_or("127.0.0.1".parse().unwrap());
        
        let (len, addr) = socket.recv_from(&mut buf).await?;
        let msg = String::from_utf8_lossy(&buf[..len]);
        debug!("Received UDP broadcast from {}: {}", addr, msg);

        if msg.trim() == "typebridge_discovery" {
            let response = format!("typebridge_server:{}", local_ip);
            socket.send_to(response.as_bytes(), addr).await?;
            info!("Responded to discovery from {}", addr);
        }
    }
}

async fn accept_connection<S>(
    stream: S, 
    addr: SocketAddr, 
    state: ServerState,
    status_tx: tokio::sync::mpsc::UnboundedSender<String>,
    is_paused: Arc<AtomicBool>,
) where S: tokio::io::AsyncRead + tokio::io::AsyncWrite + Unpin {
    info!("Incoming connection from: {}", addr);
    let _ = status_tx.send(format!("Status: Connecting {}", addr.ip()));

    let ws_stream = match tokio_tungstenite::accept_async(stream).await {
        Ok(ws) => ws,
        Err(e) => {
            error!("Error during the websocket handshake occurred: {}", e);
             let _ = status_tx.send("Status: Handshake Error".to_string());
            return;
        }
    };

    info!("WebSocket connection established: {}", addr);
    let _ = status_tx.send(format!("Status: Connected {}", addr.ip()));

    let (mut write, mut read) = ws_stream.split();
    let mut last_text = String::new();
    let mut authenticated_device_name: Option<String> = None;

    while let Some(msg) = read.next().await {
        match msg {
            Ok(Message::Text(text)) => {
                debug!("Received: {}", text);
                
                match serde_json::from_str::<ClientMessage>(&text) {
                    Ok(client_msg) => {
                        match client_msg {
                            ClientMessage::Ping => {
                                let pong = serde_json::to_string(&ClientMessage::Pong).unwrap();
                                if let Err(e) = write.send(Message::Text(pong)).await {
                                    error!("Failed to send Pong: {}", e);
                                    break;
                                }
                            },
                            ClientMessage::Pong => {},
                            ClientMessage::RequestPairing { device_name, device_id } => {
                                info!("Pairing requested by {} ({})", device_name, device_id);
                                
                                let code = state.generate_pairing_code(&device_id);
                                let _ = status_tx.send(format!("配对码: {} ({})", code, device_name));

                                // NOTE: 在独立线程中弹出原生对话框
                                // 不能阻塞 async 运行时，否则会死锁
                                let dialog_device_name = device_name.clone();
                                let dialog_code = code.clone();
                                std::thread::spawn(move || {
                                    let _ = DialogBuilder::message()
                                        .set_level(MessageLevel::Info)
                                        .set_title("TypeBridge 配对验证")
                                        .set_text(format!(
                                            "设备 {} 请求配对\n\n验证码: {}",
                                            dialog_device_name, dialog_code
                                        ))
                                        .alert()
                                        .show();
                                });

                                let response = serde_json::to_string(&ServerResponse::PairingCodeRequired).unwrap();
                                let _ = write.send(Message::Text(response)).await;
                            },
                            ClientMessage::VerifyPairing { device_id, code, device_name } => {
                                if let Some(token) = state.verify_pairing_code(&device_id, &code, &device_name) {
                                    info!("Pairing successful for {}", device_name);
                                    authenticated_device_name = Some(device_name.clone());
                                    let _ = status_tx.send(format!("已连接: {}", device_name));
                                    
                                    let response = serde_json::to_string(&ServerResponse::PairingSuccess { token }).unwrap();
                                    let _ = write.send(Message::Text(response)).await;
                                } else {
                                    info!("Pairing failed for {}", device_name);
                                    let response = serde_json::to_string(&ServerResponse::Error { message: "Invalid code".into() }).unwrap();
                                    let _ = write.send(Message::Text(response)).await;
                                }
                            },
                            ClientMessage::Auth { device_id, token } => {
                                if state.is_trusted(&device_id, &token) {
                                    info!("Client authenticated: {}", device_id);
                                    authenticated_device_name = Some(device_id.clone());
                                    let _ = status_tx.send(format!("已连接: {}", device_id));
                                    
                                    let response = serde_json::to_string(&ServerResponse::AuthSuccess).unwrap();
                                    let _ = write.send(Message::Text(response)).await;
                                } else {
                                    info!("Auth failed for: {}", device_id);
                                    let response = serde_json::to_string(&ServerResponse::AuthFailed).unwrap();
                                    let _ = write.send(Message::Text(response)).await;
                                }
                            },
                            ClientMessage::Send { mode, content, method } => {
                                if authenticated_device_name.is_some() {
                                    if is_paused.load(Ordering::Relaxed) {
                                         continue;
                                    }
                                
                                    // NOTE: 注入方式完全由手机端控制
                                    let injection_method = method.unwrap_or_else(|| "unicode".to_string());

                                    if mode == "realtime" {
                                        // Incremental Update Logic
                                        if content.starts_with(&last_text) {
                                            let diff = &content[last_text.len()..];
                                            if !diff.is_empty() {
                                                perform_injection(diff, &injection_method).await;
                                            }
                                            last_text = content;
                                        } else {
                                            if content.is_empty() {
                                                last_text.clear();
                                            } else {
                                                last_text = content; 
                                            }
                                        }
                                    } else {
                                        // Chat Mode: Inject all
                                        perform_injection(&content, &injection_method).await;
                                        last_text.clear();
                                    }
                                } else {
                                    // Not authenticated
                                    let response = serde_json::to_string(&ServerResponse::Error{ message: "Not authenticated".into() }).unwrap();
                                    let _ = write.send(Message::Text(response)).await;
                                }
                            },
                            ClientMessage::Reset => {
                                info!("State Reset");
                                last_text.clear();
                            }
                        }
                    },
                    Err(e) => error!("JSON Parsing Error: {}", e),
                }
            }
            Ok(Message::Close(_)) => {
                info!("Connection closed by client: {}", addr);
                break;
            }
            Err(e) => {
                error!("Error processing message: {}", e);
                break;
            }
            _ => {}
        }
    }
    
    let _ = status_tx.send("状态: 就绪".to_string());
}

#[derive(Serialize, Deserialize, Debug)]
#[serde(tag = "type", rename_all = "lowercase")]
enum ClientMessage {
    Ping,
    Pong,
    RequestPairing { device_name: String, device_id: String },
    VerifyPairing { device_id: String, code: String, device_name: String },
    Auth { device_id: String, token: String },
    Send { mode: String, content: String, method: Option<String> },
    Reset,
}

#[derive(Serialize, Deserialize, Debug)]
#[serde(tag = "type", rename_all = "lowercase")]
enum ServerResponse {
    Pong,
    PairingCodeRequired,
    PairingSuccess { token: String },
    AuthSuccess,
    AuthFailed,
    Error { message: String },
}


async fn perform_injection(text: &str, method: &str) {
    if method == "clipboard" {
        inject_via_clipboard(text).await;
    } else {
        inject_text(text).await;
    }
}

async fn inject_text(text: &str) {
    info!("Injecting text ({} chars)", text.len());
    let text = text.to_string();
    std::thread::spawn(move || {
        let mut enigo = match Enigo::new(&Settings::default()) {
            Ok(e) => e,
            Err(e) => {
                error!("Failed to initialize Enigo: {:?}", e);
                return;
            }
        };

        // NOTE: 不能直接用 enigo.text() 注入整段文本，因为在微信/QQ 等 IM 中
        // \n 会被当作 Enter 键事件导致消息提前发送。
        // 策略：按换行符拆分文本，逐段注入，换行处用 Shift+Enter 模拟软回车。
        let normalized = text.replace("\r\n", "\n");
        let lines: Vec<&str> = normalized.split('\n').collect();

        for (i, line) in lines.iter().enumerate() {
            if !line.is_empty() {
                let _ = enigo.text(line);
            }
            // 除最后一行外，每行后插入 Shift+Enter（软回车）
            if i < lines.len() - 1 {
                let _ = enigo.key(Key::Shift, Direction::Press);
                let _ = enigo.key(Key::Return, Direction::Click);
                let _ = enigo.key(Key::Shift, Direction::Release);
                // 短暂延迟确保按键事件被目标应用处理
                std::thread::sleep(std::time::Duration::from_millis(10));
            }
        }
    });
}

async fn inject_via_clipboard(text: &str) {
    info!("Injecting via clipboard ({} chars)", text.len());
    let text = text.to_string();
    std::thread::spawn(move || {
        let mut clipboard = arboard::Clipboard::new().expect("Failed to open clipboard");
        let original_content = clipboard.get_text().ok();
        
        let _ = clipboard.set_text(text);
        
        // Trigger Paste (Cmd+V on Mac, Ctrl+V on Windows)
        let mut enigo = Enigo::new(&Settings::default()).expect("Failed to initialize Enigo");
        #[cfg(target_os = "macos")]
        {
            let _ = enigo.key(Key::Meta, Direction::Press);
            let _ = enigo.key(Key::Unicode('v'), Direction::Click);
            let _ = enigo.key(Key::Meta, Direction::Release);
        }
        #[cfg(not(target_os = "macos"))]
        {
            let _ = enigo.key(Key::Control, Direction::Press);
            let _ = enigo.key(Key::Unicode('v'), Direction::Click);
            let _ = enigo.key(Key::Control, Direction::Release);
        }

        // Delay slightly before restoring to ensure the app processed the paste
        std::thread::sleep(std::time::Duration::from_millis(100));
        if let Some(orig) = original_content {
            let _ = clipboard.set_text(orig);
        }
    });
}

fn get_tls_acceptor() -> anyhow::Result<TlsAcceptor> {
    use rcgen::generate_simple_self_signed;
    
    // For V1, we generate a self-signed cert on the fly or load if exists
    // In a real app, you'd save this to the config dir.
    // Here we generate to satisfy "WSS" requirement.
    let subject_alt_names = vec!["localhost".to_string(), "127.0.0.1".to_string()];
    let cert = generate_simple_self_signed(subject_alt_names)?;
    let cert_der = cert.serialize_der()?;
    let priv_key_der = cert.serialize_private_key_der();

    let cert_chain = vec![Certificate(cert_der)];
    let priv_key = PrivateKey(priv_key_der);

    let server_config = ServerConfig::builder()
        .with_safe_defaults()
        .with_no_client_auth()
        .with_single_cert(cert_chain, priv_key)
        .map_err(|e| anyhow::anyhow!("TLS Config error: {}", e))?;

    Ok(TlsAcceptor::from(Arc::new(server_config)))
}
