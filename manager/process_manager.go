package manager

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"

	"syscall"
	"io"
	"bufio"

	"appkeep/models"

	"github.com/wailsapp/wails/v2/pkg/runtime"

	"github.com/google/uuid"
)

type ProcessManager struct {
	configs   map[string]models.AppConfig
	instances map[string]*models.ProcessInstance
	logBuffers map[string][]string  // 为每个实例缓存日志
	mu        sync.RWMutex
	dataFile  string
	ctx       context.Context
}

func NewProcessManager(ctx context.Context, dataFile string) *ProcessManager {
	pm := &ProcessManager{
		configs:    make(map[string]models.AppConfig),
		instances:  make(map[string]*models.ProcessInstance),
		logBuffers: make(map[string][]string),
		dataFile:   dataFile,
		ctx:        ctx,
	}
	pm.loadConfigs()
	return pm
}

func (pm *ProcessManager) loadConfigs() {
	data, err := os.ReadFile(pm.dataFile)
	if err != nil {
		return
	}
	json.Unmarshal(data, &pm.configs)
}

func (pm *ProcessManager) saveConfigs() {
	pm.mu.RLock()
	defer pm.mu.RUnlock()
	data, _ := json.MarshalIndent(pm.configs, "", "  ")
	os.WriteFile(pm.dataFile, data, 0644)
}

func (pm *ProcessManager) SaveConfig(cfg models.AppConfig) string {
	pm.mu.Lock()
	if cfg.ID == "" {
		cfg.ID = uuid.New().String()
	}
	pm.configs[cfg.ID] = cfg
	pm.mu.Unlock()
	pm.saveConfigs()
	return cfg.ID
}

func (pm *ProcessManager) DeleteConfig(id string) {
	pm.mu.Lock()
	delete(pm.configs, id)
	pm.mu.Unlock()
	pm.saveConfigs()
}

func (pm *ProcessManager) GetConfigs() []models.AppConfig {
	pm.mu.RLock()
	defer pm.mu.RUnlock()
	var res []models.AppConfig
	for _, v := range pm.configs {
		res = append(res, v)
	}
	return res
}

