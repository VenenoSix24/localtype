import { useState, useEffect, useCallback, createContext, useContext, ReactNode } from "react";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { HashRouter, Routes, Route, Link, useLocation } from "react-router-dom";
import {
  Settings, Moon, Monitor,
  Wifi, ShieldCheck, Activity, Smartphone, Power, Trash2
} from "lucide-react";

// ====== Types ======
// Note: Using 'any' for quick implementation based on user feedback refinements

// ====== Theme Context ======
type ThemeMode = 'system' | 'light' | 'dark';
interface ThemeContextType {
  theme: ThemeMode;
  setTheme: (t: ThemeMode) => void;
  currentTheme: 'light' | 'dark';
}
const ThemeContext = createContext<ThemeContextType>({
  theme: 'system', setTheme: () => { }, currentTheme: 'dark',
});

function ThemeProvider({ children }: { children: ReactNode }) {
  const [theme, setTheme] = useState<ThemeMode>(() => (localStorage.getItem('theme') as ThemeMode) || 'system');
  const [currentTheme, setCurrentTheme] = useState<'light' | 'dark'>('dark');

  useEffect(() => {
    localStorage.setItem('theme', theme);
    const root = window.document.documentElement;
    root.classList.remove('light', 'dark');
    const updateTheme = () => {
      let resolved = theme;
      if (theme === 'system') resolved = window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
      root.classList.add(resolved);
      setCurrentTheme(resolved as 'light' | 'dark');
    };
    updateTheme();
    const mq = window.matchMedia('(prefers-color-scheme: dark)');
    mq.addEventListener('change', updateTheme);
    return () => mq.removeEventListener('change', updateTheme);
  }, [theme]);

  return <ThemeContext.Provider value={{ theme, setTheme, currentTheme }}>{children}</ThemeContext.Provider>;
}

// ====== Components ======

function SidebarItem({ icon: Icon, active, onClick, to }: any) {
  const content = (
    <div className={`p-3 rounded-2xl transition-all duration-300 cursor-pointer mb-4 group relative flex items-center justify-center
      ${active ? 'bg-accent-blue text-white shadow-lg shadow-accent-blue/30' : 'text-text-secondary hover:bg-white/10 hover:text-text-primary'}`}
    >
      <Icon size={22} strokeWidth={active ? 2.5 : 2} />
      {active && <div className="absolute inset-0 bg-white/20 rounded-2xl animate-pulse" />}
    </div>
  );

  return to ? <Link to={to}>{content}</Link> : <div onClick={onClick}>{content}</div>;
}

