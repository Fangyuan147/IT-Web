# Ubuntu IT 运维实战项目

这是一个面向学习和作品集展示的 Ubuntu 单机运维项目：部署三个 Flask/Gunicorn 后端，由 Nginx 通过 `3:2:1` 权重统一代理，并使用 systemd、UFW、logrotate、健康检查、备份和故障演练完成服务生命周期管理。

> 项目定位：个人实战项目，适合在 Ubuntu 本机、虚拟机或云服务器上复现。它不是生产级高可用平台，真实生产环境还需要监控告警、密钥管理、HTTPS、集中日志和灾备策略。

## 架构

```text
客户端
  │
  ▼
UFW → Nginx :80
          │ upstream（权重 3:2:1）
          ├── 127.0.0.1:8000 → ops-demo
          ├── 127.0.0.1:8001 → ops-demo1
          └── 127.0.0.1:8002 → ops-demo2
```

三个后端只监听 `127.0.0.1`，外部请求只进入 Nginx。权重表示长期相对比例：8000、8001、8002 理论上约承担 50%、33.3%、16.7% 的请求，不保证每 6 次请求严格按比例分配。

## 目录结构

```text
ops-demo/
├── apps/
│   ├── ops-demo/app.py
│   ├── ops-demo1/app.py
│   └── ops-demo2/app.py
├── config/
│   ├── logrotate/ops-demo
│   ├── nginx/ops-demo.conf
│   └── systemd/
│       ├── ops-demo.service
│       ├── ops-demo1.service
│       └── ops-demo2.service
├── scripts/
│   ├── backup.sh
│   ├── back.sh
│   ├── check.sh
│   ├── deploy.sh
│   └── health-check.sh
├── docs/
│   ├── architecture.md
│   └── incident-review.md
├── .gitignore
├── requirements.txt
└── README.md
```

## 环境准备

推荐 Ubuntu 22.04/24.04，准备一个有 `sudo` 权限的普通用户。安装依赖：

```bash
sudo apt update
sudo apt install -y nginx python3 python3-venv python3-pip curl ufw logrotate
```

项目 Python 依赖在 `requirements.txt` 中，目前包括 Flask 和 Gunicorn。

## 部署流程

将项目放到 Ubuntu 后，在项目根目录执行：

```bash
chmod +x scripts/*.sh
sudo ./scripts/deploy.sh
```

部署脚本会完成以下工作：

1. 创建受限系统用户 `opsdemo` 和 `/opt/ops-demo` 运行目录。
2. 复制应用、配置、脚本和依赖清单。
3. 创建 Python 虚拟环境并安装 Flask/Gunicorn。
4. 安装并启动三个 systemd 服务。
5. 安装 logrotate 配置。
6. 如果系统已安装 Nginx，则安装站点配置、检查语法并重载 Nginx。

## 验收检查

```bash
curl --fail http://127.0.0.1:8000/health
curl --fail http://127.0.0.1:8001/health
curl --fail http://127.0.0.1:8002/health
curl --fail http://localhost/health
systemctl is-active nginx ops-demo ops-demo1 ops-demo2
systemctl is-enabled nginx ops-demo ops-demo1 ops-demo2
sudo nginx -t
sudo ss -lntup
sudo ufw status verbose
```

也可以运行项目自带检查：

```bash
sudo ./scripts/check.sh
```

预期端口为 `127.0.0.1:8000`、`127.0.0.1:8001`、`127.0.0.1:8002`，对外只需要开放 Nginx 的 `80` 端口；远程 SSH 场景下启用 UFW 前先放行 SSH：

```bash
sudo ufw allow OpenSSH
sudo ufw allow 'Nginx HTTP'
sudo ufw enable
```

## 日志、健康检查和备份

应用日志位于 `/var/log/ops-demo/`，Nginx 日志位于 `/var/log/nginx/`。日志轮转配置为每天轮转、保留 14 份：

```bash
sudo logrotate -d /etc/logrotate.d/ops-demo
```

健康检查默认访问 `http://localhost/health`，失败时由 root 权限脚本重启三个后端：

```bash
sudo ./scripts/health-check.sh
```

备份默认写入 `/var/backups/ops-demo/`，保留 7 天：

```bash
sudo ./scripts/backup.sh
sudo ls -lh /var/backups/ops-demo
sudo tar -tzf /var/backups/ops-demo/ops-demo_日期时间.tar.gz | head -n 20
```

恢复测试应解压到临时目录，确认文件存在后再决定是否替换运行目录。不要直接覆盖正在运行的项目。

## 故障演练

建议至少记录以下演练：

```bash
# 停止一个后端并观察状态、Nginx 日志和端口
sudo systemctl stop ops-demo1
systemctl status ops-demo1 --no-pager
sudo tail -n 50 /var/log/nginx/ops-demo-error.log
sudo systemctl start ops-demo1

# 配置改动后先检查，再 reload
sudo nginx -t
sudo systemctl reload nginx

# 查看端口占用和服务日志
sudo ss -lntup
journalctl -u ops-demo1 -n 50 --no-pager
```

完整的故障现象、证据、恢复和改进记录见 [`docs/incident-review.md`](docs/incident-review.md)。

## Git 初始化与推送

确认当前目录是项目根目录，并先检查敏感文件：

```bash
pwd
git status
git check-ignore -v .env test.key backups/example.tar.gz
```

在 `C:\Users\Nahida\ops-demo` 对应的 Ubuntu 项目目录中执行：

```bash
git init
git branch -M main
git remote add origin https://github.com/Fangyuan147/test.git
git add .
git status
git commit -m "init: add Ubuntu ops demo"
git log --oneline -1
git push -u origin main
```

如果已经存在 `origin`，不要重复添加，先查看：

```bash
git remote -v
```

本项目不会提交 `.env`、私钥、证书、数据库、备份包、日志、虚拟环境和 Python 缓存。上传前重点确认 `git status` 和 `git diff --cached --stat`，不要把密码、API Key 或个人配置写入仓库。

## 后续改进

- 为 Nginx 配置 HTTPS 和域名。
- 使用 systemd timer 替代 cron，并加入失败告警。
- 增加 Prometheus/Grafana 或其他监控系统。
- 使用 Ansible、Docker 或 GitHub Actions 实现可重复交付。
- 将 Nginx、systemd、logrotate 配置纳入完整环境备份。

更多架构说明见 [`docs/architecture.md`](docs/architecture.md)。
