# AppKeep Web API 使用说明

AppKeep 提供了一组 RESTful 风格的 HTTP API，可用于向第三方智能体或自动化脚本暴露 AppKeep 的运行状态并支持程序化控制（包括启动、停止、配置管理等）。

默认情况下，API 服务将在本地运行并监听端口 `9420`（可在系统全局设置 `ApiPort` 中更改）。所有接收/返回的 JSON 数据统一使用 `UTF-8` 编码。

## 1. 状态与配置获取

### 获取所有应用及其实例状态
获取当前监控的所有应用的配置详情以及各自的运行实例列表。

- **URL:** `GET /api/status`
- **示例:**
  ```bash
  curl -X GET http://localhost:9420/api/status
  ```
- **返回数据:**
  ```json
  {
    "data": [
      {
        "config": {
          "id": "app_123",
          "name": "My App",
          "execPath": "/path/to/app",
          "args": ["--port", "8080"],
          "allowMulti": false,
          "inheritEnv": true
        },
        "instances": [
          {
            "instanceId": "inst_456",
            "pid": 1234,
            "configId": "app_123",
            "status": "running",
            "source": "appkeep",
            "startTime": "2023-10-27T10:00:00Z",
            "exitCode": 0,
            "error": ""
          }
        ]
      }
    ]
  }
  ```

### 获取应用配置列表
获取应用面板中配置的应用元数据列表（不包括正在运行状态数据）。

- **URL:** `GET /api/configs`
- **示例:**
  ```bash
  curl -X GET http://localhost:9420/api/configs
  ```
- **返回数据:**与 `/api/status` 中的 `config` 对象数组结构一致。

## 2. 配置管理

### 添加或更新配置
添加新应用配置，若提供的 JSON 数据中带有已存在的 `id`，则为更新该配置。

- **URL:** `POST /api/configs`
- **Content-Type:** `application/json`
- **示例:**
  ```bash
  curl -X POST http://localhost:9420/api/configs \
    -H "Content-Type: application/json" \
    -d '{
      "id": "", 
      "name": "测试应用",
      "execPath": "/bin/sleep",
      "args": ["1000"],
      "allowMulti": true,
      "inheritEnv": true
    }'
  ```
- **返回数据:**
  ```json
  {
    "message": "Config saved",
    "id": "生成的或传入的唯一ID"
  }
  ```
> **注意**: `name` 和 `execPath` 必填，否则 API 将返回 `400 Bad Request`。如果 `id` 留空，系统会自动生成唯一标识符。

### 删除配置
删除指定 ID 的应用配置。建议在删除前先确保该应用运行中的实例已清空/停止。

- **URL:** `DELETE /api/configs?id=<配置ID>`
- **示例:**
  ```bash
  curl -X DELETE "http://localhost:9420/api/configs?id=app_123"
  ```
- **返回数据:**
  ```json
  {
    "message": "Config deleted"
  }
  ```

## 3. 运行控制

### 运行应用
根据给定的配置 ID 启动该应用的新实例。如果 `allowMulti` 为 `false` 且应用正处于运行中将返回错误。

- **URL:** `POST /api/apps/start?id=<配置ID>`
- **示例:**
  ```bash
  curl -X POST "http://localhost:9420/api/apps/start?id=app_123"
  ```
- **返回数据:**
  ```json
  {
    "message": "App started",
    "instanceId": "新启动实例的唯一ID"
  }
  ```

### 停止实例
根据给定的实例（Instance）ID 终止该实例的进程。实例 ID 可以通过 `/api/status` 查询。

- **URL:** `POST /api/instances/stop?id=<实例ID>`
- **示例:**
  ```bash
  curl -X POST "http://localhost:9420/api/instances/stop?id=inst_456"
  ```
- **返回数据:**
  ```json
  {
    "message": "Instance stopped"
  }
  ```

### 清理已停止记录
对于状态变为由 `running` 转为 `stopped` 且不再需要的实例历史记录对象，可以通过此接口清理从状态列表中移除（不保留挂掉或退出的痕迹）。传入应用配置 ID。

- **URL:** `POST /api/configs/clean?id=<配置ID>`
- **示例:**
  ```bash
  curl -X POST "http://localhost:9420/api/configs/clean?id=app_123"
  ```
- **返回数据:**
  ```json
  {
    "message": "Instances cleaned"
  }
  ```

## 4. 故障排除
如果 API 返回错误例如：
```json
{
  "error": "Error message details"
}
```
HTTP 状态码将相应地反映故障类型：
- **400**: 请求参数错误或缺失必要字段
- **405**: 采用了错误的 HTTP 请求方法
- **500**: 系统内部执行操作引发错误（例如启动进程失败）
