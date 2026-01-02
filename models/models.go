package models

import (
	"os/exec"
	"time"
)

type InstanceStatus string

const (
	StatusRunning InstanceStatus = "running"
	StatusStopped InstanceStatus = "stopped"
	StatusFailed  InstanceStatus = "failed"
)

type AppConfig struct {
	ID           string            `json:"id"`
	Name         string            `json:"name"`
	ExecPath     string            `json:"execPath"`
	Args         []string          `json:"args"`
	AllowMulti   bool              `json:"allowMulti"`
	Env          map[string]string `json:"env,omitempty"`          // 自定义环境变量
	InheritEnv   bool              `json:"inheritEnv"`             // 是否继承主进程环境变量
}

type ProcessInstance struct {
	InstanceID string         `json:"instanceId"`
	PID        int            `json:"pid"`
	ConfigID   string         `json:"configId"`
	Status     InstanceStatus `json:"status"`
	Source     string         `json:"source"` // "appkeep" or "external"
	StartTime  time.Time      `json:"startTime"`
	ExitCode   int            `json:"exitCode"`
	Error      string         `json:"error"`
	Cmd        *exec.Cmd      `json:"-"`
}

type AppStatusSummary struct {
	Config    AppConfig         `json:"config"`
	Instances []ProcessInstance `json:"instances"`
}
