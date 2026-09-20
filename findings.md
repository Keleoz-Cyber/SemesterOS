# 部署检查记录

- SSH可用，Ubuntu 24.04，4核，约3.7GB内存，2GB swap，系统盘可用26GB。
- Docker Compose已安装。现有博客项目在/opt/keleoz-continuum，应用仅监听127.0.0.1:8080。
- Nginx负责80/443，keleoz.com及www.keleoz.com已有有效证书；拟增加独立路径，不修改博客根路由。
- 学期OS本机API监听127.0.0.1:8871；现有APK默认10.0.2.2:8871，Flutter引擎仅x86_64，不适用于普通ARM手机。
- 后端已有Dockerfile与开发Compose，但尚缺云端重启策略、独立worker和预置OCR模型。
- 本地已有SenseVoice int8与RapidOCR ONNX模型，可校验后传至服务器，避免首次请求下载。
- 现有博客域名经过EdgeOne，Nginx已有客户端IP解析；学期OS转发必须重写X-Forwarded-For并对响应设置private/no-store，防止跨用户缓存。
- API、worker及数据库实际空闲内存约155MB、605MB、44MB；原博客保持运行。已实测云端OCR/ASR和AI，不仅是健康检查。
- 云端数据库没有迁移私人数据；只包含验证时创建的隔离合成账号，新账号学期为空。
