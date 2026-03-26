# KKPP

KKPP 是一个面向中文场景的 iOS 私人 AI Agent 日历助理。它结合本地语音识别、EventKit 日历执行和 Node.js 后端智能编排，让你像在和一位专业秘书说话一样，直接通过自然语言创建和查询日程。

## 核心能力

- 语音驱动：按住麦克风实时转写，松手自动发送
- 多 Agent 风格后端：意图识别、日程规划、工具决策、秘书式回复
- 真执行：通过 EventKit 把会议写入系统日历
- 流式反馈：后端支持 SSE，聊天界面逐字显示回复
- 多轮记忆：按 `userId` 维护最近若干轮会话上下文
- 双端结构：iOS 负责交互与本地执行，Node.js 负责模型与编排

## 项目结构

```text
KKPP
├── backend
│   ├── .env.example
│   ├── package.json
│   └── server.js
├── ios
│   ├── KKPP.xcodeproj
│   ├── KKPP
│   │   ├── Managers
│   │   ├── Models
│   │   ├── Resources
│   │   ├── Services
│   │   ├── ViewModels
│   │   ├── Views
│   │   └── KKPPApp.swift
│   └── project.yml
└── DEPLOYMENT.md
```

## 技术栈

- iOS: SwiftUI, Speech, AVFoundation, EventKit, AuthenticationServices
- Backend: Node.js, Express, OpenAI SDK 兼容模式
- Model Provider: DashScope Coding API
- Models:
  - `qwen3.5-plus`
  - `qwen3-max-2026-01-23`

## 本地运行

### 1. 启动后端

```bash
cd /Users/wanglida/Desktop/KKPP/backend
cp .env.example .env
npm install
npm run dev
```

确认健康检查正常：

```bash
curl http://127.0.0.1:3000/health
```

### 2. 打开 iOS 工程

```bash
open /Users/wanglida/Desktop/KKPP/ios/KKPP.xcodeproj
```

如果你修改了 `ios/project.yml`，记得重新生成工程：

```bash
cd /Users/wanglida/Desktop/KKPP/ios
xcodegen generate
```

## 真机联调说明

- iPhone 或 iPad 需要和 Mac 处于同一 Wi‑Fi
- 当前默认本地后端地址配置在 `Info.plist` 的 `KKPPBackendBaseURL`
- 本项目默认本地调试地址为：

```text
http://192.168.1.195:3000
```

- 如果你的 Mac 局域网地址变化了，需要同步更新这个字段

## 当前版本支持

- 新增日程
- 查询今天与未来日程
- 简体中文秘书式回复
- 普通话优先的实时语音识别
- Apple 登录标识用户

## 当前版本暂不支持

- 删除日程
- 改期执行
- 多设备同步
- 服务端持久化记忆

## 后端接口

### `GET /health`

用于健康检查和真机联网调试。

### `POST /process`

请求体：

```json
{
  "userId": "apple-user-id",
  "text": "请帮我安排明天下午三点和客户开会一小时，在会议室",
  "timezone": "Asia/Shanghai",
  "calendarContext": {
    "events": []
  }
}
```

响应体：

```json
{
  "reply": "好的，已为您安排好明天下午三点的客户会议……",
  "structuredAction": {
    "type": "add_calendar_event",
    "payload": {
      "title": "客户会议",
      "startISO": "2026-03-27T15:00:00+08:00",
      "durationHours": 1,
      "notes": "与客户开会",
      "location": "会议室",
      "reminderMinutesBefore": 15
    }
  }
}
```

### `POST /process/stream`

使用 SSE 返回事件：

- `action`
- `token`
- `done`
- `error`

## GitHub

仓库地址：

- [WanglidaDan/KKPP](https://github.com/WanglidaDan/KKPP)
