// LocalType 控制中心 - Tauri v2 后端
// NOTE: 所有核心网络逻辑（WSS、UDP、TLS）在 Tauri setup 钩子中启动，
// 通过 AppHandle.emit() 向前端推送状态更新。

// 防止在 Windows 发布模式下弹出控制台窗口
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use std::{
    net::{IpAddr, SocketAddr},
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc,
    },
};

use futures_util::{SinkExt, StreamExt};
use log::{debug, error, info};
use serde::{Deserialize, Serialize};
use tauri::{
    menu::{Menu, MenuItem},
    tray::{MouseButton, TrayIconBuilder, TrayIconEvent},
    AppHandle, Emitter, Manager, WindowEvent,
};
use tauri_plugin_autostart::MacosLauncher;
use tokio::net::{TcpListener, UdpSocket};
use tokio_tungstenite::tungstenite::Message;

use enigo::{Direction, Enigo, Key, Keyboard, Settings};
use tokio_rustls::{
    rustls::{Certificate, PrivateKey, ServerConfig},
    TlsAcceptor,
};

mod server_state;
use server_state::ServerState;

// 核心配置
const WSS_PORT: u16 = 8765;
const UDP_PORT: u16 = 45678;

// ====== 前端事件载荷 ======

#[derive(Clone, Serialize)]
struct StatusPayload {
    text: String,
}

#[derive(Clone, Serialize)]
struct ConnectionPayload {
    count: i32,
}

#[derive(Clone, Serialize)]
struct PairingPayload {
    code: String,
    device_name: String,
}

#[derive(Clone, Serialize)]
struct DevicePayload {
    id: String,
    name: String,
    alias: Option<String>,
    os: Option<String>,
    current_ip: Option<String>,
}

#[derive(Clone, Serialize)]
struct NetworkInterfacePayload {
    name: String,
    ip: String,
}

fn list_network_interfaces() -> Vec<(String, IpAddr)> {
    let mut interfaces: Vec<(String, IpAddr)> = local_ip_address::list_afinet_netifas()
        .unwrap_or_default()
        .into_iter()
        .filter(|(_, ip)| matches!(ip, IpAddr::V4(v4) if !v4.is_loopback()))
        .collect();
    interfaces.sort_by(|a, b| a.0.cmp(&b.0));
    interfaces
}

fn resolve_discovery_ip(config: &server_state::AppConfig) -> IpAddr {
    if let Some(interface_name) = config.discovery_interface.as_deref() {
        if let Some((_, ip)) = list_network_interfaces()
            .into_iter()
            .find(|(name, _)| name == interface_name)
        {
            return ip;
        }
    }

    local_ip_address::local_ip().unwrap_or("127.0.0.1".parse().unwrap())
}

// ====== Tauri Commands ======

/// 获取服务器信息（IP + 端口 + 设备名）
#[tauri::command]
fn get_server_info(state: tauri::State<'_, ServerState>) -> serde_json::Value {
    let config = state.config.lock().unwrap();
    let ip = resolve_discovery_ip(&config).to_string();
    serde_json::json!({
        "ip": ip,
        "port": WSS_PORT,
        "device_name": config.device_name,
        "server_id": config.server_id,
        "discovery_interface": config.discovery_interface
    })
}

/// 获取应用配置
#[tauri::command]
fn get_app_config(state: tauri::State<'_, ServerState>) -> server_state::AppConfig {
    state.config.lock().unwrap().clone()
}

/// 更新设备名称
#[tauri::command]
fn update_device_name(name: String, state: tauri::State<'_, ServerState>) -> bool {
    let mut config = state.config.lock().unwrap();
    config.device_name = name;
    drop(config);
    let _ = state.save_config();
    true
}

/// 获取可用网卡列表
#[tauri::command]
fn get_network_interfaces(state: tauri::State<'_, ServerState>) -> serde_json::Value {
    let interfaces: Vec<NetworkInterfacePayload> = list_network_interfaces()
        .into_iter()
        .map(|(name, ip)| NetworkInterfacePayload {
            name,
            ip: ip.to_string(),
        })
        .collect();

    let selected = state.config.lock().unwrap().discovery_interface.clone();
    serde_json::json!({
        "interfaces": interfaces,
        "selected": selected
    })
}