function Dashboard({ serverInfo, connectedCount, pairing, setPairing, pairingSuccess }: any) {
  return (
    <div className="flex flex-col h-full w-full max-w-4xl mx-auto relative z-10 px-8 py-6">
      {/* Page Header */}
      <div className="flex items-center justify-between mb-10">
        <div>
          <h1 className="text-4xl font-black font-heading tracking-tighter text-text-primary">运行状态</h1>
          <p className="text-text-secondary text-base">TypeBridge 服务正在后台运行</p>
        </div>
        <div className={`flex items-center gap-3 px-5 py-2.5 rounded-2xl glass-card border-none bg-white/5`}>
          <div className={`w-2.5 h-2.5 rounded-full ${connectedCount > 0 ? 'bg-accent-green animate-pulse shadow-[0_0_12px_rgba(34,197,94,0.6)]' : 'bg-text-muted'}`} />
          <span className="text-sm font-bold tracking-tight">
            {connectedCount > 0 ? "已连接通信中" : "空闲中"}
          </span>
        </div>
      </div>

      {/* Hero Stats Grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6 mb-10">
        <div className="glass-card p-6 rounded-4xl border-white/5 flex flex-col justify-between min-h-40">
          <div className="space-y-3">
            <div className="p-3 bg-accent-blue/10 rounded-2xl w-fit text-accent-blue"><Wifi size={24} /></div>
            <p className="text-sm font-bold text-text-secondary opacity-60 uppercase tracking-widest">内网地址</p>
          </div>
          <p className="text-xl font-mono font-black text-text-primary break-all leading-tight">{serverInfo?.ip || "获取中..."}</p>
        </div>
        <div className="glass-card p-6 rounded-4xl border-white/5 flex flex-col justify-between min-h-40">
          <div className="space-y-3">
            <div className="p-3 bg-accent-green/10 rounded-2xl w-fit text-accent-green"><Activity size={24} /></div>
            <p className="text-sm font-bold text-text-secondary opacity-60 uppercase tracking-widest">通信端口</p>
          </div>
          <p className="text-2xl font-mono font-black text-text-primary">{serverInfo?.port || "..."}</p>
        </div>
        <div className="glass-card p-6 rounded-4xl border-white/5 flex flex-col justify-between min-h-40">
          <div className="space-y-3">
            <div className="p-3 bg-accent-purple/10 rounded-2xl w-fit text-accent-purple"><Monitor size={24} /></div>
            <p className="text-sm font-bold text-text-secondary opacity-60 uppercase tracking-widest">本机名称</p>
          </div>
          <p className="text-xl font-black text-text-primary truncate">{serverInfo?.device_name || "..."}</p>
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <div className="glass-card p-8 rounded-4xl border-white/5 space-y-4">
          <div className="flex items-center gap-4">
            <div className="p-3 bg-white/5 rounded-2xl text-text-primary"><Smartphone size={24} /></div>
            <div>
              <p className="text-xl font-bold">连接统计</p>
              <p className="text-sm text-text-secondary">当前活动会话</p>
            </div>
          </div>
          <div className="flex items-baseline gap-2 pt-2">
            <span className="text-5xl font-black text-accent-blue">{connectedCount}</span>
            <span className="text-text-muted font-bold italic">Active Devices</span>
          </div>
        </div>
        <div className="glass-card p-8 rounded-4xl border-white/5 space-y-4 flex flex-col justify-center">
          <div className="flex items-center gap-4 mb-2">
            <div className="w-3 h-3 bg-accent-green rounded-full" />
            <p className="text-lg font-bold">输入服务已就绪</p>
          </div>
          <p className="text-sm text-text-secondary leading-relaxed">
            请在手机端 App 扫描您的局域网，选择并连接到本设备。连接后，手机端的输入内容将实时同步到电脑光标处。
          </p>
        </div>
      </div>

      {/* Floating Pairing Overlay */}
      {pairing && (
        <div className="absolute inset-0 z-50 flex items-center justify-center p-8 bg-bg-deep/80 backdrop-blur-xl rounded-4xl animate-fade-in">
          <div className="glass-card w-full max-w-sm p-10 rounded-4xl text-center space-y-8 animate-scale-in border-accent-blue/40 border-2 shadow-[0_0_50px_rgba(59,130,246,0.3)]">
            <div className="space-y-2">
              <h3 className="text-2xl font-black text-text-primary">新设备配对</h3>
              <p className="text-sm text-text-secondary">请在手机端输入下方验证码</p>
            </div>
            <div className="text-5xl font-black font-heading text-accent-blue tracking-widest py-6 bg-white/5 rounded-3xl">
              {pairing.code}
            </div>
            <div className="space-y-1">
              <p className="text-xs text-text-muted uppercase tracking-widest">申请设备</p>
              <p className="text-lg font-bold text-text-primary">{pairing.device_name}</p>
            </div>
            <button
              onClick={() => setPairing(null)}
              className="w-full py-4 rounded-2xl bg-white/5 hover:bg-white/10 transition text-sm font-bold tracking-widest uppercase cursor-pointer"
            >
              取消配对
            </button>
          </div>
        </div>
      )}

      {/* Simple Connection Success Toast/Overlay */}
      {pairingSuccess && (
        <div className="absolute top-10 right-10 z-50 animate-scale-in">
          <div className="glass-card px-8 py-4 rounded-2xl bg-accent-green/20 border-accent-green/30 border flex items-center gap-4 text-accent-green">
            <ShieldCheck size={24} />
            <span className="font-bold">配对成功，通信已加密</span>
          </div>
        </div>
      )}
    </div>
  );
}

function DevicesPage({ devices, onRemoveDevice }: any) {
  return (
    <div className="flex flex-col h-full w-full max-w-2xl mx-auto px-6 py-4 space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-3xl font-bold font-heading tracking-tight">设备管理</h1>
          <p className="text-text-secondary text-sm">查看和管理已配对的受信任设备</p>
        </div>
      </div>

      <div className="glass-card rounded-3xl overflow-hidden min-h-[200px]">
        {devices.length === 0 ? (
          <div className="h-[300px] flex flex-col items-center justify-center text-text-muted gap-4">
            <Smartphone size={48} className="opacity-20" />
            <p>暂无已配对设备</p>
          </div>
        ) : (
          <div className="divide-y divide-border-subtle">
            {devices.map((device: any) => (
              <div key={device.id} className="p-6 flex items-center justify-between hover:bg-white/5 transition group">
                <div className="flex items-center gap-4">
                  <div className="w-12 h-12 bg-accent-blue/10 rounded-2xl flex items-center justify-center text-accent-blue">
                    <Smartphone size={24} />
                  </div>
                  <div>
                    <h3 className="font-bold text-text-primary">{device.name}</h3>
                    <p className="text-xs text-text-secondary font-mono">{device.id}</p>
                  </div>
                </div>
                <button
                  onClick={() => onRemoveDevice(device.id)}
                  className="p-2 text-text-muted hover:text-accent-destruct hover:bg-accent-destruct/10 rounded-xl transition-all opacity-0 group-hover:opacity-100 cursor-pointer"
                >
                  <Trash2 size={20} />
                </button>
              </div>
            ))}
          </div>
        )}
      </div>

      <div className="bg-accent-blue/5 p-4 rounded-2xl border border-accent-blue/10">
        <p className="text-xs text-accent-blue/80 leading-relaxed">
          <b>提示:</b> 移除设备后，下次连接需要重新扫描二维码配对。
        </p>
      </div>
    </div>
  );
}

