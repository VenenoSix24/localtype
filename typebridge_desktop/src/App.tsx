import { useState, useEffect, useCallback, createContext, useContext, ReactNode } from "react";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { QRCodeSVG } from "qrcode.react";
import { HashRouter, Routes, Route, Link, useLocation } from "react-router-dom";
import {
  Keyboard, Monitor, Settings, Trash2, Lock, Moon, Sun, MonitorUp,
  Power, ArrowLeft, RefreshCw
} from "lucide-react";

// ====== 类型定义 ======

interface ServerInfo {
  ip: string;
  port: number;
}
interface Device {
  id: string;
  name: string;
}
interface StatusPayload {
  text: string;
}
interface ConnectionPayload {
  count: number;
}
interface PairingPayload {
  code: string;
  device_name: string;
}

// ====== Theme Context ======
type ThemeMode = 'system' | 'light' | 'dark';

interface ThemeContextType {
  theme: ThemeMode;
  setTheme: (t: ThemeMode) => void;
  currentTheme: 'light' | 'dark';
}

const ThemeContext = createContext<ThemeContextType>({
  theme: 'system',
  setTheme: () => { },
  currentTheme: 'dark',
});

function ThemeProvider({ children }: { children: ReactNode }) {
  const [theme, setTheme] = useState<ThemeMode>(() => {
    return (localStorage.getItem('theme') as ThemeMode) || 'system';
  });
  const [currentTheme, setCurrentTheme] = useState<'light' | 'dark'>('dark');

  useEffect(() => {
    localStorage.setItem('theme', theme);
    const root = window.document.documentElement;
    root.classList.remove('light', 'dark');

    const updateTheme = () => {
      let resolvedTheme = theme;
      if (theme === 'system') {
        resolvedTheme = window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
      }
      root.classList.add(resolvedTheme);
      setCurrentTheme(resolvedTheme as 'light' | 'dark');
    };

    updateTheme();
    const mediaQuery = window.matchMedia('(prefers-color-scheme: dark)');
    const handler = () => {
      if (theme === 'system') updateTheme();
    };
    mediaQuery.addEventListener('change', handler);
    return () => mediaQuery.removeEventListener('change', handler);
  }, [theme]);

  // 更新 Tailwind 颜色变量 (通过 class)
  return (
    <ThemeContext.Provider value={{ theme, setTheme, currentTheme }}>
      {children}
    </ThemeContext.Provider>
  );
}

// ====== 组件: Toggle Button ======
function ThemeToggle() {
  const { theme, setTheme } = useContext(ThemeContext);
  return (
    <button
      onClick={() => setTheme(theme === 'dark' ? 'light' : theme === 'light' ? 'system' : 'dark')}
      className="p-2 rounded-lg hover:bg-white/10 text-text-secondary hover:text-text-primary transition-colors cursor-pointer"
      title={`当前模式: ${theme === 'system' ? '跟随系统' : theme === 'dark' ? '深色' : '浅色'}`}
    >
      {theme === 'system' ? <MonitorUp size={18} /> : theme === 'dark' ? <Moon size={18} /> : <Sun size={18} />}
    </button>
  );
}

