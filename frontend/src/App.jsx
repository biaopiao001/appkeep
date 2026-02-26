import {useState, useEffect} from 'react';
import './App.css';
import {GetConfigs, SaveConfig, DeleteConfig, StartApp, StopInstance, GetAllStatus, ClearStoppedInstances, ScanExternalProcesses, GetGlobalSettings, SaveGlobalSettings} from "../wailsjs/go/main/App";
import LogPanel from "./LogPanel";

function App() {
    const [apps, setApps] = useState([]);
    const [selectedConfigId, setSelectedConfigId] = useState(null);
    const [selectedInstanceId, setSelectedInstanceId] = useState(null); // New state for logs
    const [isModalOpen, setIsModalOpen] = useState(false);
    const [isSettingsOpen, setIsSettingsOpen] = useState(false);
    const [editingApp, setEditingApp] = useState(null);

    const refreshData = () => {
        GetAllStatus().then(res => {
            const sortedApps = res || [];
            // 简单的排序，保持列表稳定
            sortedApps.sort((a, b) => a.config.name.localeCompare(b.config.name));
            setApps(sortedApps);
        });
    };

    useEffect(() => {
        refreshData();
        const interval = setInterval(refreshData, 2000);
        return () => clearInterval(interval);
    }, []);

    // 当切换应用配置时，重置实例选择
    useEffect(() => {
        setSelectedInstanceId(null);
    }, [selectedConfigId]);

    const handleSaveConfig = (config) => {
        SaveConfig(config).then((id) => {
            setIsModalOpen(false);
            setEditingApp(null);
            refreshData();
            if (!config.id) {
                setSelectedConfigId(id); // 新建后自动选中
            }
        });
    };

    const handleDeleteConfig = (id) => {
        if (window.confirm("确定删除该配置吗？")) {
            DeleteConfig(id).then(() => {
                if (selectedConfigId === id) {
                    setSelectedConfigId(null);
                    setSelectedInstanceId(null); // 清空实例选择
                }
                refreshData();
            });
        }
    };

    const handleStartApp = (id) => {
        StartApp(id).then(() => {
            refreshData();
        }).catch(err => {
            alert("启动失败: " + err);
        });
    };

    const handleStopInstance = (instanceId) => {
        StopInstance(instanceId).then(refreshData);
    };

    const handleScan = () => {
        ScanExternalProcesses().then(refreshData);
    };

    const selectedAppSummary = apps.find(a => a.config.id === selectedConfigId);

    return (
        <div id="App">
            <Sidebar 
                apps={apps} 
                selectedId={selectedConfigId} 
                onSelect={setSelectedConfigId} 
                onAdd={() => { setEditingApp(null); setIsModalOpen(true); }}
                onScan={handleScan}
                onSettings={() => setIsSettingsOpen(true)}
            />
            
            <main className="main-content">
                {selectedAppSummary ? (
                    <AppDetail 
                        summary={selectedAppSummary}
                        onStart={() => handleStartApp(selectedAppSummary.config.id)}
                        onEdit={() => { setEditingApp(selectedAppSummary.config); setIsModalOpen(true); }}
                        onDelete={() => handleDeleteConfig(selectedAppSummary.config.id)}
                        onStopInstance={handleStopInstance}
                        selectedInstanceId={selectedInstanceId}
                        onSelectInstance={setSelectedInstanceId}
                    />
                ) : (
                    <div className="empty-state">
                        <p>请选择一个应用或添加新应用</p>
                    </div>
                )}
            </main>

            {isModalOpen && (
                <ConfigModal 
                    app={editingApp} 
                    onSave={handleSaveConfig} 
                    onClose={() => { setIsModalOpen(false); setEditingApp(null); }} 
                />
            )}

            {isSettingsOpen && (
                <SettingsModal 
                    onClose={() => setIsSettingsOpen(false)} 
                />
            )}
        </div>
    );
}