func (pm *ProcessManager) StartApp(configID string) (string, error) {
	pm.mu.RLock()
	cfg, ok := pm.configs[configID]
	pm.mu.RUnlock()
	if !ok {
		return "", fmt.Errorf("config not found")
	}

	pm.mu.Lock()
	if !cfg.AllowMulti {
		for _, inst := range pm.instances {
			if inst.ConfigID == configID && inst.Status == models.StatusRunning {
				pm.mu.Unlock()
				return "", fmt.Errorf("app is already running and multi-instance is not allowed")
			}
		}
	}
	pm.mu.Unlock()

	cmd := exec.Command(cfg.ExecPath, cfg.Args...)
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	
	// 根据配置决定是否继承环境变量
	var envMap map[string]string
	
	if cfg.InheritEnv {
		// 继承当前进程的环境变量
		envMap = make(map[string]string)
		for _, env := range os.Environ() {
			parts := strings.SplitN(env, "=", 2)
			if len(parts) == 2 {
				envMap[parts[0]] = parts[1]
			}
		}
		
		// 尝试从用户的 shell 配置文件中加载额外的环境变量
		pm.loadUserEnvironment(envMap)
	} else {
		// 不继承环境变量，只设置最基本的环境变量
		envMap = make(map[string]string)
		
		// 设置基本的环境变量
		if home, err := os.UserHomeDir(); err == nil {
			envMap["HOME"] = home
		}
		
		if user := os.Getenv("USER"); user != "" {
			envMap["USER"] = user
		}
		
		// 设置最小的 PATH
		envMap["PATH"] = "/usr/local/bin:/usr/bin:/bin"
	}
	
	// 确保关键环境变量存在（无论哪种模式）
	if _, exists := envMap["HOME"]; !exists {
		if home, err := os.UserHomeDir(); err == nil {
			envMap["HOME"] = home
		}
	}
	
	if _, exists := envMap["USER"]; !exists {
		if user := os.Getenv("USER"); user != "" {
			envMap["USER"] = user
		}
	}
	
	// 添加或覆盖自定义环境变量
	if cfg.Env != nil {
		for key, value := range cfg.Env {
			envMap[key] = value
		}
	}
	
	// 构建环境变量数组
	cmd.Env = make([]string, 0, len(envMap))
	for key, value := range envMap {
		cmd.Env = append(cmd.Env, key+"="+value)
	}
	
	// 调试：打印关键环境变量
	fmt.Printf("启动进程 %s，继承环境变量: %t\n", cfg.Name, cfg.InheritEnv)
	
	// 打印当前进程的环境变量（用于调试）
	currentEnv := os.Environ()
	fmt.Printf("当前进程环境变量数量: %d\n", len(currentEnv))
	for _, env := range currentEnv {
		if strings.HasPrefix(env, "PATH=") {
			fmt.Printf("当前进程 PATH: %s\n", env)
			break
		}
	}
	
	if path, exists := envMap["PATH"]; exists {
		fmt.Printf("传递给子进程的 PATH: %s\n", path)
	}
	fmt.Printf("传递给子进程的环境变量数量: %d\n", len(envMap))

	stdout, _ := cmd.StdoutPipe()
	stderr, _ := cmd.StderrPipe()

	err := cmd.Start()
	if err != nil {
		return "", err
	}

	inst := &models.ProcessInstance{
		InstanceID: uuid.New().String(),
		PID:        cmd.Process.Pid,
		ConfigID:   configID,
		Status:     models.StatusRunning,
		Source:     "appkeep",
		StartTime:  time.Now(),
		Cmd:        cmd,
	}

	pm.mu.Lock()
	pm.instances[inst.InstanceID] = inst
	pm.mu.Unlock()

	// 启动日志监听
	go pm.streamLog(inst.InstanceID, stdout, "stdout")
	go pm.streamLog(inst.InstanceID, stderr, "stderr")

	go pm.monitorProcess(inst)

	return inst.InstanceID, nil
}

func (pm *ProcessManager) streamLog(instanceID string, reader io.Reader, source string) {
	scanner := bufio.NewScanner(reader)
	for scanner.Scan() {
		line := scanner.Text()
		
		// 缓存日志到内存（保留最近1000行）
		pm.mu.Lock()
		if pm.logBuffers[instanceID] == nil {
			pm.logBuffers[instanceID] = make([]string, 0)
		}
		pm.logBuffers[instanceID] = append(pm.logBuffers[instanceID], line)
		if len(pm.logBuffers[instanceID]) > 1000 {
			pm.logBuffers[instanceID] = pm.logBuffers[instanceID][len(pm.logBuffers[instanceID])-1000:]
		}
		pm.mu.Unlock()
		
		// 发送日志事件：log:<instanceID> -> "line content"
		runtime.EventsEmit(pm.ctx, "log:"+instanceID, line)
	}
}

func (pm *ProcessManager) monitorProcess(inst *models.ProcessInstance) {
	err := inst.Cmd.Wait()
	
	pm.mu.Lock()
	defer pm.mu.Unlock()

	if err != nil {
		inst.Status = models.StatusFailed
		inst.Error = err.Error()
		if exitErr, ok := err.(*exec.ExitError); ok {
			inst.ExitCode = exitErr.ExitCode()
		}
	} else {
		inst.Status = models.StatusStopped
		inst.ExitCode = 0
	}
	
	// 进程结束后保留日志缓存一段时间，但标记为已停止
	// 这样用户仍可以查看停止进程的日志
}