/// 更新发现响应所使用的网卡
#[tauri::command]
fn update_discovery_interface(interface_name: Option<String>, state: tauri::State<'_, ServerState>) -> bool {
    let normalized = interface_name.and_then(|name| {
        let trimmed = name.trim();
        if trimmed.is_empty() {
            None
        } else {
            Some(trimmed.to_string())
        }
    });

    let mut config = state.config.lock().unwrap();
    config.discovery_interface = normalized;
    drop(config);
    let _ = state.save_config();
    true
}

/// 获取已信任设备列表
#[tauri::command]
fn get_devices(state: tauri::State<'_, ServerState>) -> Vec<DevicePayload> {
    let active = state.active_sessions.lock().unwrap();
    state
        .get_device_list()
        .into_iter()
        .map(|c| DevicePayload {
            current_ip: active.get(&c.id).map(|(ip, _)| ip.clone()),
            id: c.id,
            name: c.name,
            alias: c.alias,
            os: c.os,
        })
        .collect()
}

/// 更新设备备注名
#[tauri::command]
fn update_device_alias(device_id: String, alias: String, state: tauri::State<'_, ServerState>) -> bool {
    let mut clients = state.trusted_clients.lock().unwrap();
    if let Some(client) = clients.get_mut(&device_id) {
        client.alias = if alias.trim().is_empty() { None } else { Some(alias) };
        drop(clients);
        let _ = state.save_trusted_clients();
        return true;
    }
    false
}

/// 移除已信任设备
#[tauri::command]
fn remove_device(device_id: String, state: tauri::State<'_, ServerState>) -> bool {
    info!("移除设备: {}", device_id);
    state.remove_device(&device_id);
    true
}

/// 切换注入暂停状态
#[tauri::command]
fn toggle_pause(paused: tauri::State<'_, Arc<AtomicBool>>) -> bool {
    let current = paused.load(Ordering::Relaxed);
    let new_state = !current;
    paused.store(new_state, Ordering::Relaxed);
    info!("注入 {}", if new_state { "已暂停" } else { "已恢复" });
    new_state
}

/// 获取当前版本号
#[tauri::command]
fn get_current_version(app: tauri::AppHandle) -> String {
    app.config().version.clone().unwrap_or_else(|| "unknown".to_string())
}

/// 比较 semver 版本号，返回 a > b 时为正数
fn compare_versions(a: &str, b: &str) -> i32 {
    // 去除 pre-release 后缀（如 "1.2.3-beta" → "1.2.3"）
    let clean = |s: &str| -> String {
        s.split('-').next().unwrap_or(s).to_string()
    };
    let parse = |s: &str| -> Vec<i32> {
        clean(s).split('.').map(|p| p.parse().unwrap_or(0)).collect()
    };
    let a_parts = parse(a);
    let b_parts = parse(b);
    for i in 0..3 {
        let av = a_parts.get(i).copied().unwrap_or(0);
        let bv = b_parts.get(i).copied().unwrap_or(0);
        if av != bv { return av - bv; }
    }
    0
}

/// 检查更新（通过 GitHub Releases API）
#[tauri::command]
async fn check_for_updates(app: tauri::AppHandle, state: tauri::State<'_, ServerState>) -> Result<serde_json::Value, String> {
    let current_version = app.config().version.clone().unwrap_or_else(|| "0.0.0".to_string());

    let client = reqwest::Client::new();
    let resp = client
        .get("https://api.github.com/repos/VenenoSix24/localtype/releases/latest")
        .header("Accept", "application/vnd.github.v3+json")
        .header("User-Agent", "LocalType")
        .send()
        .await
        .map_err(|e| e.to_string())?;

    if !resp.status().is_success() {
        return Err(format!("GitHub API 返回状态码: {}", resp.status()));
    }

    let data: serde_json::Value = resp.json().await.map_err(|e| e.to_string())?;
    let tag_name = data["tag_name"].as_str().unwrap_or("");
    let latest_version = tag_name.trim_start_matches('v');
    let release_notes = data["body"].as_str().unwrap_or("").to_string();

    // 查找当前平台对应的下载链接
    let download_url = find_download_url(&data["assets"]);

    if compare_versions(latest_version, &current_version) <= 0 {
        return Ok(serde_json::json!({
            "available": false,
            "current_version": current_version,
        }));
    }

    let skipped = {
        let config = state.config.lock().unwrap();
        config.skipped_version.as_deref() == Some(latest_version)
    };

    Ok(serde_json::json!({
        "available": true,
        "current_version": current_version,
        "latest_version": latest_version,
        "release_notes": release_notes,
        "download_url": download_url,
        "skipped": skipped,
    }))
}

