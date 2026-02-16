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

  // Simple theme application logic
  useEffect(() => {
    localStorage.setItem('theme', theme);
    const root = window.document.documentElement;

    // Remove both classes first
    root.classList.remove('light', 'dark');

    const computeTheme = () => {
      if (theme === 'system') {
        return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
      }
      return theme;
    };

    const resolved = computeTheme();
    root.classList.add(resolved);
    setCurrentTheme(resolved as 'light' | 'dark');

    // Listener for system changes
    const mq = window.matchMedia('(prefers-color-scheme: dark)');
    const onChange = () => {
      if (theme === 'system') {
        root.classList.remove('light', 'dark');
        const newResolved = mq.matches ? 'dark' : 'light';
        root.classList.add(newResolved);
        setCurrentTheme(newResolved as 'light' | 'dark');
      }
    };
    mq.addEventListener('change', onChange);
    return () => mq.removeEventListener('change', onChange);
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
        <div className={`flex items-center gap-3 px-5 py-2 rounded-2xl bg-bg-card border border-border-subtle shadow-sm`}>
          <div className={`w-2.5 h-2.5 rounded-full ${connectedCount > 0 ? 'bg-accent-green animate-pulse shadow-[0_0_12px_rgba(34,197,94,0.6)]' : 'bg-text-muted'}`} />
          <span className="text-sm font-bold tracking-tight text-text-primary">
            {connectedCount > 0 ? "已连接通信中" : "空闲中"}
          </span>
        </div>
      </div>

      {/* Hero Stats Grid - 2x2 or 4x1 */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-6 mb-10">
        <div className="glass-card p-6 rounded-4xl border-white/5 flex flex-col justify-between min-h-40">
          <div className="space-y-3">
            <div className="p-3 bg-accent-blue/10 rounded-2xl w-fit text-accent-blue"><Wifi size={24} /></div>
            <p className="text-sm font-bold text-text-secondary opacity-60 uppercase tracking-widest">内网地址</p>
          </div>
          <p className="text-lg font-mono font-black text-text-primary break-all leading-tight">{serverInfo?.ip || "获取中..."}</p>
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

        <div className="glass-card p-6 rounded-4xl border-white/5 flex flex-col justify-between min-h-40">
          <div className="space-y-3">
            <div className="p-3 bg-white/5 rounded-2xl w-fit text-text-primary"><Smartphone size={24} /></div>
            <p className="text-sm font-bold text-text-secondary opacity-60 uppercase tracking-widest">活跃连接</p>
          </div>
          <div className="flex items-baseline gap-2">
            <span className="text-4xl font-black text-accent-blue">{connectedCount}</span>
            <span className="text-text-muted font-bold italic">Active</span>
          </div>
        </div>
      </div>

      {/* Bottom spacer is handled by container pb-12, removed extra card */}

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

// Helper to map OS strings nicely
function getMappedOS(os: string | undefined) {
  if (!os) return "MOBILE";
  const lower = os.toLowerCase();
  if (lower.includes('android')) return "ANDROID";
  if (lower.includes('ios')) return "IOS";
  return os.toUpperCase();
}

function DevicesPage({ devices, onRemoveDevice, onUpdateAlias }: any) {
  const [editingId, setEditingId] = useState<string | null>(null);
  const [aliasBuffer, setAliasBuffer] = useState("");

  const handleStartEdit = (device: any) => {
    setEditingId(device.id);
    setAliasBuffer(device.alias || "");
  };

  const handleSaveEdit = async (id: string) => {
    await onUpdateAlias(id, aliasBuffer);
    setEditingId(null);
  };

  return (
    <div className="flex flex-col h-full w-full max-w-3xl mx-auto px-6 py-4 space-y-8 pb-12">
      <div>
        <h1 className="text-3xl font-bold font-heading tracking-tight text-text-primary">设备管理</h1>
        <p className="text-text-secondary text-sm">查看、重命名或取消已配对设备的授权</p>
      </div>

      {devices.length === 0 ? (
        <div className="glass-card rounded-4xl h-64 flex flex-col items-center justify-center text-text-muted gap-4">
          <Smartphone size={48} className="opacity-20" />
          <p>暂无已配对设备</p>
        </div>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          {devices.map((device: any) => (
            <div key={device.id} className="glass-card p-6 rounded-3xl border-white/5 space-y-4 group relative overflow-hidden">
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-3">
                  <div className={`p-2.5 rounded-xl ${device.current_ip ? 'bg-accent-green/10 text-accent-green' : 'bg-accent-blue/10 text-accent-blue'}`}>
                    <Smartphone size={20} />
                  </div>
                  <div>
                    {editingId === device.id ? (
                      <input
                        autoFocus
                        value={aliasBuffer}
                        onChange={(e) => setAliasBuffer(e.target.value)}
                        onBlur={() => handleSaveEdit(device.id)}
                        onKeyDown={(e) => e.key === 'Enter' && handleSaveEdit(device.id)}
                        className="bg-bg-deep/50 border border-accent-blue rounded-lg px-2 py-0.5 text-sm focus:outline-none mb-1"
                      />
                    ) : (
                      <h3 className="font-bold text-text-primary flex items-center gap-2 mb-1">
                        {device.alias || device.name}
                        <button onClick={() => handleStartEdit(device)} className="opacity-0 group-hover:opacity-100 transition p-1 hover:bg-white/10 rounded-md cursor-pointer">
                          <Power size={12} className="rotate-90" />
                        </button>
                      </h3>
                    )}

                    {/* IP Address Row */}
                    {device.current_ip && (
                      <p className="text-xs font-mono text-accent-green font-bold mb-1 flex items-center gap-1">
                        <div className="w-1.5 h-1.5 rounded-full bg-accent-green animate-pulse" />
                        {device.current_ip}
                      </p>
                    )}

                    {/* Metadata Row */}
                    <div className="flex items-center gap-2 text-[10px] text-text-secondary opacity-80">
                      <span className="bg-white/5 px-1.5 py-0.5 rounded uppercase tracking-wider font-bold">
                        {getMappedOS(device.os)}
                      </span>
                      <span>{device.current_ip ? "在线" : "离线"}</span>
                    </div>
                  </div>
                </div>
                <button
                  onClick={() => onRemoveDevice(device.id)}
                  className="p-2 text-text-muted hover:text-accent-destruct hover:bg-accent-destruct/10 rounded-xl transition cursor-pointer"
                >
                  <Trash2 size={18} />
                </button>
              </div>

            </div>
          ))}
        </div>
      )}

      <div className="bg-accent-blue/5 p-4 rounded-2xl border border-accent-blue/10">
        <p className="text-xs text-accent-blue/80 leading-relaxed font-medium">
          <b>安全提示:</b> 移除设备后，该设备持有的令牌将失效，下次连接需重新验证。
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

  const handleUpdateAlias = async (deviceId: string, alias: string) => {
    await invoke("update_device_alias", { deviceId, alias });
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

  // Simple and clean main layout, no forced rounded corners or borders on the window itself
  return (
    <div className="flex w-screen h-screen bg-bg-deep text-text-primary select-none overflow-hidden">
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
      <main className="flex-1 relative flex flex-col overflow-hidden">
        {/* Window Drag Area - Top Bar */}
        <div data-tauri-drag-region className="h-6 w-full shrink-0 flex items-center justify-between px-6 z-30">
        </div>

        <div className="flex-1 overflow-y-auto scrollbar-none pb-12">
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
                onUpdateAlias={handleUpdateAlias}
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
