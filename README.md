# Ubuntu IT 运维实战项目

这是一个面向学习和作品集展示的 Ubuntu 单机 Web 运维项目。项目在一台 Ubuntu 主机上运行三个 Flask/Gunicorn 后端，由 Nginx 统一接入并按 3:2:1 权重转发请求；同时部署完整的 Prometheus 监控告警栈（Prometheus + Node Exporter + Blackbox Exporter + Alertmanager + Grafana），实现指标采集、HTTP 存活探测、告警路由和仪表盘可视化。

项目重点不是在部署时生成网页代码，而是练习完整的服务生命周期：

~~~text
代码管理 → 部署 → 服务托管 → 反向代理 → 健康检查 → 监控告警 → 日志轮转 → 备份 → 故障恢复
~~~

> 项目定位：个人 Linux/Web 运维实践项目，适合在 Ubuntu 本机、虚拟机或云服务器上复现。它不是生产级高可用平台，不代表真实生产环境经验。

## 当前项目结构

~~~text
ops-demo/
├── apps/
│   ├── ops-demo/app.py
│   ├── ops-demo1/app.py
│   └── ops-demo2/app.py
├── config/
│   ├── nginx/
│   │   └── sites.conf                # 站点列表与公共运行参数
│   ├── prometheus/
│   │   ├── prometheus.conf           # 监控端口与目标安装路径
│   │   ├── prometheus.yml            # 抓取配置（含 HTTP 探测任务）
│   │   ├── blackbox.yml              # Blackbox Exporter 探测模块
│   │   ├── alertmanager.yml          # 告警路由与邮件配置
│   │   └── rules/
│   │       └── ops-demo.yml          # 告警规则
│   ├── grafana/
│   │   ├── dashboards/ops-demo-overview.json   # 项目总览仪表盘
│   │   └── provisioning/             # 数据源与仪表盘自动加载
│   ├── logrotate/ops-demo
│   └── cron/ops-demo-backup
├── scripts/
│   ├── install.sh                    # 系统依赖安装（需单独执行）
│   ├── deploy.sh                     # 全栈部署
│   ├── check.sh                      # 部署后全量验收
│   ├── health-check.sh               # 日常健康检查
│   ├── backup.sh                     # 备份脚本
│   └── back.sh                       # backup.sh 的别名
├── docs/
│   ├── architecture.md               # 架构说明
│   ├── project-review.md             # 项目评审报告
│   ├── incident-review.md            # 故障复盘模板与演练记录
│   ├── PROJECT_HANDOFF.md            # 项目交接文档
│   └── upgrade-roadmap.md            # 进阶路线
├── .gitattributes
├── .gitignore
├── requirements.txt
└── README.md
~~~

### 应用代码说明

项目当前保留三份独立的 app.py：

| 应用 | 端口 | 用途 |
| --- | ---: | --- |
| apps/ops-demo/app.py | 8000 | 第一个后端实例 |
| apps/ops-demo1/app.py | 8001 | 第二个后端实例 |
| apps/ops-demo2/app.py | 8002 | 第三个后端实例 |

每个应用都提供 `/` 和 `/health` 接口，并在页面和健康响应中显示自己的服务名和端口。部署脚本负责部署已有代码，不负责批量生成 app.py。

保留三份应用代码有利于当前阶段观察 Nginx 请求具体转发到了哪个后端，也便于分别验证监控探针对三个目标的探测结果。后续如果需要减少重复代码，可以再重构为一份通用 Flask 应用，通过环境变量传入服务名和端口；这不是当前部署流程的必要条件。

## 运行架构

### Web 接入

~~~text
客户端
  │
  ▼
UFW → Nginx :80
          │ upstream（权重 3:2:1）
          ├── 127.0.0.1:8000 → ops-demo
          ├── 127.0.0.1:8001 → ops-demo1
          └── 127.0.0.1:8002 → ops-demo2
~~~

三个后端只监听 127.0.0.1，不直接对外暴露。外部请求统一进入 Nginx，再由 Nginx 转发到三个后端。

权重 3:2:1 表示长期相对比例，理论上三个后端约承担 50%、33.3% 和 16.7% 的请求，不保证每六次请求严格按比例分配。

### 监控告警