function Sidebar({apps, selectedId, onSelect, onAdd, onScan, onSettings}) {
    return (
        <aside className="sidebar">
            <div className="sidebar-header">
                <h2>AppKeep</h2>
                <div className="actions">
                    <button className="icon-only-btn" onClick={onSettings} title="全局设置">⚙️</button>
                    <button className="icon-only-btn" onClick={onScan} title="扫描外部进程">🔄</button>
                    <button className="add-btn" onClick={onAdd} title="添加应用">+</button>
                </div>
            </div>
            <div className="app-list scrollbar">
                {apps.map(item => {
                    const runningCount = (item.instances || []).filter(i => i.status === 'running').length;
                    return (
                        <div 
                            key={item.config.id} 
                            className={`app-list-item ${selectedId === item.config.id ? 'active' : ''}`}
                            onClick={() => onSelect(item.config.id)}
                        >
                            <span className="app-name">{item.config.name}</span>
                            {runningCount > 0 && <span className="running-badge">{runningCount}</span>}
                        </div>
                    );
                })}
            </div>
        </aside>
    );
}

function AppDetail({summary, onStart, onEdit, onDelete, onStopInstance, selectedInstanceId, onSelectInstance}) {
    const config = summary.config;
    const instances = summary.instances || [];

    // Auto-select first running instance if none selected, or if current selection is invalid
    useEffect(() => {
        if (instances.length > 0) {
           const running = instances.find(i => i.status === 'running');
           if (running) {
               // Only switch if we don't have a valid selection or selection is not in this list
               if (!selectedInstanceId || !instances.find(i => i.instanceId === selectedInstanceId)) {
                   onSelectInstance(running.instanceId);
               }
           } else {
               // No running instances, but there are stopped/failed instances
               // Check if current selection is still valid
               if (!selectedInstanceId || !instances.find(i => i.instanceId === selectedInstanceId)) {
                   // Select the first available instance (even if stopped)
                   onSelectInstance(instances[0].instanceId);
               }
           }
        } else {
            // No instances at all, clear selection
            onSelectInstance(null);
        }
    }, [instances, selectedInstanceId]);

    const handleClearStopped = (configId) => {
        ClearStoppedInstances(configId).then(refreshData);
    };

    const hasStopped = instances.some(i => i.status !== 'running');

    return (
        <div className="app-detail fade-in">
            <div className="detail-content"> {/* Wrap content for flex layout */}
                <header className="detail-header">
                    <div className="header-left">
                        <h1>{config.name}</h1>
                        <code className="path">{config.execPath}</code>
                    </div>
                    <div className="header-actions">
                        {hasStopped && (
                            <button className="secondary" onClick={() => handleClearStopped(config.id)} title="清除已停止/失败的卡片">
                                🧹 清理
                            </button>
                        )}
                        <button className="secondary" onClick={onEdit}>配置</button>
                        <button className="danger" onClick={onDelete}>删除</button>
                        <button className="primary big-btn" onClick={onStart}>
                            {instances.length > 0 && !config.allowMulti ? "已运行" : "启动新实例"}
                        </button>
                    </div>
                </header>

                <div className="instances-grid">
                    {instances.length === 0 ? (
                        <div className="no-instances">
                            <p>暂无运行实例</p>
                        </div>
                    ) : (
                        instances.map(inst => (
                            <InstanceCard 
                                key={inst.instanceId} 
                                inst={inst} 
                                isSelected={selectedInstanceId === inst.instanceId}
                                onClick={() => onSelectInstance(inst.instanceId)}
                                onStop={() => onStopInstance(inst.instanceId)} 
                            />
                        ))
                    )}
                </div>
            </div>
            
            {/* Log Panel at the bottom */}
            <LogPanel instanceId={selectedInstanceId} visible={!!selectedInstanceId} />
        </div>
    );
}