func (pm *ProcessManager) StopInstance(instanceID string) error {
	pm.mu.Lock()
	inst, ok := pm.instances[instanceID]
	pm.mu.Unlock()

	if !ok {
		return fmt.Errorf("instance not found")
	}

	if inst.Status != models.StatusRunning {
		return nil
	}

	if inst.Cmd != nil && inst.Cmd.Process != nil {
		// Kill(-pid) 发送信号给进程组，确保子进程也被终止
		if err := syscall.Kill(-inst.PID, syscall.SIGKILL); err != nil {
			// 如果进程组杀失败（可能因为权限或进程已不存在），尝试普通 Kill
			return inst.Cmd.Process.Kill()
		}
		return nil
	}
	return nil
}

func (pm *ProcessManager) GetAllStatus() []models.AppStatusSummary {
	// 检查已知实例的状态
	pm.CheckExternalStatus()
	// 注意：ScanExternalProcesses (pgrep) 比较耗时，改为手动触发

	pm.mu.RLock()
	defer pm.mu.RUnlock()
	
	instanceMap := make(map[string][]models.ProcessInstance)
	for _, inst := range pm.instances {
		instanceMap[inst.ConfigID] = append(instanceMap[inst.ConfigID], *inst)
	}

	var res []models.AppStatusSummary
	for _, cfg := range pm.configs {
		res = append(res, models.AppStatusSummary{
			Config:    cfg,
			Instances: instanceMap[cfg.ID],
		})
	}
	return res
}

func (pm *ProcessManager) ClearStoppedInstances(configID string) {
	pm.mu.Lock()
	defer pm.mu.Unlock()

	for id, inst := range pm.instances {
		if inst.ConfigID == configID && inst.Status != models.StatusRunning {
			delete(pm.instances, id)
		}
	}
}

func (pm *ProcessManager) ScanExternalProcesses() {
	pm.mu.RLock()
	configs := make([]models.AppConfig, 0, len(pm.configs))
	for _, cfg := range pm.configs {
		configs = append(configs, cfg)
	}
	pm.mu.RUnlock()

	for _, cfg := range configs {
		pm.scanForConfig(cfg)
	}
}

func (pm *ProcessManager) scanForConfig(cfg models.AppConfig) {
	execName := filepath.Base(cfg.ExecPath)
	if execName == "" || execName == "." {
		return
	}

	targetPath, err := filepath.EvalSymlinks(cfg.ExecPath)
	if err != nil {
		targetPath = cfg.ExecPath
	}
	absConfigPath, _ := filepath.Abs(targetPath)
	
	// 使用 pgrep -f -a 查找匹配命令行的进程
	// -f: 匹配完整命令行
	// -a: 输出 PID 和 命令行
	cmd := exec.Command("pgrep", "-f", "-a", execName)
	output, err := cmd.Output()
	if err != nil {
		// 尝试回退到精确名称匹配
		cmd = exec.Command("pgrep", "-x", "-a", execName)
		output, err = cmd.Output()
		if err != nil {
			return
		}
	}

	lines := strings.Split(strings.TrimSpace(string(output)), "\n")
	
	pm.mu.Lock()
	knownPIDs := make(map[int]bool)
	for _, inst := range pm.instances {
		if inst.ConfigID == cfg.ID && inst.Status == models.StatusRunning {
			knownPIDs[inst.PID] = true
		}
	}
	pm.mu.Unlock()

	for _, line := range lines {
		parts := strings.SplitN(line, " ", 2)
		if len(parts) < 2 {
			continue
		}
		
		pid, err := strconv.Atoi(parts[0])
		if err != nil {
			continue
		}

		if knownPIDs[pid] {
			continue
		}

		// 验证路径：
		// 1. 检查 /proc/<pid>/exe (硬核路径匹配)
		// 2. 如果失败，检查命令行是否包含配置路径
		exeLink := fmt.Sprintf("/proc/%d/exe", pid)
		realExePath, err := os.Readlink(exeLink)
		
		match := false
		if err == nil {
			if realExePath == absConfigPath || realExePath == cfg.ExecPath {
				match = true
			}
		} 
		
		// 如果 exe 链接匹配不上（比如脚本启动的解释器），尝试匹配命令行
		// 例如：python script.py，exe 是 python，但命令行包含 script.py
		if !match {
			cmdLine := parts[1]
			if strings.Contains(cmdLine, cfg.ExecPath) || strings.Contains(cmdLine, absConfigPath) {
				match = true
			}
		}

		if match {
			fmt.Printf("Detected external process for %s: PID %d (Path: %s)\n", cfg.Name, pid, realExePath)
			
			pm.mu.Lock()
			inst := &models.ProcessInstance{
				InstanceID: uuid.New().String(),
				PID:        pid,
				ConfigID:   cfg.ID,
				Status:     models.StatusRunning,
				Source:     "external",
				StartTime:  time.Now(),
			}
			pm.instances[inst.InstanceID] = inst
			pm.mu.Unlock()
		}
	}
}

