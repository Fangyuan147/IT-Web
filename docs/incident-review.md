# 故障复盘模板与演练记录

本文用于记录每次故障演练的现象、证据、判断、恢复和改进。学习项目不只要“修好”，还要能说明为什么这样判断。

## 演练一：后端服务停止

### 操作

```bash
sudo systemctl stop ops-demo1
curl -i http://localhost/health
systemctl status ops-demo1 --no-pager
journalctl -u ops-demo1 -n 50 --no-pager
sudo ss -lntup | grep ':8001'
```

### 预期判断

8001 后端停止后，该 upstream 节点不可用。只要另外两个后端正常，Nginx 仍可能继续提供服务；所有后端都不可用时，入口会返回 `502 Bad Gateway`。

### 恢复

```bash
sudo systemctl start ops-demo1
curl --fail http://127.0.0.1:8001/health
curl --fail http://localhost/health
```

## 演练二：Nginx 配置错误

先备份配置，再制造一个可控的语法错误：

```bash
sudo cp -a /etc/nginx/sites-available/ops-demo /tmp/ops-demo.conf.bak
sudo nginx -t
```

修复后必须再次执行 `nginx -t`，确认成功后才 reload：

```bash
sudo nginx -t
sudo systemctl reload nginx
```

## 演练三：端口冲突

```bash
sudo ss -lntup | grep -E ':8000|:8001|:8002'
sudo lsof -i :8000 -i :8001 -i :8002
journalctl -u ops-demo -n 50 --no-pager
```

重点判断：监听端口是否被其他进程占用、systemd 的 `ExecStart` 是否使用了正确端口，以及应用是否仍在运行。

## 复盘记录

每次演练后补充：

| 项目 | 内容 |
| --- | --- |
| 发生时间 | YYYY-MM-DD HH:MM |
| 故障现象 | HTTP 状态、页面表现、服务状态 |
| 关键证据 | `systemctl`、`ss`、Nginx 日志、应用日志 |
| 根因 | 哪个组件、哪个配置或哪个资源导致 |
| 恢复动作 | 执行的命令和顺序 |
| 恢复验证 | 健康接口、端口、服务状态 |
| 后续改进 | 告警、权限、脚本或文档改进 |