// ====== 页面: Dashboard ======
function Dashboard({
  serverInfo, status, connectedCount, devices, onRemoveDevice, pairing, setPairing
}: any) {
  const { currentTheme } = useContext(ThemeContext);

  // 生成 QR 码内容
  const qrContent = serverInfo
    ? `typebridge://${serverInfo.ip}:${serverInfo.port}`
    : "";

  return (
    <div className="space-y-4 animate-fade-in pb-4">
      {/* 状态卡片行 */}
      <div className="grid grid-cols-3 gap-3">
        {/* IP 卡片 */}
        <div className="col-span-1 bg-bg-card border border-border-subtle rounded-xl p-3 transition-colors duration-200 hover:bg-bg-card-hover">
          <p className="text-[10px] text-text-muted uppercase tracking-wider mb-1">本机 IP</p>
          <p className="text-sm font-semibold text-text-primary truncate font-[family-name:var(--font-heading)]">
            {serverInfo?.ip || "..."}
          </p>
        </div>
        {/* 端口卡片 */}
        <div className="bg-bg-card border border-border-subtle rounded-xl p-3 transition-colors duration-200 hover:bg-bg-card-hover">
          <p className="text-[10px] text-text-muted uppercase tracking-wider mb-1">端口</p>
          <p className="text-sm font-semibold text-text-primary font-[family-name:var(--font-heading)]">
            {serverInfo?.port || "..."}
          </p>
        </div>
        {/* 连接数卡片 */}
        <div className={`bg-bg-card border rounded-xl p-3 transition-all duration-300 ${connectedCount > 0 ? "border-success/30 bg-success/5" : "border-border-subtle"
          }`}>
          <p className="text-[10px] text-text-muted uppercase tracking-wider mb-1">连接</p>
          <p className={`text-xl font-bold font-[family-name:var(--font-heading)] ${connectedCount > 0 ? "text-success" : "text-text-primary"
            }`}>
            {connectedCount}
          </p>
        </div>
      </div>

      {/* QR 码区域 (自适应背景色) */}
      <div className={`rounded-2xl p-6 flex flex-col items-center gap-4 shadow-lg transition-colors duration-300
        ${currentTheme === 'dark' ? 'bg-bg-card border border-border-subtle' : 'bg-white border border-border-subtle'}`}>
        {qrContent ? (
          <div className="p-2 bg-white/5 rounded-xl">
            <QRCodeSVG
              value={qrContent}
              size={180}
              bgColor={"transparent"}
              fgColor={currentTheme === 'dark' ? "#FFFFFF" : "#000000"}
              level="M"
              includeMargin={false}
            />
          </div>
        ) : (
          <div className="w-[180px] h-[180px] bg-gray-100/10 rounded animate-pulse" />
        )}
        <p className={`text-xs ${currentTheme === 'dark' ? 'text-text-muted' : 'text-text-secondary'}`}>
          使用手机扫描二维码配对
        </p>
      </div>

      {/* 已信任设备 */}
      <div className="space-y-2">
        <h2 className="text-[11px] font-semibold text-text-muted uppercase tracking-wider px-1">
          已信任设备
        </h2>
        {devices.length === 0 ? (
          <div className="bg-bg-card border border-border-subtle rounded-xl py-6 text-center">
            <p className="text-sm text-text-muted">暂无已信任设备</p>
          </div>
        ) : (
          devices.map((device: Device) => (
            <div
              key={device.id}
              className="group flex items-center justify-between bg-bg-card border border-border-subtle rounded-xl px-4 py-3 transition-all duration-200 hover:bg-bg-card-hover hover:border-border-active"
            >
              <div className="flex items-center gap-3 min-w-0">
                <div className="flex-shrink-0 w-9 h-9 rounded-lg bg-accent-blue/10 flex items-center justify-center text-accent-blue">
                  <Monitor size={18} />
                </div>
                <div className="min-w-0">
                  <p className="text-sm font-medium text-text-primary truncate">{device.name}</p>
                  <p className="text-[10px] text-text-muted truncate font-mono">{device.id}</p>
                </div>
              </div>
              <button
                onClick={() => onRemoveDevice(device.id)}
                className="flex-shrink-0 w-8 h-8 rounded-lg flex items-center justify-center text-danger/60 opacity-0 group-hover:opacity-100 hover:bg-danger/10 hover:text-danger transition-all duration-200 cursor-pointer"
                title="移除设备"
              >
                <Trash2 size={18} />
              </button>
            </div>
          ))
        )}
      </div>

      {/* 配对弹窗 */}
      {pairing && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm animate-fade-in">
          <div className="w-80 bg-bg-glass backdrop-blur-2xl border border-border-subtle rounded-2xl p-6 shadow-2xl space-y-5">
            <div className="flex flex-col items-center gap-2 text-accent-blue">
              <div className="p-3 bg-accent-blue/10 rounded-full">
                <Lock size={24} />
              </div>
              <h3 className="text-lg font-semibold font-[family-name:var(--font-heading)]">设备配对请求</h3>
            </div>
            <p className="text-sm text-text-secondary text-center leading-relaxed">
              设备 <span className="text-text-primary font-medium block mt-1 text-base">{pairing.device_name}</span> 请求连接
            </p>
            <div className="bg-bg-deep rounded-xl py-4 text-center border border-border-subtle">
              <p className="text-4xl font-bold text-accent-cyan tracking-[0.2em] font-[family-name:var(--font-heading)] animate-pulse pl-2">
                {pairing.code}
              </p>
            </div>
            <button
              onClick={() => setPairing(null)}
              className="w-full py-3 rounded-xl bg-bg-card hover:bg-bg-card-hover border border-border-subtle text-sm text-text-primary font-medium transition-all cursor-pointer"
            >
              关闭
            </button>
          </div>
        </div>
      )}
    </div>
  );
}

