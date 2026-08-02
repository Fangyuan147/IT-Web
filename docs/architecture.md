# 架构说明

## 1. 目标

用一台 Ubuntu 主机练习一个 Web 服务从部署、启动、访问、日志、检查、备份到故障恢复的完整流程。三个后端使用相同的应用结构，但通过服务名和端口区分，便于观察 Nginx 的加权转发。

## 2. 请求链路

```text
客户端
  -> UFW
  -> Nginx :80
  -> upstream ops_demo_backend
  -> Gunicorn
  -> Flask /health 或 /
```

Nginx 配置中的后端权重为：

| 后端 | 地址 | 权重 | 理论比例 |
| --- | --- | ---: | ---: |
| ops-demo | 127.0.0.1:8000 | 3 | 50% |
| ops-demo1 | 127.0.0.1:8001 | 2 | 33.3% |
| ops-demo2 | 127.0.0.1:8002 | 1 | 16.7% |

实际短样本可能偏离理论比例，这是负载均衡调度和样本数量造成的正常现象。

## 3. 进程与权限

三个服务均使用 `opsdemo` 用户运行，禁止交互登录；Gunicorn 只绑定回环地址，减少后端端口直接暴露的范围。systemd 使用 `Restart=on-failure` 做基础自动恢复，并启用 `NoNewPrivileges` 和 `PrivateTmp` 两项基础限制。

## 4. 运维闭环

- 部署：`scripts/deploy.sh`
- 验收：`scripts/check.sh`
- 健康检查：`scripts/health-check.sh`
- 备份：`scripts/backup.sh`
- 日志轮转：`config/logrotate/ops-demo`
- 服务定义：`config/systemd/`
- 代理配置：`config/nginx/ops-demo.conf`

当前备份脚本主要备份项目代码、配置和脚本，不等同于整台主机灾备。若要恢复完整运行环境，还应备份 `/etc/systemd/system/`、`/etc/nginx/`、`/etc/logrotate.d/` 和实际的定时任务，并验证恢复流程。