/// 打开下载页面
#[tauri::command]
async fn open_download_page(url: String, app: tauri::AppHandle) -> Result<(), String> {
    use tauri_plugin_opener::OpenerExt;
    app.opener().open_url(url, None::<&str>).map_err(|e| e.to_string())
}

/// 根据当前平台从 assets 中找到对应的下载链接
fn find_download_url(assets: &serde_json::Value) -> String {
    let assets = match assets.as_array() {
        Some(a) => a,
        None => return String::new(),
    };

    // 根据当前平台匹配文件名关键字
    #[cfg(target_os = "macos")]
    let keywords: Vec<&str> = if cfg!(target_arch = "aarch64") {
        vec!["darwin-aarch64", "macos-aarch64"]
    } else {
        vec!["darwin-x64", "macos-x86_64"]
    };
    #[cfg(target_os = "windows")]
    let keywords: Vec<&str> = vec!["windows"];
    #[cfg(target_os = "linux")]
    let keywords: Vec<&str> = vec!["linux"];

    for asset in assets {
        let name = asset["name"].as_str().unwrap_or("");
        let url = asset["browser_download_url"].as_str().unwrap_or("");
        let matched = keywords.iter().any(|kw| name.contains(kw));
        if matched && (name.ends_with(".dmg") || name.ends_with(".msi") || name.ends_with(".exe") || name.ends_with(".AppImage") || name.ends_with(".deb")) {
            return url.to_string();
        }
    }

    String::new()
}

/// 跳过某个版本
#[tauri::command]
fn skip_version(version: String, state: tauri::State<'_, ServerState>) -> bool {
    let mut config = state.config.lock().unwrap();
    config.skipped_version = Some(version);
    drop(config);
    let _ = state.save_config();
    true
}