~~~text
Prometheus :9090
  │  抓取 ──────────────► 自身(9090)、Node Exporter(9100)
  │  HTTP 探测(ops-demo-http)
  │    └─► Blackbox Exporter(9115) ──► 127.0.0.1:8000/8001/8002 的 /health
  │  告警规则触发 ───────► Alertmanager(9093) ──邮件──► SMTP（需自行配置）
  └─► Grafana(3000) 查询并展示（provisioning 自动加载数据源与仪表盘）
~~~

- **Node Exporter(9100)**：采集主机 CPU、内存、磁盘等指标。
- **Blackbox Exporter(9115)**：对外部 URL 做 HTTP 探测，`probe_success` 用于判断三个后端 `/health` 是否存活。
- **告警规则**（config/prometheus/rules/ops-demo.yml）：Node Exporter 掉线、HTTP 探测失败、根分区使用率 > 85%、内存使用率 > 90%。
- **Grafana(3000)**：通过 provisioning 自动加载 Prometheus 数据源和 `ops-demo-overview` 仪表盘，无需手动配置。

### 端口总览

| 组件 | 端口 | 说明 |
| --- | ---: | --- |
| Nginx | 80 | Web 统一入口 |
| ops-demo / ops-demo1 / ops-demo2 | 8000 / 8001 / 8002 | 三个后端（仅 127.0.0.1） |
| Prometheus | 9090 | 指标抓取与查询 |
| Node Exporter | 9100 | 主机指标 |
| Blackbox Exporter | 9115 | HTTP 探测 |
| Alertmanager | 9093 | 告警路由 |
| Grafana | 3000 | 可视化 |

## 目标运行布局

Ubuntu 上的目标运行布局为：

~~~text
/opt/ops-demo/
├── apps/ops-demo/app.py
├── apps/ops-demo1/app.py
├── apps/ops-demo2/app.py
├── config/
├── scripts/
├── requirements.txt
└── venv/

/etc/systemd/system/ops-demo{,1,2}.service   # 三个后端服务（deploy.sh 生成）
/etc/nginx/sites-available/ops-demo          # Nginx 站点（deploy.sh 生成）
/etc/prometheus/{prometheus.yml,blackbox.yml,alertmanager.yml,rules/ops-demo.yml}
/etc/grafana/provisioning/…                  # 数据源与仪表盘 provisioning
/etc/grafana/dashboards/ops-demo/…           # 项目总览仪表盘
/etc/cron.d/ops-demo-backup                  # 每日备份定时任务
/etc/logrotate.d/ops-demo                    # 应用日志轮转
~~~

三个服务共用一个运行用户 `opsdemo` 和一个 Python 虚拟环境 `/opt/ops-demo/venv`，通过不同的工作目录和端口运行三个应用。

## 配置说明

### 站点列表与公共参数

当前参数配置文件位于 `config/nginx/sites.conf`，站点列表格式为：

~~~bash
# 服务名 | 应用路径 | 后端端口 | Nginx 权重
SITES=(
  "ops-demo|$PROJECT_ROOT/apps/ops-demo|8000|3"
  "ops-demo1|$PROJECT_ROOT/apps/ops-demo1|8001|2"
  "ops-demo2|$PROJECT_ROOT/apps/ops-demo2|8002|1"
)
~~~

公共配置包括：

~~~bash
NGINX_PORT=80
RUN_USER="opsdemo"
PROJECT_ROOT="/opt/ops-demo"
VENV_PATH="$PROJECT_ROOT/venv"
LOG_ROOT="/var/log/ops-demo"
BACKUP_ROOT="/var/backups/ops-demo"
BACKUP_RETENTION_DAYS=7
PYTHON_BIN="/usr/bin/python3"
~~~

`deploy.sh`、`check.sh`、`health-check.sh` 和 `backup.sh` 都通过 source 加载这份配置；增加后端实例或调整权重时，先修改站点列表，其余脚本会自动跟随。

### 监控端口与目标路径

`config/prometheus/prometheus.conf` 定义监控栈端口、各配置的安装目标路径，以及邮箱网络检测参数：

~~~bash
PROMETHEUS_PORT=9090
PROMETHEUS_NODE_PORT=9100
PROMETHEUS_BLACKBOX_PORT=9115
PROMETHEUS_ALERTMANAGER=9093
GRAFANA_PORT=3000

# 邮箱网络检测用的 SMTP 服务器（host:port）。
# 留空则 check.sh 跳过邮箱网络检测；部署前请填写真实地址，例如：smtp.gmail.com:587
SMTP_HOST=""
~~~

