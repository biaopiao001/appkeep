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
				dialog, err := runtime.MessageDialog(ctx, runtime.MessageDialogOptions{
					Type:          runtime.QuestionDialog,
					Title:         "退出确认",
					Message:       "还有应用在后台运行，是否要在退出前关闭它们？",
					Buttons:       []string{"关闭所有并退出", "保留运行并退出", "取消"},
					DefaultButton: "取消",
					CancelButton:  "取消",
				})
				if err != nil {
					return false
				}

				switch dialog {
				case "关闭所有并退出":
					app.StopAllApps()
					return false
				case "保留运行并退出":
					return false
				case "取消":
					return true
				}
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
