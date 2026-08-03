# Ubuntu IT 运维实战项目

这是一个面向学习和作品集展示的 Ubuntu 单机 Web 运维项目。项目在一台 Ubuntu 主机上运行三个 Flask/Gunicorn 后端，由 Nginx 统一接入，并通过 3:2:1 权重转发请求。

项目重点不是在部署时生成网页代码，而是练习完整的服务生命周期：

~~~text
代码管理 → 部署 → 服务托管 → 反向代理 → 健康检查 → 日志轮转 → 备份 → 故障恢复
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
│   ├── logrotate/ops-demo
│   └── nginx/sites.conf
├── scripts/
│   ├── backup.sh
│   ├── back.sh
│   ├── check.sh
│   ├── deploy.sh
│   └── health-check.sh
├── docs/
│   ├── architecture.md
│   ├── incident-review.md
│   └── project-review.md
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

每个应用都提供 / 和 /health 接口，并在页面和健康响应中显示自己的服务名和端口。部署脚本负责部署已有代码，不负责批量生成 app.py。

保留三份应用代码有利于当前阶段观察 Nginx 请求具体转发到了哪个后端。后续如果需要减少重复代码，可以再重构为一份通用 Flask 应用，通过环境变量传入服务名和端口；这不是当前部署流程的必要条件。

## 运行架构

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
~~~

三个服务共用一个运行用户 opsdemo 和一个 Python 虚拟环境 /opt/ops-demo/venv，通过不同的工作目录和端口运行三个应用。

## 配置说明

当前参数配置文件位于：

~~~text
config/nginx/sites.conf
~~~

站点列表格式为：

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
~~~

增加后端实例或调整权重时，应先修改站点列表，再检查部署脚本、健康检查脚本和文档是否使用同一个配置路径。

## 当前已知注意事项

当前仓库中的 deploy.sh、health-check.sh、check.sh 和 backup.sh 加载的是：

~~~bash
config/sites.conf
~~~

但当前仓库实际存在的参数文件是：

~~~text
config/nginx/sites.conf
~~~

因此，在统一配置路径之前，不要直接在 Ubuntu 上执行 sudo ./scripts/deploy.sh。此外，部署脚本使用的 LOG_ROOT、BACKUP_ROOT、PYTHON_BIN 和 GUNICORN_VERSION 也应在实际加载的配置文件中定义。

这属于当前项目的待修复项，不能把部署脚本描述为已经完成真实验证的一键部署。

## 环境准备

推荐使用 Ubuntu 22.04 或 Ubuntu 24.04，并准备一个具有 sudo 权限的普通用户。

~~~bash
sudo apt update
sudo apt install -y nginx python3 python3-venv python3-pip curl ufw logrotate
~~~

项目 Python 依赖记录在 requirements.txt 中，包括 Flask 和 Gunicorn 的版本范围。

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
bash -n scripts/deploy.sh scripts/health-check.sh scripts/check.sh scripts/backup.sh
~~~

确认配置路径和脚本中的 source 路径一致后，再执行：