### 告警邮件配置

`config/prometheus/alertmanager.yml` 中的 SMTP 配置是**示例占位符**（使用 IANA 保留域名 example.com），仓库里不包含任何真实邮箱或授权码。部署到自己服务器前，把以下四个值替换为你的真实配置，并且**不要把替换后的真实凭据提交到公开仓库**：

~~~yaml
global:
  smtp_smarthost: 'smtp.example.com:587'   # 替换为你的 SMTP 服务器
  smtp_from: 'alert@example.com'           # 替换为发件邮箱
  smtp_auth_username: 'alert@example.com'  # 替换为认证账号
  smtp_auth_password: 'your-app-password'  # 替换为邮箱授权码
~~~

同理，`SMTP_HOST` 留空时 `check.sh` 会打印 SKIP 并跳过邮箱网络检测；填上真实地址后才会启用检测。

## 环境准备

推荐使用 Ubuntu 22.04 或 Ubuntu 24.04，并准备一个具有 sudo 权限的普通用户。最简单的方式是执行项目自带的依赖安装脚本：

~~~bash
sudo ./scripts/install.sh
~~~

该脚本会安装 Nginx、Python3、venv、pip、curl、iproute2、logrotate、cron、UFW、Prometheus、Node/Blackbox Exporter、Alertmanager 和 Grafana（Grafana 使用官方 apt 仓库），并验证各命令版本。

也可以手动安装基础依赖作为替代：

~~~bash
sudo apt update
sudo apt install -y nginx python3 python3-venv python3-pip curl ufw logrotate cron
~~~

注意：`install.sh` 需要单独执行，`deploy.sh` 不会自动调用它；首次部署前应先完成依赖安装。UFW 的放行与启用也需要手动执行（见下文验收检查）。

项目 Python 依赖记录在 `requirements.txt` 中，当前固定 `Flask==3.0.3` 和 `gunicorn==22.0.0`。

## Windows 与 Ubuntu 的分工

Windows 用于修改源代码、脚本和配置，并提交到 Git；Ubuntu 用于拉取代码、运行服务和执行验收。

~~~text
Windows 修改代码
    ↓
git add / git commit / git push
    ↓
GitHub
    ↓
Ubuntu git pull
    ↓
执行部署和验收脚本
~~~

日志、虚拟环境、备份包、密钥和运行时文件只保留在 Ubuntu，不提交到 Git。

**行尾约定**：仓库通过 `.gitattributes` 统一为 LF 行尾。在 Windows 上编辑时请保持编辑器的行尾设置为 LF（或依赖 Git 的 eol=lf 归一化），不要把 `config/*.conf` 等被脚本 source 的文件存成 CRLF——`\r` 会混入变量值，导致 useradd、路径、端口等全部异常。

## 部署流程

在 Windows 修改完成并推送后，在 Ubuntu 项目根目录执行：

~~~bash
git pull
pwd
git status
git diff --check
~~~

先检查 Bash 语法：

~~~bash
bash -n scripts/install.sh scripts/deploy.sh scripts/check.sh scripts/health-check.sh scripts/backup.sh
~~~

确认语法检查通过后，执行：