function InstanceCard({inst, onStop, onClick, isSelected}) {
    const isRunning = inst.status === 'running';
    return (
        <div 
            className={`instance-card ${inst.status} ${isSelected ? 'selected' : ''}`}
            onClick={onClick}
        >
            <div className="card-top">
                <div className="status-indicator">
                    <div className={`status-dot ${inst.status}`}></div>
                    <span className="status-text">{inst.status}</span>
                </div>
                <div className="card-actions">
                    {inst.source === 'external' && <span className="external-badge" title="外部启动的进程">EXT</span>}
                    {isRunning && (
                        <button className="icon-btn stop" onClick={(e) => { e.stopPropagation(); onStop(); }} title="停止">⏹</button>
                    )}
                </div>
            </div>
            <div className="card-body">
                <div className="info-row">
                    <label>PID</label>
                    <span className="mono">{inst.pid}</span>
                </div>
                <div className="info-row">
                    <label>开始时间</label>
                    <span>{new Date(inst.startTime).toLocaleTimeString()}</span>
                </div>
                {inst.status === 'failed' && (
                    <div className="error-message" title={inst.error}>{inst.error}</div>
                )}
                {inst.status === 'stopped' && (
                    <div className="exit-code">Exit Code: {inst.exitCode}</div>
                )}
                {isRunning && inst.source !== 'external' && (
                   <div className="log-hint">点击查看日志</div>
                )}
            </div>
        </div>
    );
}

function ConfigModal({app, onSave, onClose}) {
    const [name, setName] = useState(app?.name || "");
    const [execPath, setExecPath] = useState(app?.execPath || "");
    const [args, setArgs] = useState(app?.args?.join(" ") || "");
    const [proxy, setProxy] = useState(app?.proxy || "");
    const [allowMulti, setAllowMulti] = useState(app?.allowMulti || false);
    const [inheritEnv, setInheritEnv] = useState(app?.inheritEnv !== undefined ? app.inheritEnv : true); // 默认继承
    const [envVars, setEnvVars] = useState(() => {
        if (app?.env) {
            return Object.entries(app.env).map(([key, value]) => ({ key, value }));
        }
        return [];
    });

    const addEnvVar = () => {
        setEnvVars([...envVars, { key: "", value: "" }]);
    };

    const updateEnvVar = (index, field, value) => {
        const newEnvVars = [...envVars];
        newEnvVars[index][field] = value;
        setEnvVars(newEnvVars);
    };

    const removeEnvVar = (index) => {
        setEnvVars(envVars.filter((_, i) => i !== index));
    };

    const handleSubmit = (e) => {
        e.preventDefault();
        
        // 构建环境变量对象
        const env = {};
        envVars.forEach(({ key, value }) => {
            if (key.trim() && value.trim()) {
                env[key.trim()] = value.trim();
            }
        });

        onSave({
            id: app?.id || "",
            name,
            execPath,
            args: args.split(" ").filter(a => a !== ""),
            proxy: proxy.trim(),
            allowMulti,
            inheritEnv,
            env: Object.keys(env).length > 0 ? env : undefined
        });
    };

    return (
        <div className="modal-overlay fadeIn">
            <div className="modal-content scaleIn">
                <div className="modal-header">
                    <h2>{app ? "编辑应用配置" : "添加新应用"}</h2>
                    <button className="close-btn" onClick={onClose} title="关闭">×</button>
                </div>
                <form onSubmit={handleSubmit}>
                    <div className="modal-body">
                        <div className="form-group">
                            <label>应用名称</label>
                            <input value={name} onChange={e => setName(e.target.value)} placeholder="例如：我的 Nginx 服务" required autoFocus />
                            <small className="form-hint">显示在侧边栏的名称</small>
                        </div>
                        <div className="form-group">
                            <label>执行路径</label>
                            <input value={execPath} onChange={e => setExecPath(e.target.value)} placeholder="/usr/bin/nginx" required />
                            <small className="form-hint">可执行文件的绝对路径</small>
                        </div>
                        <div className="form-group">
                            <label>启动参数</label>
                            <input value={args} onChange={e => setArgs(e.target.value)} placeholder="-c /etc/nginx.conf" />
                            <small className="form-hint">参数之间用空格分隔</small>
                        </div>
                        <div className="form-group">
                            <label>应用代理</label>
                            <input value={proxy} onChange={e => setProxy(e.target.value)} placeholder="例如: socks5://127.0.0.1:1080 (留空使用全局代理)" />
                            <small className="form-hint">该代理会以环境变量形式传入。若不填且配置了全局代理，将使用全局代理。</small>
                        </div>
                        <div className="form-group checkbox-group">
                            <input type="checkbox" checked={allowMulti} onChange={e => setAllowMulti(e.target.checked)} id="multi" />
                            <label htmlFor="multi">
                                <span className="label-text">允许启动多个实例</span>
                                <span className="label-desc">开启后，应用可以同时运行多个副本（如终端、编辑器）</span>
                            </label>
                        </div>
                        <div className="form-group checkbox-group">
                            <input type="checkbox" checked={inheritEnv} onChange={e => setInheritEnv(e.target.checked)} id="inheritEnv" />
                            <label htmlFor="inheritEnv">
                                <span className="label-text">继承主进程环境变量</span>
                                <span className="label-desc">继承 AppKeep 的环境变量（包括 PATH、NODE_PATH 等），推荐开启</span>
                            </label>
                        </div>
                        <div className="form-group">
                            <label>环境变量</label>
                            <small className="form-hint">
                                {inheritEnv 
                                    ? "自定义环境变量会覆盖继承的变量。继承模式下可使用 node、npm、python 等命令。" 
                                    : "仅使用自定义环境变量和基本系统变量（HOME、USER、PATH=/usr/local/bin:/usr/bin:/bin）。"
                                }
                            </small>
                            {envVars.map((envVar, index) => (
                                <div key={index} className="env-var-row">
                                    <input 
                                        type="text" 
                                        placeholder="变量名" 
                                        value={envVar.key}
                                        onChange={e => updateEnvVar(index, 'key', e.target.value)}
                                    />
                                    <span>=</span>
                                    <input 
                                        type="text" 
                                        placeholder="变量值" 
                                        value={envVar.value}
                                        onChange={e => updateEnvVar(index, 'value', e.target.value)}
                                    />
                                    <button type="button" className="remove-env-btn" onClick={() => removeEnvVar(index)}>×</button>
                                </div>
                            ))}
                            <button type="button" className="add-env-btn" onClick={addEnvVar}>+ 添加环境变量</button>
                        </div>
                    </div>
                    <div className="modal-footer">
                        <button type="button" className="secondary large" onClick={onClose}>取消</button>
                        <button type="submit" className="primary large">保存配置</button>
                    </div>
                </form>
            </div>
        </div>
    );
}

