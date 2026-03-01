package main

import (
	"context"
	"embed"

	"github.com/wailsapp/wails/v2"
	"github.com/wailsapp/wails/v2/pkg/options"
	"github.com/wailsapp/wails/v2/pkg/options/assetserver"
	"github.com/wailsapp/wails/v2/pkg/runtime"
)

//go:embed all:frontend/dist
var assets embed.FS

//go:embed build/appicon.png
var icon []byte

func main() {
	// Create an instance of the app structure
	app := NewApp()


	// Create application with options
	err := wails.Run(&options.App{
		Title:  "appkeep",
		Width:  1024,
		Height: 768,
		AssetServer: &assetserver.Options{
			Assets: assets,
		},
		BackgroundColour: &options.RGBA{R: 27, G: 38, B: 54, A: 1},
		OnStartup:        app.startup,
		OnBeforeClose: func(ctx context.Context) (prevent bool) {
			if !app.isQuitting {
				runtime.WindowHide(ctx)
				return true
			}

			// 检查是否有运行中的应用
			summaries := app.GetAllStatus()
			hasRunning := false
			for _, s := range summaries {
				for _, inst := range s.Instances {
					if inst.Status == "running" { // models.StatusRunning
						hasRunning = true
						break
					}
				}
				if hasRunning { break }
			}

			if hasRunning {
				// 用户要求退出时默认必须把子进程都清理了，不再提示
				app.StopAllApps()
			}
			return false
		},
		Bind: []interface{}{
			app,
		},
	})

	if err != nil {
		println("Error:", err.Error())
	}
}
