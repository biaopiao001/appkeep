package main

import (
	"context"
	"appkeep/manager"
	"appkeep/models"
	"os"
	"path/filepath"

	"github.com/energye/systray"
	"github.com/wailsapp/wails/v2/pkg/runtime"
)

// App struct
type App struct {
	ctx        context.Context
	manager    *manager.ProcessManager
	isQuitting bool
}

// NewApp creates a new App application struct
func NewApp() *App {
	return &App{}
}

// startup is called when the app starts. The context is saved
// so we can call the runtime methods
func (a *App) startup(ctx context.Context) {
	a.ctx = ctx
	
	// Start systray
	go systray.Run(a.onTrayReady, a.onTrayExit)

	// 设置数据存储路径
	home, _ := os.UserHomeDir()
	configDir := filepath.Join(home, ".appkeep")
	os.MkdirAll(configDir, 0755)
	dataFile := filepath.Join(configDir, "config.json")
	
	a.manager = manager.NewProcessManager(ctx, dataFile)
}

func (a *App) onTrayReady() {
	systray.SetIcon(iconData)
	systray.SetTitle("AppKeep")
	systray.SetTooltip("AppKeep - 应用保活管理")

	mShow := systray.AddMenuItem("显示主窗口", "Show Main Window")
	mQuit := systray.AddMenuItem("退出", "Quit Application")

	mShow.Click(func() {
		runtime.WindowShow(a.ctx)
	})

	mQuit.Click(func() {
		a.isQuitting = true
		systray.Quit()
		runtime.Quit(a.ctx)
	})
}

func (a *App) onTrayExit() {
	// Cleanup here
}

// GetConfigs 获取所有应用配置
func (a *App) GetConfigs() []models.AppConfig {
	return a.manager.GetConfigs()
}

// SaveConfig 保存或更新应用配置
func (a *App) SaveConfig(cfg models.AppConfig) string {
	return a.manager.SaveConfig(cfg)
}

// DeleteConfig 删除应用配置
func (a *App) DeleteConfig(id string) {
	a.manager.DeleteConfig(id)
}

// StartApp 启动应用实例
func (a *App) StartApp(configID string) (string, error) {
	return a.manager.StartApp(configID)
}

// StopInstance 停止应用实例
func (a *App) StopInstance(instanceID string) error {
	return a.manager.StopInstance(instanceID)
}

// GetAllStatus 获取所有应用及其状态
func (a *App) GetAllStatus() []models.AppStatusSummary {
	return a.manager.GetAllStatus()
}

// ScanExternalProcesses 手动扫描外部进程
func (a *App) ScanExternalProcesses() {
	a.manager.ScanExternalProcesses()
}

// ClearStoppedInstances 清理已停止的实例
func (a *App) ClearStoppedInstances(configID string) {
	a.manager.ClearStoppedInstances(configID)
}

// StopAllApps 停止所有运行中的应用
func (a *App) StopAllApps() {
	summaries := a.manager.GetAllStatus()
	for _, summary := range summaries {
		for _, inst := range summary.Instances {
			if inst.Status == models.StatusRunning {
				if err := a.manager.StopInstance(inst.InstanceID); err != nil {
					runtime.LogErrorf(a.ctx, "Failed to stop instance %s (PID %d): %v", inst.InstanceID, inst.PID, err)
				}
			}
		}
	}
}

// GetInstanceLogs 获取指定实例的历史日志
func (a *App) GetInstanceLogs(instanceID string) []string {
	return a.manager.GetInstanceLogs(instanceID)
}

// ClearInstanceLogs 清空指定实例的日志缓存
func (a *App) ClearInstanceLogs(instanceID string) {
	a.manager.ClearInstanceLogs(instanceID)
}
