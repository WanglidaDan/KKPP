# KKPP Backend 腾讯云部署

当前后端已保持 Qwen / DashScope 兼容，不需要切换模型供应商。

## 推荐架构

- 腾讯云 CVM: Ubuntu 22.04
- Docker + Docker Compose
- Nginx 反向代理
- HTTPS 域名: 例如 `api.your-domain.com`

## 1. 服务器准备

```bash
sudo apt update
sudo apt install -y ca-certificates curl gnupg
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
newgrp docker
```

验证：

```bash
docker --version
docker compose version
```

## 2. 上传后端代码

建议目录：`/opt/kkpp/backend`

```bash
sudo mkdir -p /opt/kkpp
sudo chown -R $USER:$USER /opt/kkpp
cd /opt/kkpp
# 这里放 backend 目录
```

## 3. 生产环境变量

```bash
cd /opt/kkpp/backend
cp .env.production.example .env.production
```

至少填写：

- `DASHSCOPE_API_KEY`
- `CORS_ORIGINS`

如果暂时不用高精度转写，可以保留：

- `TRANSCRIPTION_API_KEY=` 空着

## 4. 配置域名和证书

修改文件：`nginx/conf.d/kkpp.conf`

把 `api.your-domain.com` 改成你的真实域名。

证书文件放到：

- `nginx/ssl/fullchain.pem`
- `nginx/ssl/privkey.pem`

如果你使用腾讯云负载均衡或 CDN 终止 HTTPS，也可以把 Nginx 先只保留 80 端口反代。

## 5. 启动服务

```bash
cd /opt/kkpp/backend
docker compose up -d --build
```

查看状态：

```bash
docker compose ps
docker compose logs -f kkpp-backend
docker compose logs -f nginx
```

## 6. 健康检查

```bash
curl http://127.0.0.1/health
curl https://api.your-domain.com/health
```

预期返回：

```json
{
  "ok": true,
  "service": "kkpp-backend",
  "collaborationMode": "synchronous-specialists"
}
```

## 7. iOS 端修改

把 iOS 里的 `KKPPBackendBaseURL` 改成你的正式域名，例如：

```text
https://api.your-domain.com
```

## 8. 更新发布

后续更新：

```bash
cd /opt/kkpp/backend
git pull
docker compose up -d --build
```

## 9. 稳定性建议

- `CORS_ORIGINS` 不要留空
- 给域名加 HTTPS
- 生产环境不要直接暴露 Node 3000 端口到公网
- 先用 CVM 单机部署，稳定后再考虑 CLB / 容器服务
- 如果后面并发上来，再补 Redis 会话和请求队列
