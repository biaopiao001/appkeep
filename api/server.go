package api

import (
	"appkeep/models"
	"encoding/json"
	"fmt"
	"net/http"
)

// AppInterface 定义了 API 需要的主应用功能接口
type AppInterface interface {
	GetAllStatus() []models.AppStatusSummary
	GetConfigs() []models.AppConfig
	SaveConfig(cfg models.AppConfig) string
	DeleteConfig(id string)
	StartApp(configID string) (string, error)
	StopInstance(instanceID string) error
	ClearStoppedInstances(configID string)
}

// Server 定义了 API Http 服务结构
type Server struct {
	app AppInterface
}

// StartServer 启动 HTTP 后端 API 服务
func StartServer(app AppInterface, port int) error {
	if port <= 0 {
		port = 9420 // 默认端口
	}

	server := &Server{app: app}
	mux := http.NewServeMux()

	mux.HandleFunc("/api/status", server.handleStatus)
	mux.HandleFunc("/api/configs", server.handleConfigs)
	mux.HandleFunc("/api/apps/start", server.handleStartApp)
	mux.HandleFunc("/api/instances/stop", server.handleStopInstance)
	mux.HandleFunc("/api/configs/clean", server.handleCleanInstances)

	addr := fmt.Sprintf(":%d", port)
	fmt.Printf("[API Server] Starting on %s\n", addr)
	return http.ListenAndServe(addr, mux)
}

// writeJSON 是一个辅助函数，用于返回 JSON 响应
func writeJSON(w http.ResponseWriter, status int, data interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(data)
}

// writeError 是一个辅助函数，用于返回错误 JSON 响应
func writeError(w http.ResponseWriter, status int, message string) {
	writeJSON(w, status, map[string]string{"error": message})
}

func (s *Server) handleStatus(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeError(w, http.StatusMethodNotAllowed, "Method not allowed")
		return
	}
	status := s.app.GetAllStatus()
	writeJSON(w, http.StatusOK, map[string]interface{}{"data": status})
}

func (s *Server) handleConfigs(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		configs := s.app.GetConfigs()
		writeJSON(w, http.StatusOK, map[string]interface{}{"data": configs})

	case http.MethodPost:
		var cfg models.AppConfig
		if err := json.NewDecoder(r.Body).Decode(&cfg); err != nil {
			writeError(w, http.StatusBadRequest, "Invalid JSON payload")
			return
		}
		if cfg.Name == "" || cfg.ExecPath == "" {
			writeError(w, http.StatusBadRequest, "name and execPath are required")
			return
		}
		id := s.app.SaveConfig(cfg)
		writeJSON(w, http.StatusOK, map[string]string{"message": "Config saved", "id": id})

	case http.MethodDelete:
		id := r.URL.Query().Get("id")
		if id == "" {
			writeError(w, http.StatusBadRequest, "id parameter is required")
			return
		}
		s.app.DeleteConfig(id)
		writeJSON(w, http.StatusOK, map[string]string{"message": "Config deleted"})

	default:
		writeError(w, http.StatusMethodNotAllowed, "Method not allowed")
	}
}

func (s *Server) handleStartApp(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeError(w, http.StatusMethodNotAllowed, "Method not allowed")
		return
	}
	id := r.URL.Query().Get("id")
	if id == "" {
		writeError(w, http.StatusBadRequest, "id parameter is required")
		return
	}
	instanceID, err := s.app.StartApp(id)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"message": "App started", "instanceId": instanceID})
}

func (s *Server) handleStopInstance(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeError(w, http.StatusMethodNotAllowed, "Method not allowed")
		return
	}
	id := r.URL.Query().Get("id")
	if id == "" {
		writeError(w, http.StatusBadRequest, "id parameter is required")
		return
	}
	err := s.app.StopInstance(id)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"message": "Instance stopped"})
}

func (s *Server) handleCleanInstances(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeError(w, http.StatusMethodNotAllowed, "Method not allowed")
		return
	}
	id := r.URL.Query().Get("id")
	if id == "" {
		writeError(w, http.StatusBadRequest, "id parameter is required")
		return
	}
	s.app.ClearStoppedInstances(id)
	writeJSON(w, http.StatusOK, map[string]string{"message": "Instances cleaned"})
}