// ====== 应用入口 ======

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    env_logger::init_from_env(env_logger::Env::default().default_filter_or("info"));

    let server_state = ServerState::new();
    let is_paused = Arc::new(AtomicBool::new(false));

    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_autostart::init(
            MacosLauncher::LaunchAgent,
            Some(vec!["--minimized"]), // 可选：启动时最小化参数
        ))
        .manage(server_state.clone())
        .manage(is_paused.clone())
        .invoke_handler(tauri::generate_handler![
            get_server_info,
            get_devices,
            remove_device,
            toggle_pause,
            get_app_config,
            update_device_name,
            update_device_alias,
            get_network_interfaces,
            update_discovery_interface,
            get_current_version,
            check_for_updates,
            open_download_page,
            skip_version,
        ])
        .setup(move |app| {
            let app_handle = app.handle().clone();
            let state = server_state.clone();
            let paused = is_paused.clone();

            // --- 系统托盘 ---
            let quit_i = MenuItem::with_id(app, "quit", "退出", true, None::<&str>)?;
            let show_i = MenuItem::with_id(app, "show", "显示主界面", true, None::<&str>)?;
            let menu = Menu::with_items(app, &[&show_i, &quit_i])?;

            // 加载自定义托盘图标
            #[cfg(target_os = "macos")]
            let tray_icon = tauri::image::Image::from_bytes(include_bytes!("../icons/tray.png"))?; // macOS 使用白色图标

            #[cfg(not(target_os = "macos"))]
            let tray_icon = tauri::image::Image::from_bytes(include_bytes!("../icons/tray_all.png"))?; // Windows/Linux 使用彩色图标

            let _tray = TrayIconBuilder::new()
                .icon(tray_icon)
                .menu(&menu)
                .show_menu_on_left_click(false)
                .on_menu_event(|app, event| match event.id.as_ref() {
                    "quit" => {
                        app.exit(0);
                    }
                    "show" => {
                        if let Some(window) = app.get_webview_window("main") {
                            let _ = window.show();
                            let _ = window.set_focus();
                        }
                    }
                    _ => {}
                })
                .on_tray_icon_event(|tray, event| match event {
                    TrayIconEvent::Click {
                        button: MouseButton::Left,
                        ..
                    } => {
                        let app = tray.app_handle();
                        if let Some(window) = app.get_webview_window("main") {
                            let _ = window.show();
                            let _ = window.set_focus();
                        }
                    }
                    _ => {}
                })
                .build(app)?;

            // --- 窗口事件拦截 (关闭 -> 隐藏) ---
            if let Some(window) = app.get_webview_window("main") {
                let window_clone = window.clone();
                window.on_window_event(move |event| match event {
                    WindowEvent::CloseRequested { api, .. } => {
                        api.prevent_close();
                        let _ = window_clone.hide();
                    }
                    _ => {}
                });
            }

            // --- 启动网络服务 ---
            std::thread::spawn(move || {
                let rt = tokio::runtime::Runtime::new().unwrap();
                rt.block_on(async {
                    // TLS 配置
                    let tls_acceptor = match get_tls_acceptor() {
                        Ok(a) => a,
                        Err(e) => {
                            error!("TLS 配置错误: {}", e);
                            return;
                        }
                    };

                    // 启动 UDP 广播发现服务
                    let discovery_state = state.clone();
                    tokio::spawn(async move {
                        if let Err(e) = run_discovery_service(discovery_state).await {
                            error!("UDP 发现服务错误: {}", e);
                        }
                    });

                    // 启动 WSS 服务器
                    let addr = format!("0.0.0.0:{}", WSS_PORT);
                    let listener = TcpListener::bind(&addr).await.unwrap();
                    info!("WSS 监听: {}", addr);

                    // 通知前端服务器已就绪
                    let _ = app_handle.emit("status-changed", StatusPayload {
                        text: "就绪".to_string(),
                    });

                    while let Ok((stream, addr)) = listener.accept().await {
                        let state = state.clone();
                        let app_handle = app_handle.clone();
                        let paused = paused.clone();
                        let acceptor = tls_acceptor.clone();

                        tokio::spawn(async move {
                            match acceptor.accept(stream).await {
                                Ok(tls_stream) => {
                                    accept_connection(
                                        tls_stream,
                                        addr,
                                        state,
                                        app_handle,
                                        paused,
                                    )
                                    .await;
                                }
                                Err(e) => error!("TLS 握手错误 {}: {}", addr, e),
                            }
                        });
                    }
                });
            });

            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("LocalType 启动失败");
}

// ====== 网络服务 ======

async fn run_discovery_service(state: ServerState) -> std::io::Result<()> {
    let socket = UdpSocket::bind(format!("0.0.0.0:{}", UDP_PORT)).await?;
    socket.set_broadcast(true)?;
    info!("UDP 发现服务监听: {}", UDP_PORT);

    let mut buf = [0u8; 1024];

    loop {
        let (len, addr) = socket.recv_from(&mut buf).await?;
        let msg = String::from_utf8_lossy(&buf[..len]);
        debug!("收到 UDP 广播 from {}: {}", addr, msg);

        if msg.trim() == "localtype_discovery" {
            let (local_ip, device_name, server_id, interface_name) = {
                let config = state.config.lock().unwrap();
                (
                    resolve_discovery_ip(&config),
                    config.device_name.clone(),
                    config.server_id.clone(),
                    config.discovery_interface.clone(),
                )
            };
            let os_name = std::env::consts::OS;
            
            // Format: localtype_server:[IP]|[NAME]|[OS]|[ID]
            let response = format!("localtype_server:{}|{}|{}|{}", local_ip, device_name, os_name, server_id);
            socket.send_to(response.as_bytes(), addr).await?;
            info!(
                "已响应发现请求 from {}: {} (IP: {}, 网卡: {}, OS: {}, ID: {})",
                addr,
                device_name,
                local_ip,
                interface_name.unwrap_or_else(|| "auto".to_string()),
                os_name,
                server_id
            );
        }
    }
}

// ====== WebSocket 连接处理 ======

async fn accept_connection<S>(
    stream: S,
    addr: SocketAddr,
    state: ServerState,
    app_handle: AppHandle,
    is_paused: Arc<AtomicBool>,
) where
    S: tokio::io::AsyncRead + tokio::io::AsyncWrite + Unpin,
{
    info!("新连接: {}", addr);
    let _ = app_handle.emit(
        "status-changed",
        StatusPayload {
            text: format!("连接中: {}", addr.ip()),
        },
    );

    let ws_stream = match tokio_tungstenite::accept_async(stream).await {
        Ok(ws) => ws,
        Err(e) => {
            error!("WebSocket 握手失败: {}", e);
            let _ = app_handle.emit(
                "status-changed",
                StatusPayload {
                    text: "握手失败".to_string(),
                },
            );
            return;
        }
    };

    info!("WebSocket 已建立: {}", addr);
    let _ = app_handle.emit(
        "status-changed",
        StatusPayload {
            text: format!("已连接: {}", addr.ip()),
        },
    );
    let (mut ws_write, mut ws_read) = ws_stream.split();
    let mut authenticated_device_name: Option<String> = None;
    let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel::<String>();
    let session_id = state.next_session_id();
    

    loop {
        tokio::select! {
            // 监听 WebSocket 消息
            msg = ws_read.next() => {
                let msg = match msg {
                    Some(Ok(m)) => m,
                    _ => break, // 连接关闭或错误
                };

                match msg {
                    Message::Text(text) => {
                        debug!("收到: {}", text);

                        match serde_json::from_str::<ClientMessage>(&text) {
                            Ok(client_msg) => match client_msg {
                                ClientMessage::Ping => {
                                    let pong = serde_json::to_string(&ServerResponse::Pong).unwrap();
                                    if let Err(e) = ws_write.send(Message::Text(pong)).await {
                                        error!("发送 Pong 失败: {}", e);
                                        break;
                                    }
                                }
                                ClientMessage::Pong => {}
                                ClientMessage::RequestPairing {
                                    device_name,
                                    device_id,
                                    os: _,
                                } => {
                                    info!("配对请求: {} ({})", device_name, device_id);

                                    let code = state.generate_pairing_code(&device_id);
                                    let _ = app_handle.emit(
                                        "status-changed",
                                        StatusPayload {
                                            text: format!("配对中: {}", device_name),
                                        },
                                    );

                                    let _ = app_handle.emit(
                                        "pairing-requested",
                                        PairingPayload {
                                            code: code.clone(),
                                            device_name: device_name.clone(),
                                        },
                                    );

                                    let response = serde_json::to_string(
                                        &ServerResponse::PairingCodeRequired,
                                    ).unwrap();
                                    let _ = ws_write.send(Message::Text(response)).await;
                                }
                                ClientMessage::VerifyPairing {
                                    device_id,
                                    code,
                                    device_name,
                                    os,
                                } => {
                                    if let Some(token) = state.verify_pairing_code(&device_id, &code, &device_name, os.clone()) {
                                        info!("配对成功: {}", device_name);
                                        authenticated_device_name = Some(device_id.clone());
                                        
                                        if let Some(os_val) = os {
                                            state.update_client_os(&device_id, &os_val);
                                        }

                                        state.kick_device(&device_id);
                                        state.active_connections.lock().unwrap().insert(device_id.clone(), tx.clone());

                                        let active_count = {
                                            let mut active = state.active_sessions.lock().unwrap();
                                            active.insert(device_id.clone(), (addr.ip().to_string(), session_id));
                                            active.len() as i32
                                        };

                                        let display_name = state.get_client_display_name(&device_id);
                                        if let Some(window) = app_handle.get_webview_window("main") {
                                            let _ = window.set_title(&format!("LocalType - {}", display_name));
                                        }

                                        let _ = app_handle.emit("status-changed", StatusPayload {
                                            text: format!("已连接: {}", display_name),
                                        });
                                        let _ = app_handle.emit("connection-changed", ConnectionPayload { count: active_count });
                                        let _ = app_handle.emit("devices-changed", ());
                                        let _ = app_handle.emit("pairing-success", ());

                                        let response = serde_json::to_string(&ServerResponse::PairingSuccess { 
                                            token,
                                            os: std::env::consts::OS.to_string(),
                                            name: state.config.lock().unwrap().device_name.clone()
                                        }).unwrap();
                                        let _ = ws_write.send(Message::Text(response)).await;
                                    } else {
                                        info!("配对失败: {}", device_name);
                                        let response = serde_json::to_string(&ServerResponse::Error {
                                            message: "验证码无效".into(),
                                        }).unwrap();
                                        let _ = ws_write.send(Message::Text(response)).await;
                                    }
                                }
                                ClientMessage::Auth { device_id, token, os } => {
                                    if state.is_trusted(&device_id, &token) {
                                        info!("认证成功: {}", device_id);
                                        authenticated_device_name = Some(device_id.clone());

                                        if let Some(os_val) = os {
                                            state.update_client_os(&device_id, &os_val);
                                        }

                                        state.kick_device(&device_id);
                                        state.active_connections.lock().unwrap().insert(device_id.clone(), tx.clone());

                                        let active_count = {
                                            let mut active = state.active_sessions.lock().unwrap();
                                            active.insert(device_id.clone(), (addr.ip().to_string(), session_id));
                                            active.len() as i32
                                        };
                                        let display_name = state.get_client_display_name(&device_id);
                                        if let Some(window) = app_handle.get_webview_window("main") {
                                            let _ = window.set_title(&format!("LocalType - {}", display_name));
                                        }

                                        let _ = app_handle.emit("status-changed", StatusPayload {
                                            text: format!("已连接: {}", display_name),
                                        });
                                        let _ = app_handle.emit("connection-changed", ConnectionPayload { count: active_count });
                                        let _ = app_handle.emit("devices-changed", ());

                                        let response = serde_json::to_string(&ServerResponse::AuthSuccess {
                                            os: std::env::consts::OS.to_string(),
                                            name: state.config.lock().unwrap().device_name.clone()
                                        }).unwrap();
                                        let _ = ws_write.send(Message::Text(response)).await;
                                    } else {
                                        info!("认证失败: {}", device_id);
                                        let response = serde_json::to_string(&ServerResponse::AuthFailed).unwrap();
                                        let _ = ws_write.send(Message::Text(response)).await;
                                    }
                                }
                                ClientMessage::Unpair => {
                                    if let Some(device_id) = &authenticated_device_name {
                                        info!("客户端请求解除配对: {}", device_id);
                                        state.remove_device(device_id);
                                        let _ = app_handle.emit("devices-changed", ());
                                        let response = serde_json::to_string(&ServerResponse::Unpaired).unwrap();
                                        let _ = ws_write.send(Message::Text(response)).await;
                                        break;
                                    }
                                }
                                ClientMessage::Send { content, method, msg_id } => {
                                    if authenticated_device_name.is_some() {
                                        if is_paused.load(Ordering::Relaxed) { continue; }
                                        let injection_method = method.unwrap_or_else(|| "unicode".to_string());
                                        
                                        // 执行注入
                                        perform_injection(&content, &injection_method).await;

                                        // 如果客户端提供了消息 ID，回传 ACK
                                        if let Some(id) = msg_id {
                                            let ack = serde_json::to_string(&ServerResponse::Ack { msg_id: id }).unwrap();
                                            let _ = ws_write.send(Message::Text(ack)).await;
                                        }
                                    } else {
                                        let response = serde_json::to_string(&ServerResponse::Error {
                                            message: "尚未认证".into(),
                                        }).unwrap();
                                        let _ = ws_write.send(Message::Text(response)).await;
                                    }
                                }
                                ClientMessage::Reset => {
                                    info!("状态重置");
                                }
                            },
                            Err(e) => error!("JSON 解析错误: {}", e),
                        }
                    }
                    Message::Close(_) => break,
                    _ => {}
                }
            },
            
            // 监听内部控制指令 (由后端命令触发，如删除设备)
            ctrl_msg = rx.recv() => {
                if let Some(ctrl_text) = ctrl_msg {
                    if ctrl_text == "unpaired" {
                        info!("收到内部指令: 解除配对，关闭连接");
                        let response = serde_json::to_string(&ServerResponse::Unpaired).unwrap();
                        let _ = ws_write.send(Message::Text(response)).await;
                        break;
                    } else if ctrl_text == "kick" {
                        info!("收到内部指令: 踢出旧会话，保留配对信息");
                        break; // 直接断开连接，不发送 Unpaired 消息
                    }
                } else {
                    break;
                }
            }
        }
    }

    let active_count = {
        let mut active = state.active_sessions.lock().unwrap();
        if let Some(did) = &authenticated_device_name {
            if let Some((_, sid)) = active.get(did) {
                if *sid == session_id {
                    active.remove(did);
                    state.active_connections.lock().unwrap().remove(did);
                    info!("清理会话: {} (ID: {})", did, session_id);
                }
            }
        }
        active.len() as i32
    };

    if active_count == 0 {
        if let Some(window) = app_handle.get_webview_window("main") {
            let _ = window.set_title("LocalType");
        }
    }

    let _ = app_handle.emit(
        "status-changed",
        StatusPayload {
            text: "就绪".to_string(),
        },
    );
    let _ = app_handle.emit("connection-changed", ConnectionPayload { count: active_count });
    let _ = app_handle.emit("devices-changed", ());
}

// ====== 消息协议 ======

#[derive(Serialize, Deserialize, Debug)]
#[serde(tag = "type", rename_all = "lowercase")]
enum ClientMessage {
    Ping,
    Pong,
    RequestPairing {
        device_name: String,
        device_id: String,
        os: Option<String>,
    },
    VerifyPairing {
        device_id: String,
        code: String,
        device_name: String,
        os: Option<String>,
    },
    Auth {
        device_id: String,
        token: String,
        os: Option<String>,
    },
    Send {
        content: String,
        method: Option<String>,
        msg_id: Option<String>,
    },
    Reset,
    Unpair,
}

#[derive(Serialize, Deserialize, Debug)]
#[serde(tag = "type", rename_all = "lowercase")]
enum ServerResponse {
    Pong,
    PairingCodeRequired,
    PairingSuccess { token: String, os: String, name: String },
    AuthSuccess { os: String, name: String },
    AuthFailed,
    Unpaired,
    Ack { msg_id: String },
    Error { message: String },
}

// ====== 文本注入 ======

async fn perform_injection(text: &str, method: &str) {
    if method == "clipboard" {
        inject_via_clipboard(text).await;
    } else {
        inject_text(text).await;
    }
}

async fn inject_text(text: &str) {
    info!("注入文本 ({} 字符)", text.len());
    let text = text.to_string();
    std::thread::spawn(move || {
        let mut enigo = match Enigo::new(&Settings::default()) {
            Ok(e) => e,
            Err(e) => {
                error!("Enigo 初始化失败: {:?}", e);
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
            if i < lines.len() - 1 {
                let _ = enigo.key(Key::Shift, Direction::Press);
                let _ = enigo.key(Key::Return, Direction::Click);
                let _ = enigo.key(Key::Shift, Direction::Release);
                std::thread::sleep(std::time::Duration::from_millis(10));
            }
        }
    });
}

async fn inject_via_clipboard(text: &str) {
    info!("剪贴板注入 ({} 字符)", text.len());
    let text = text.to_string();
    std::thread::spawn(move || {
        let mut clipboard = arboard::Clipboard::new().expect("Failed to open clipboard");
        let original_content = clipboard.get_text().ok();

        let _ = clipboard.set_text(text);

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

        std::thread::sleep(std::time::Duration::from_millis(100));
        if let Some(orig) = original_content {
            let _ = clipboard.set_text(orig);
        }
    });
}

// ====== TLS ======

fn get_tls_acceptor() -> anyhow::Result<TlsAcceptor> {
    use rcgen::generate_simple_self_signed;

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
        .map_err(|e| anyhow::anyhow!("TLS 配置错误: {}", e))?;

    Ok(TlsAcceptor::from(Arc::new(server_config)))
}