// ====== 页面: Configuration (设置) ======
function Configuration() {
  const [autoStart, setAutoStart] = useState(false);
  const [port] = useState("8765");

  useEffect(() => {
    // 检查是否启用了自启动插件
    import("@tauri-apps/plugin-autostart").then(async (autostart) => {
      try {
        const enabled = await autostart.isEnabled();
        setAutoStart(enabled);
      } catch (e) { console.warn("Autostart check failed", e); }
    });
  }, []);

  const toggleAutoStart = async () => {
    const autostart = await import("@tauri-apps/plugin-autostart");
    try {
      if (autoStart) {
        await autostart.disable();
      } else {
        await autostart.enable();
      }
      const enabled = await autostart.isEnabled();
      setAutoStart(enabled);
    } catch (e) {
      console.error("Autostart toggle failed", e);
    }
  };

  return (
    <div className="space-y-6 animate-fade-in pt-2">
      <div className="space-y-3">
        <h2 className="text-[11px] font-semibold text-text-muted uppercase tracking-wider px-1">通用设置</h2>
        <div className="bg-bg-card border border-border-subtle rounded-xl divide-y divide-border-subtle overflow-hidden">
          {/* 开机自启 */}
          <div className="flex items-center justify-between p-4 hover:bg-bg-card-hover transition-colors">
            <div className="flex items-center gap-3">
              <div className="p-2 bg-accent-blue/10 rounded-lg text-accent-blue">
                <Power size={18} />
              </div>
              <div>
                <p className="text-sm font-medium text-text-primary">开机自启</p>
                <p className="text-xs text-text-muted mt-0.5">登录时自动启动 TypeBridge</p>
              </div>
            </div>
            <button
              onClick={toggleAutoStart}
              className={`w-11 h-6 rounded-full transition-colors relative cursor-pointer ${autoStart ? 'bg-success' : 'bg-gray-600'}`}
            >
              <span className={`absolute top-1 w-4 h-4 bg-white rounded-full transition-transform shadow-sm ${autoStart ? 'left-6' : 'left-1'}`} />
            </button>
          </div>
        </div>
      </div>

      <div className="space-y-3">
        <h2 className="text-[11px] font-semibold text-text-muted uppercase tracking-wider px-1">网络配置</h2>
        <div className="bg-bg-card border border-border-subtle rounded-xl p-4 space-y-4">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-3">
              <div className="p-2 bg-accent-warning/10 rounded-lg text-accent-warning">
                <RefreshCw size={18} />
              </div>
              <div>
                <p className="text-sm font-medium text-text-primary">WSS 端口</p>
                <p className="text-xs text-text-muted mt-0.5">WebSocket 服务监听端口</p>
              </div>
            </div>
            <div className="bg-bg-deep border border-border-subtle rounded px-3 py-1.5 text-sm font-mono text-text-secondary w-20 text-center">
              {port}
            </div>
          </div>
          <div className="pl-[52px]">
            <p className="text-[10px] text-text-muted leading-relaxed bg-bg-deep/50 p-2 rounded border border-border-subtle/50">
              若端口被占用，请修改配置文件或结束占用进程。当前版本暂不支持热切换端口。
            </p>
          </div>
        </div>
      </div>

      <div className="pt-4 text-center">
        <p className="text-[10px] text-text-muted">TypeBridge v1.1.0 (Tauri Build)</p>
      </div>
    </div>
  );
}