~~~bash
chmod +x scripts/*.sh
sudo ./scripts/deploy.sh
~~~

部署脚本的完整流程是：

1. 检查 root 权限、项目根目录和 requirements.txt。
2. 创建或复用受限系统用户 `opsdemo`。
3. 将应用、配置、脚本和依赖清单复制到 `/opt/ops-demo`（脚本本身就在 `/opt/ops-demo` 时跳过自我复制）。
4. 创建或复用 `/opt/ops-demo/venv`，升级 pip 并安装 Flask/Gunicorn 依赖。
5. 根据站点列表生成三个 systemd 服务配置。
6. 根据站点列表生成 Nginx upstream 配置（权重 3:2:1）。
7. 安装 cron 定时任务和 logrotate 配置，执行 `nginx -t` 与 `systemctl daemon-reload`。
8. 启用并重启三个后端服务。
9. 安装 Prometheus / Blackbox / Alertmanager 规则与 Grafana provisioning 配置到 `/etc/`。
10. 用 `promtool check config`、`promtool check rules`、`prometheus-blackbox-exporter --config.check`、`amtool check-config` 分别校验配置。
11. 启用并重启 Prometheus、Node/Blackbox Exporter、Alertmanager、Grafana、Nginx 和 cron。
12. 等待 Grafana 就绪（最长 30 秒，失败会输出状态与日志）。
13. 自动执行 `scripts/check.sh` 收尾验收。

在真实 Ubuntu 主机上成功执行并验证前，不应把上述流程描述为已经完成的自动化部署能力。

## 验收检查

### 单独检查三个后端

~~~bash
curl --fail http://127.0.0.1:8000/health
curl --fail http://127.0.0.1:8001/health
curl --fail http://127.0.0.1:8002/health
~~~

### 检查 Nginx 统一入口

~~~bash
curl --fail http://127.0.0.1/health
curl --fail http://localhost/health
~~~

### 检查监控栈

~~~bash
curl --fail http://127.0.0.1:9090/-/ready                 # Prometheus 就绪
curl --fail http://127.0.0.1:9100/metrics | head          # Node Exporter 指标
curl --fail http://127.0.0.1:9115/metrics | head          # Blackbox Exporter 指标
curl --fail http://127.0.0.1:9093/-/healthy               # Alertmanager 健康
curl --fail http://127.0.0.1:3000/api/health              # Grafana 健康
~~~

### 检查服务、端口和 Nginx 配置

~~~bash
systemctl is-active nginx ops-demo ops-demo1 ops-demo2 prometheus
systemctl is-enabled nginx ops-demo ops-demo1 ops-demo2 prometheus
sudo nginx -t
sudo ss -lntup
sudo ufw status verbose
~~~

### 一键全量检查

~~~bash
sudo ./scripts/check.sh
~~~

`check.sh` 会依次检查：依赖命令存在性、`nginx -t`、三个后端的服务运行/开机自启/端口监听/`/health` 接口、Prometheus 就绪、`probe_success{job="ops-demo-http"}` 的 3 个探测目标全部为 1、Node/Blackbox Exporter 的 `/metrics`、Grafana 健康、邮箱网络（`SMTP_HOST` 为空时跳过），以及 Prometheus、Alertmanager、两个 Exporter、Grafana、Nginx、cron 的运行与开机自启状态。

预期后端监听地址为：

~~~text
127.0.0.1:8000
127.0.0.1:8001
127.0.0.1:8002
~~~

对外只需要开放 Nginx 的 80 端口（如需从其他电脑访问 Grafana，再放行 3000/tcp）。远程 SSH 场景下，启用 UFW 前先放行 SSH：

~~~bash
sudo ufw allow OpenSSH
sudo ufw allow 'Nginx HTTP'
sudo ufw enable
sudo ufw status numbered
~~~

## 日志、健康检查和备份

应用日志位于 `/var/log/ops-demo/`，Nginx 日志位于 `/var/log/nginx/`。

logrotate 配置位于仓库的 `config/logrotate/ops-demo`，每天轮转并保留 14 份，可在部署后验证：

~~~bash
sudo logrotate -d /etc/logrotate.d/ops-demo
~~~

日常健康检查可执行（比 check.sh 轻量，不含服务自启等全量检查）：

~~~bash
sudo ./scripts/health-check.sh
~~~

健康检查失败时会返回非 0 并输出失败组件。服务进程异常时，systemd 的 `Restart=on-failure` 负责一部分自动恢复；健康检查脚本本身不直接重启服务。

备份默认写入 `/var/backups/ops-demo/`，保留最近 7 天：

~~~bash
sudo ./scripts/backup.sh     # 或 sudo ./scripts/back.sh（别名）
sudo ls -lh /var/backups/ops-demo
~~~

备份内容包括项目中的应用、配置、脚本和依赖清单；如果系统中存在相应文件，也会收集三个 systemd 服务、cron 定时规则、Nginx 站点和 logrotate 配置。它仍然不是完整的主机灾备，不包含用户数据库、所有系统状态和外部依赖。

### cron 定时备份

项目使用 cron 在每天凌晨 02:00 自动执行备份。仓库中的定时规则位于 `config/cron/ops-demo-backup`；运行 `scripts/deploy.sh` 后，该规则会被安装到 Ubuntu 的 `/etc/cron.d/ops-demo-backup`。

~~~cron
0 2 * * * root /opt/ops-demo/scripts/backup.sh >> /var/log/ops-demo/backup-cron.log 2>&1
~~~

这条规则表示：cron 以 `root` 身份执行 `/opt/ops-demo/scripts/backup.sh`，正常输出和报错都会追加写入 `/var/log/ops-demo/backup-cron.log`。注意：`/etc/cron.d/` 中的规则比个人 `crontab -e` 多一列执行用户，因此这里的 `root` 不能省略。

部署后可在 Ubuntu 上验证：

~~~bash
sudo systemctl is-active cron
sudo cat /etc/cron.d/ops-demo-backup
sudo /opt/ops-demo/scripts/backup.sh
sudo ls -lh /var/backups/ops-demo
sudo tail -n 50 /var/log/ops-demo/backup-cron.log
~~~

手动执行成功只能证明备份脚本可运行；还需要等到下一次 02:00 后检查日志和备份文件，才能确认 cron 已实际触发。

恢复时请先解压到临时目录，确认文件完整后再决定是否替换运行目录，不要直接覆盖正在运行的项目。

## 故障演练

建议在 Ubuntu 上记录真实命令输出、现象、原因、恢复动作和恢复验证。

### 停止一个后端

~~~bash
sudo systemctl stop ops-demo1
systemctl status ops-demo1 --no-pager
sudo ss -lntup | grep ':8001'
curl -i http://localhost/health
sudo systemctl start ops-demo1
~~~

只要其他后端正常，Nginx 通常仍可以提供服务；所有后端都不可用时，统一入口可能返回 502 Bad Gateway。此时 Prometheus 的 `probe_success` 会变为 0，两分钟后触发 `OpsDemoEndpointDown` 告警（需已配置 Alertmanager 邮件）。

### 检查 Nginx 配置后再 reload

~~~bash
sudo nginx -t
sudo systemctl reload nginx
~~~

### 查看服务日志和端口占用

~~~bash
sudo ss -lntup
journalctl -u ops-demo1 -n 50 --no-pager
journalctl -u prometheus -n 50 --no-pager
sudo tail -n 50 /var/log/nginx/ops-demo-error.log
~~~

完整的故障记录模板见 docs/incident-review.md。

## Git 管理

Windows 上修改代码和配置：

~~~powershell
cd <你的本地仓库路径>
git status
git diff --check
git add -A
git commit -m "docs: update project README"
git push
~~~

Ubuntu 上拉取同一个仓库：

~~~bash
git pull
~~~

提交前检查敏感文件是否被忽略：

~~~bash
git check-ignore -v .env test.key backups/example.tar.gz
~~~

不要把密码、API Key、授权码、私钥、证书、数据库、备份包、日志、虚拟环境和 Python 缓存提交到 GitHub；`alertmanager.yml` 与 `prometheus.conf` 中的 SMTP 配置只保留示例占位符，真实凭据仅在本机配置且不提交。

## 当前限制和后续方向

当前项目可以体现：

- Ubuntu 基础服务部署
- Flask/Gunicorn 应用运行
- systemd 服务托管和开机自启
- Nginx 反向代理与权重转发
- Prometheus 指标抓取与 Blackbox HTTP 探测
- 告警规则、Alertmanager 路由与邮件配置（示例）
- Grafana provisioning 自动加载数据源与仪表盘
- cron 定时备份与 logrotate 日志轮转
- UFW 端口边界控制
- 健康检查、验收脚本和故障排查文档

仅凭仓库文件不能证明部署已经在 Ubuntu 成功运行。还需要补充真实证据：

- 三个后端和 Nginx 的健康检查输出
- Prometheus 目标抓取状态与 Grafana 仪表盘截图
- systemd、端口和 Nginx 状态输出
- 停止服务后的故障现象、告警触发和恢复记录
- 重启 Ubuntu 后的服务恢复结果
- 备份解压和恢复验证结果

后续可以按以下顺序升级：

1. 在 Ubuntu 上完成当前脚本的真实部署验证。
2. 把告警邮件替换为真实 SMTP 配置并验证告警链路。
3. 将部署、监控、健康检查和备份结果记录到项目文档。
4. 再考虑把三份重复的 app.py 重构为一份通用 Flask 应用。
5. 学习 Ansible、Docker Compose 和 GitHub Actions。

更多架构说明见 docs/architecture.md，项目问题记录见 docs/project-review.md，进阶路线见 docs/upgrade-roadmap.md。
