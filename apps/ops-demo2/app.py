from datetime import datetime, timezone

from flask import Flask, jsonify


SERVICE_NAME = "ops-demo2"
SERVICE_PORT = 8002
app = Flask(__name__)


@app.get("/")
def index():
    return f"""
    <html lang="zh-CN">
      <head><meta charset="UTF-8"><title>{SERVICE_NAME}</title></head>
      <body><h1>8002</h1>
      <p>当前后端：{SERVICE_NAME}，监听端口：{SERVICE_PORT}</p></body>
    </html>
    """


@app.get("/health")
def health():
    return jsonify(status="8002 ok", service=SERVICE_NAME, port=SERVICE_PORT,
                   time=datetime.now(timezone.utc).isoformat())
