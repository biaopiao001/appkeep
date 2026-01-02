
import { useState, useEffect, useRef } from 'react';
import { EventsOn, EventsOff } from "../wailsjs/runtime/runtime";
import { GetInstanceLogs, ClearInstanceLogs } from "../wailsjs/go/main/App";

function LogPanel({ instanceId, visible }) {
    const [logs, setLogs] = useState([]);
    const logsEndRef = useRef(null);
    const contentRef = useRef(null);
    const [isCollapsed, setIsCollapsed] = useState(false);
    const [isLoading, setIsLoading] = useState(false);
    const eventListenerRef = useRef(null);

    useEffect(() => {
        // 清理之前的事件监听器
        if (eventListenerRef.current) {
            EventsOff("log:" + eventListenerRef.current);
            eventListenerRef.current = null;
        }

        if (!instanceId) {
            setLogs([]);
            setIsLoading(false);
            return;
        }

        setIsLoading(true);
        
        // 首先获取历史日志
        GetInstanceLogs(instanceId).then(historicalLogs => {
            setLogs(historicalLogs || []);
            setIsLoading(false);
            
            // 然后订阅新的日志事件
            eventListenerRef.current = instanceId;
            EventsOn("log:" + instanceId, (line) => {
                setLogs(prev => {
                    const newLogs = [...prev, line];
                    // 保持最近1000行
                    return newLogs.length > 1000 ? newLogs.slice(-1000) : newLogs;
                });
            });
        }).catch(err => {
            console.error("Failed to load historical logs:", err);
            setIsLoading(false);
            
            // 即使历史日志加载失败，也要订阅新日志
            eventListenerRef.current = instanceId;
            EventsOn("log:" + instanceId, (line) => {
                setLogs(prev => {
                    const newLogs = [...prev, line];
                    return newLogs.length > 1000 ? newLogs.slice(-1000) : newLogs;
                });
            });
        });

        // 清理函数
        return () => {
            if (eventListenerRef.current) {
                EventsOff("log:" + eventListenerRef.current);
                eventListenerRef.current = null;
            }
        };
    }, [instanceId]);

    useEffect(() => {
        if (visible && !isCollapsed && logsEndRef.current) {
            logsEndRef.current.scrollIntoView({ behavior: "smooth" });
        }
    }, [logs, visible, isCollapsed]);

    const handleClearLogs = (e) => {
        e.stopPropagation();
        if (instanceId) {
            // 清空后端缓存和前端显示
            ClearInstanceLogs(instanceId).then(() => {
                setLogs([]);
            }).catch(err => {
                console.error("Failed to clear logs:", err);
                // 即使后端清理失败，也清空前端显示
                setLogs([]);
            });
        } else {
            setLogs([]);
        }
    };

    if (!visible) return null;

    return (
        <div className={`log-panel ${isCollapsed ? 'collapsed' : ''}`}>
            <div className="log-header" onClick={() => setIsCollapsed(!isCollapsed)}>
                <span className="log-title">
                    Console Output {instanceId ? `(#${instanceId.substring(0, 8)})` : ''}
                </span>
                <div className="log-actions">
                    <button className="icon-btn" onClick={handleClearLogs}>
                        🗑️
                    </button>
                    <span className="collapse-icon">{isCollapsed ? '🔼' : '🔽'}</span>
                </div>
            </div>
            {!isCollapsed && (
                <div className="log-content scrollbar" ref={contentRef}>
                    {isLoading ? (
                        <div className="log-empty">Loading logs...</div>
                    ) : logs.length === 0 ? (
                        <div className="log-empty">Waiting for output...</div>
                    ) : (
                        logs.map((line, i) => (
                            <div key={i} className="log-line">{line}</div>
                        ))
                    )}
                    <div ref={logsEndRef} />
                </div>
            )}
        </div>
    );
}

export default LogPanel;