function SettingsPage({ onRefresh }: { onRefresh: () => void }) {
  const [autoStart, setAutoStart] = useState(false);
  const [deviceName, setDeviceName] = useState("");
  const [saved, setSaved] = useState(false);
  const { theme, setTheme } = useContext(ThemeContext);

  useEffect(() => {
    // Load config
    invoke<any>("get_app_config").then(cfg => setDeviceName(cfg.device_name));

    import("@tauri-apps/plugin-autostart").then(async (autostart) => {
      try { setAutoStart(await autostart.isEnabled()); } catch (e) { }
    });
  }, []);

  const handleNameSave = async () => {
    try {
      await invoke("update_device_name", { name: deviceName });
      setSaved(true);
      onRefresh(); // Trigger refresh in parent
      setTimeout(() => setSaved(false), 2000);
    } catch (e) {
      console.error(e);
    }
  };

  const toggleAutoStart = async () => {
    const autostart = await import("@tauri-apps/plugin-autostart");
    if (autoStart) {
      await autostart.disable();
    } else {
      await autostart.enable();
    }
    setAutoStart(await autostart.isEnabled());
  };

  return (
    <div className="flex flex-col h-full p-6 space-y-8 animate-fade-in max-w-2xl mx-auto">
      <h1 className="text-3xl font-bold font-heading tracking-tight">设置</h1>

      <div className="glass-card rounded-3xl overflow-hidden divide-y divide-border-subtle">
        {/* Device Name */}
        <div className="p-6 space-y-4 hover:bg-white/5 transition">
          <div className="flex items-center gap-3">
            <div className="p-2 bg-accent-blue/10 rounded-xl text-accent-blue"> <Monitor size={20} /> </div>
            <div>
              <p className="text-sm font-bold">设备显示名称</p>
              <p className="text-xs text-text-secondary">手机端搜索时显示的名称</p>
            </div>
          </div>
          <div className="flex gap-2">
            <input
              value={deviceName}
              onChange={(e) => setDeviceName(e.target.value)}
              className="flex-1 bg-bg-deep/50 border border-border-subtle rounded-xl px-4 py-2 text-sm focus:outline-none focus:border-accent-blue transition"
              placeholder="输入设备名称"
            />
            <button
              onClick={handleNameSave}
              className={`px-6 py-2 rounded-xl text-sm font-bold transition-all cursor-pointer ${saved ? 'bg-accent-green text-white' : 'bg-accent-blue text-white hover:shadow-lg hover:shadow-accent-blue/30'}`}
            >
              {saved ? '已保存' : '更新'}
            </button>
          </div>
        </div>

        {/* Appearance */}
        <div className="p-6 flex items-center justify-between hover:bg-white/5 transition">
          <div className="flex items-center gap-3">
            <div className="p-2 bg-accent-blue/10 rounded-xl text-accent-blue"> <Moon size={20} /> </div>
            <div>
              <p className="text-sm font-bold">外观主题</p>
              <p className="text-xs text-text-secondary">当前模式: {theme === 'system' ? '跟随系统' : theme === 'dark' ? '深色' : '浅色'}</p>
            </div>
          </div>
          <div className="flex p-1 bg-bg-deep/50 rounded-xl border border-border-subtle">
            {(['system', 'light', 'dark'] as const).map((t) => (
              <button
                key={t}
                onClick={() => setTheme(t)}
                className={`px-3 py-1.5 rounded-lg text-xs font-bold transition-all cursor-pointer ${theme === t ? 'bg-white text-accent-blue shadow-sm shadow-black/5' : 'text-text-muted hover:text-text-primary'}`}
              >
                {t.toUpperCase()}
              </button>
            ))}
          </div>
        </div>

        {/* Auto Start */}
        <div className="p-6 flex items-center justify-between hover:bg-white/5 transition">
          <div className="flex items-center gap-3">
            <div className="p-2 bg-accent-green/10 rounded-xl text-accent-green"> <Power size={20} /> </div>
            <div>
              <p className="text-sm font-bold">开机自启</p>
              <p className="text-xs text-text-secondary">在系统登录时自动启动</p>
            </div>
          </div>
          <div
            onClick={toggleAutoStart}
            className={`w-12 h-6 rounded-full relative transition-colors cursor-pointer ${autoStart ? 'bg-accent-green' : 'bg-text-muted/30'}`}
          >
            <div className={`absolute top-1 left-1 w-4 h-4 rounded-full bg-white shadow-sm transition-transform ${autoStart ? 'translate-x-6' : ''}`} />
          </div>
        </div>
      </div>

      <div className="text-center mt-auto">
        <p className="text-[10px] text-text-muted font-mono tracking-widest uppercase">TypeBridge v1.1.0 (Vision OS)</p>
      </div>
    </div>
  )
}

