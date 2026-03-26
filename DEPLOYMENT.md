# KKPP 部署与测试

## 后端本地运行

```bash
cd /Users/wanglida/Desktop/KKPP/backend
cp .env.example .env
npm install
npm run dev
```

`.env` 至少需要配置：

```bash
PORT=3000
DASHSCOPE_API_KEY=你的阿里云百炼 Key
DASHSCOPE_BASE_URL=https://coding.dashscope.aliyuncs.com/v1
DEFAULT_MODEL=qwen3.5-plus
COMPLEX_MODEL=qwen3-max-2026-01-23
TIMEZONE=Asia/Shanghai
MEMORY_WINDOW=12
```

## 腾讯云部署

```bash
cd /data/www/KKPP/backend
npm install --production
pm2 start server.js --name kkpp-backend
pm2 save
pm2 startup
```

推荐使用 Nginx 反向代理：

```nginx
server {
    listen 80;
    server_name your-domain.com;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Connection '';
        chunked_transfer_encoding off;
        proxy_buffering off;
        proxy_cache off;
    }
}
```

重载配置：

```bash
sudo nginx -t
sudo systemctl reload nginx
```

## iOS 接入说明

1. 在 Xcode 新建 `App` 项目，名称填写 `KKPP`。
2. 将 `/Users/wanglida/Desktop/KKPP/ios/KKPP` 下所有 `.swift` 文件加入工程。
3. 将 `Resources/Info.plist` 内容同步到项目的 `Info.plist`。
4. 在 `Signing & Capabilities` 中开启：
   - `Sign in with Apple`
   - `Background Modes` 不必开启
5. 在 `ContentView.swift` 中把 `BackendService(baseURLString:)` 改成你的腾讯云后端地址。

## 简单测试流程

1. 启动后端，访问 `GET /health`，确认返回 `ok: true`。
2. 打开 iOS App，先点击 Apple 登录。
3. 首次进入时允许：
   - 麦克风
   - 语音识别
   - 日历完全访问
4. 按住麦克风说：
   - `明天上午10點和客戶開會一小時，在會議室`
5. 预期结果：
   - 聊天页出现繁体中文秘书式确认
   - 系统日历新增对应事件
6. 再说：
   - `今天有什麼安排`
7. 预期结果：
   - 聊天页返回今日行程总结
   - 我的日程页显示未来 7 天事件

## 当前 v1 边界

- 支持新增日程
- 支持查询今天与未来日程
- 不支持删除或改期
- 会话记忆保存在后端内存，重启后会清空