func (pm *ProcessManager) CheckExternalStatus() {
	pm.mu.Lock()
	defer pm.mu.Unlock()

	for _, inst := range pm.instances {
		if inst.Status == models.StatusRunning && inst.Source == "external" {
			p, err := os.FindProcess(inst.PID)
			if err != nil {
				inst.Status = models.StatusFailed 
				inst.Error = "Process not found"
				continue
			}
			if err := p.Signal(syscall.Signal(0)); err != nil {
				inst.Status = models.StatusStopped
				inst.ExitCode = 0
			}
		}
	}
}

// GetInstanceLogs 获取指定实例的历史日志
func (pm *ProcessManager) GetInstanceLogs(instanceID string) []string {
	pm.mu.RLock()
	defer pm.mu.RUnlock()
	
	if logs, exists := pm.logBuffers[instanceID]; exists {
		// 返回日志副本，避免并发修改
		result := make([]string, len(logs))
		copy(result, logs)
		return result
	}
	return []string{}
}

// ClearInstanceLogs 清空指定实例的日志缓存
func (pm *ProcessManager) ClearInstanceLogs(instanceID string) {
	pm.mu.Lock()
	defer pm.mu.Unlock()
	
	delete(pm.logBuffers, instanceID)
}

// loadUserEnvironment 尝试从用户的 shell 配置文件中加载环境变量
func (pm *ProcessManager) loadUserEnvironment(envMap map[string]string) {
	// 尝试执行 bash -i -c 'env' 来获取交互式 shell 的环境变量
	cmd := exec.Command("bash", "-i", "-c", "env")
	output, err := cmd.Output()
	if err != nil {
		fmt.Printf("警告: 无法加载用户 shell 环境: %v\n", err)
		return
	}
	
	// 解析输出的环境变量
	lines := strings.Split(string(output), "\n")
	loadedCount := 0
	for _, line := range lines {
		if line == "" {
			continue
		}
		parts := strings.SplitN(line, "=", 2)
		if len(parts) == 2 {
			key, value := parts[0], parts[1]
			// 只覆盖重要的环境变量，避免破坏现有设置
			if pm.isImportantEnvVar(key) {
				if envMap[key] != value {
					fmt.Printf("更新环境变量 %s\n", key)
					envMap[key] = value
					loadedCount++
				}
			}
		}
	}
	fmt.Printf("从用户 shell 加载了 %d 个环境变量\n", loadedCount)
}

// isImportantEnvVar 判断是否是重要的环境变量
func (pm *ProcessManager) isImportantEnvVar(key string) bool {
	importantVars := []string{
		"PATH", "NVM_DIR", "NVM_BIN", "NVM_INC", "NVM_CD_FLAGS",
		"NODE_PATH", "NODE_ENV", "JAVA_HOME", "GOPATH", "GOROOT",
		"PYTHON_PATH", "PYTHONPATH", "CARGO_HOME", "RUSTUP_HOME",
	}
	
	for _, important := range importantVars {
		if key == important {
			return true
		}
	}
	
	// 也包含以这些前缀开头的变量
	prefixes := []string{"NVM_", "NODE_", "NPM_", "JAVA_", "GO", "PYTHON", "RUST"}
	for _, prefix := range prefixes {
		if strings.HasPrefix(key, prefix) {
			return true
		}
	}
	
	return false
}