function SettingsModal({onClose}) {
    const [proxy, setProxy] = useState("");

    useEffect(() => {
        GetGlobalSettings().then(settings => {
            if (settings && settings.proxy) {
                setProxy(settings.proxy);
            }
        });
    }, []);

    const handleSubmit = (e) => {
        e.preventDefault();
        SaveGlobalSettings({
            proxy: proxy.trim()
        }).then(() => {
            onClose();
        });
    };

    return (
        <div className="modal-overlay fadeIn">
            <div className="modal-content scaleIn" style={{maxWidth: '400px'}}>
                <div className="modal-header">
                    <h2>全局设置</h2>
                    <button className="close-btn" onClick={onClose} title="关闭">×</button>
                </div>
                <form onSubmit={handleSubmit}>
                    <div className="modal-body">
                        <div className="form-group">
                            <label>全局代理</label>
                            <input 
                                value={proxy} 
                                onChange={e => setProxy(e.target.value)} 
                                placeholder="例如: http://127.0.0.1:7890" 
                                autoFocus 
                            />
                            <small className="form-hint">子应用未配置代理时，将默认使用此设置。</small>
                        </div>
                    </div>
                    <div className="modal-footer">
                        <button type="button" className="secondary large" onClick={onClose}>取消</button>
                        <button type="submit" className="primary large">保存全局设置</button>
                    </div>
                </form>
            </div>
        </div>
    );
}

export default App;