function AppLayout() {
  const [serverInfo, setServerInfo] = useState<any>(null);
  const [connectedCount, setConnectedCount] = useState(0);
  const [devices, setDevices] = useState<any[]>([]);
  const [pairing, setPairing] = useState<any>(null);
  const [pairingSuccess, setPairingSuccess] = useState(false);
  const location = useLocation();

  const fetchData = useCallback(async () => {
    try {
      setServerInfo(await invoke("get_server_info"));
      setDevices(await invoke("get_devices"));
    } catch { }
  }, []);

  const handleRemoveDevice = async (deviceId: string) => {
    await invoke("remove_device", { deviceId });
    fetchData();
  };

  useEffect(() => {
    fetchData();
    const listeners = [
      listen<any>("connection-changed", (e) => setConnectedCount(e.payload.count)),
      listen<any>("pairing-requested", (e) => { setPairingSuccess(false); setPairing(e.payload); }),
      listen("pairing-success", () => { setPairingSuccess(true); setTimeout(() => { setPairing(null); setPairingSuccess(false); }, 1500); }),
      listen("devices-changed", fetchData)
    ];
    return () => { listeners.forEach(l => l.then(f => f())); };
  }, [fetchData]);

  return (
    <div className="flex w-screen h-screen bg-bg-deep/80 backdrop-blur-3xl overflow-hidden text-text-primary transition-colors duration-500 border border-white/5 rounded-xl shadow-2xl">
      {/* Sidebar Rail */}
      <aside data-tauri-drag-region className="w-24 bg-bg-glass backdrop-blur-2xl flex flex-col items-center py-8 z-20 border-r border-border-subtle">
        <div className="mb-10">
          <div className={`w-12 h-12 rounded-2xl flex items-center justify-center transition-all ${connectedCount > 0 ? 'bg-accent-green text-white shadow-lg shadow-accent-green/40' : 'bg-accent-blue/10 text-accent-blue'}`}>
            <Activity size={24} />
          </div>
        </div>

        <div className="flex-1 w-full px-4 space-y-6">
          <SidebarItem icon={Monitor} active={location.pathname === "/"} to="/" />
          <SidebarItem icon={Smartphone} active={location.pathname === "/devices"} to="/devices" />
          <SidebarItem icon={Settings} active={location.pathname === "/settings"} to="/settings" />
        </div>
      </aside>

      {/* Main Content Area */}
      <main className="flex-1 relative flex flex-col bg-white/5 overflow-hidden">
        {/* Window Drag Area - Top Bar */}
        <div data-tauri-drag-region className="h-12 w-full shrink-0 flex items-center justify-between px-6 z-30">
          <div data-tauri-drag-region className="flex-1 h-full" />
          <div className="flex items-center gap-2">
            {/* Potential window controls could go here if native titlebar is disabled entirely */}
          </div>
        </div>

        <div className="flex-1 overflow-y-auto scrollbar-none">
          <Routes>
            <Route path="/" element={
              <Dashboard
                serverInfo={serverInfo}
                connectedCount={connectedCount}
                devices={devices}
                pairing={pairing}
                setPairing={setPairing}
                pairingSuccess={pairingSuccess}
              />
            } />
            <Route path="/devices" element={
              <DevicesPage
                devices={devices}
                onRemoveDevice={handleRemoveDevice}
              />
            } />
            <Route path="/settings" element={<SettingsPage onRefresh={fetchData} />} />
          </Routes>
        </div>
      </main>
    </div>
  );
}

export default function App() {
  return (
    <HashRouter>
      <ThemeProvider>
        <AppLayout />
      </ThemeProvider>
    </HashRouter>
  );
}