// ====== 主应用容器 ======
function AppLayout() {
  const [serverInfo, setServerInfo] = useState<ServerInfo | null>(null);
  const [status, setStatus] = useState("启动中...");
  const [connectedCount, setConnectedCount] = useState(0);
  const [devices, setDevices] = useState<Device[]>([]);
  const [pairing, setPairing] = useState<PairingPayload | null>(null);

  const location = useLocation();

  const fetchServerInfo = useCallback(async () => {
    try {
      const info = await invoke<ServerInfo>("get_server_info");
      setServerInfo(info);
    } catch (e) { console.error(e); }
  }, []);

  const fetchDevices = useCallback(async () => {
    try {
      const devs = await invoke<Device[]>("get_devices");
      setDevices(devs);
    } catch (e) { console.error(e); }
  }, []);

  const handleRemoveDevice = useCallback(async (deviceId: string) => {
    await invoke("remove_device", { deviceId });
    fetchDevices();
  }, [fetchDevices]);

  useEffect(() => {
    fetchServerInfo();
    fetchDevices();
    const unlistenStatus = listen<StatusPayload>("status-changed", (e) => setStatus(e.payload.text));
    const unlistenConnection = listen<ConnectionPayload>("connection-changed", (e) => setConnectedCount(e.payload.count));
    const unlistenPairing = listen<PairingPayload>("pairing-requested", (e) => setPairing(e.payload));
    const unlistenDevices = listen("devices-changed", () => fetchDevices());

    return () => {
      unlistenStatus.then(f => f());
      unlistenConnection.then(f => f());
      unlistenPairing.then(f => f());
      unlistenDevices.then(f => f());
    };
  }, [fetchServerInfo, fetchDevices]);

  return (
    <div className="flex flex-col h-screen bg-bg-deep text-text-primary transition-colors duration-300 select-none">
      {/* 标题栏 */}
      <header className="flex-shrink-0 flex items-center justify-between px-5 py-4 bg-bg-glass backdrop-blur-xl border-b border-border-subtle sticky top-0 z-10">
        <div className="flex items-center gap-3">
          {location.pathname !== "/" ? (
            <Link to="/" className="p-1 -ml-1 rounded-lg hover:bg-white/5 text-text-secondary hover:text-text-primary transition-all group">
              <ArrowLeft size={20} className="group-hover:-translate-x-0.5 transition-transform" />
            </Link>
          ) : (
            <div className="text-accent-blue p-1 bg-accent-blue/10 rounded-lg">
              <Keyboard size={20} />
            </div>
          )}

          <div className="flex flex-col">
            <h1 className="text-base font-bold font-[family-name:var(--font-heading)] tracking-tight leading-none">
              TypeBridge
            </h1>
            <span className="text-[9px] text-text-muted font-medium tracking-wider mt-0.5">CONTROL CENTER</span>
          </div>
        </div>

        <div className="flex items-center gap-1">
          <ThemeToggle />
          {location.pathname === "/" && (
            <Link to="/settings" className="p-2 rounded-lg hover:bg-white/10 text-text-secondary hover:text-text-primary transition-colors" title="设置">
              <Settings size={18} />
            </Link>
          )}
        </div>
      </header>

      {/* 内容区 */}
      <main className="flex-1 overflow-y-auto p-5 scrollbar-thin">
        <Routes>
          <Route path="/" element={
            <Dashboard
              serverInfo={serverInfo}
              status={status}
              connectedCount={connectedCount}
              devices={devices}
              onRemoveDevice={handleRemoveDevice}
              pairing={pairing}
              setPairing={setPairing}
            />
          } />
          <Route path="/settings" element={<Configuration />} />
        </Routes>
      </main>

      {/* 底部状态栏 */}
      <footer className="flex-shrink-0 px-5 py-2.5 border-t border-border-subtle bg-bg-card flex items-center justify-between text-[10px] text-text-muted">
        <div className="flex items-center gap-1.5">
          <span className={`w-1.5 h-1.5 rounded-full ${connectedCount > 0 ? 'bg-success animate-pulse' : 'bg-gray-500'}`} />
          <span>{status}</span>
        </div>
      </footer>
    </div>
  );
}

function App() {
  return (
    <HashRouter>
      <ThemeProvider>
        <AppLayout />
      </ThemeProvider>
    </HashRouter>
  );
}

export default App;