~~~bash
chmod +x scripts/*.sh
sudo ./scripts/deploy.sh
~~~

部署脚本的目标流程是：

1. 检查 root 权限和必要命令。
2. 创建或复用受限系统用户 opsdemo。
3. 将应用、配置、脚本和依赖清单复制到 /opt/ops-demo。
4. 创建或复用 /opt/ops-demo/venv。
5. 安装 Flask 和 Gunicorn 依赖。
6. 根据站点列表生成三个 systemd 服务配置。
7. 根据站点列表生成 Nginx upstream 配置。
8. 安装 logrotate 配置。
9. 执行 nginx -t。
10. 执行 systemctl daemon-reload，启用并重启三个后端服务。
11. 启用并重启 Nginx。
12. 执行健康检查。

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

### 检查服务、端口和 Nginx 配置

~~~bash
systemctl is-active nginx ops-demo ops-demo1 ops-demo2
systemctl is-enabled nginx ops-demo ops-demo1 ops-demo2
sudo nginx -t
sudo ss -lntup
sudo ufw status verbose
~~~

也可以执行项目检查脚本：

~~~bash
sudo ./scripts/check.sh
~~~

预期后端监听地址为：

~~~text
127.0.0.1:8000
127.0.0.1:8001
127.0.0.1:8002
~~~

对外只需要开放 Nginx 的 80 端口。远程 SSH 场景下，启用 UFW 前先放行 SSH：

~~~bash
sudo ufw allow OpenSSH
sudo ufw allow 'Nginx HTTP'
sudo ufw enable
~~~

## 日志、健康检查和备份

应用日志位于：

~~~text
/var/log/ops-demo/
~~~

Nginx 日志位于：

~~~text
/var/log/nginx/
~~~

logrotate 配置文件位于仓库的 config/logrotate/ops-demo，预期为每天轮转并保留 14 份：

~~~bash
sudo logrotate -d /etc/logrotate.d/ops-demo
~~~

健康检查会检查 Nginx、三个 systemd 服务和三个后端的 /health 接口，并为 HTTP 请求设置连接和总超时：

~~~bash
sudo ./scripts/health-check.sh
~~~

健康检查失败时会返回非 0 并输出失败组件。服务进程异常时，systemd 的 Restart=on-failure 负责一部分自动恢复；健康检查脚本本身不直接重启全部服务。

备份默认写入：

~~~text
/var/backups/ops-demo/
~~~

执行备份：

~~~bash
sudo ./scripts/backup.sh
sudo ls -lh /var/backups/ops-demo
~~~

备份主要包括项目中的应用、配置、脚本和依赖清单；如果系统中存在相应文件，也会收集三个 systemd 服务、Nginx 站点和 logrotate 配置。它仍然不是完整的主机灾备，不包含用户数据库、所有系统状态和外部依赖。

恢复测试应先解压到临时目录，确认文件完整后再决定是否替换运行目录，不要直接覆盖正在运行的项目。

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

只要其他后端正常，Nginx 通常仍可以提供服务；所有后端都不可用时，统一入口可能返回 502 Bad Gateway。

### 检查 Nginx 配置后再 reload

~~~bash
sudo nginx -t
sudo systemctl reload nginx
~~~

### 查看服务日志和端口占用

~~~bash
sudo ss -lntup
journalctl -u ops-demo1 -n 50 --no-pager
sudo tail -n 50 /var/log/nginx/ops-demo-error.log
~~~

完整的故障记录模板见 docs/incident-review.md。

## Git 管理

Windows 上修改代码和配置：

~~~powershell
cd C:\\Users\\Nahida\\ops-demo
git status
git diff --check
git add .
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

不要把密码、API Key、私钥、证书、数据库、备份包、日志、虚拟环境和 Python 缓存提交到 GitHub。

## 当前限制和后续方向

当前项目可以体现：

- Ubuntu 基础服务部署
- Flask/Gunicorn 应用运行
- systemd 服务托管和开机自启
- Nginx 反向代理与权重转发
- UFW 端口边界控制
- 日志轮转、健康检查和项目文件备份
- 基础故障排查和运维文档编写

仅凭仓库文件不能证明部署已经在 Ubuntu 成功运行。还需要补充真实证据：

- 三个后端和 Nginx 的健康检查输出
- systemd、端口和 Nginx 状态输出
- 停止服务后的故障现象和恢复记录
- 重启 Ubuntu 后的服务恢复结果
- 备份解压和恢复验证结果

后续可以按以下顺序升级：

1. 在 Ubuntu 上完成当前脚本的真实部署验证。
2. 修复脚本与 config/nginx/sites.conf 的路径一致性。
3. 将部署、健康检查和备份结果记录到项目文档。
4. 再考虑把三份重复的 app.py 重构为一份通用 Flask 应用。
5. 学习 Ansible、Docker Compose 和 GitHub Actions。

更多架构说明见 docs/architecture.md，项目问题记录见 docs/project-review.md。
