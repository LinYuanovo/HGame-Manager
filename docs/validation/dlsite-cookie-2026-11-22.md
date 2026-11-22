# DLsite 登录态接入验证

## 行为

- 设置入口：设置 → 刮削 → Cookie 设置 → DLsite，配置键为 `cookie_dlsite`。
- 保存后下一次 DLsite 搜索、作品页及补全 API 请求读取最新 Cookie；未填写时保留年龄确认和语言默认值。
- 五种刮削入口的 DLsite 详情获取均经过 `DlsiteService.fetchById`。单个添加及 URL 三入口、批量确认的图片保存共用 `ScrapeApplyService` 和 `ConcurrentImageDownloader`。
- 官方 HTTPS 图片域名 `dlsite.com`、`dlsite.jp` 及其子域携带 Cookie，来源页继续作为 Referer；外部图片不接收 DLsite 凭据。
- 刮削结果确认表单的图片预览、图片管理的 URL 添加也采用相同的凭据范围。
- 登录状态依据实际响应判断。服务器仍返回受限页时，继续补全公开资料并保留受限提示。

## 验证结果

1. 修复前运行新增的作品页登录态测试，实际请求仅有固定 Cookie，未包含已保存的会话值，测试失败。
2. `flutter test --no-pub --concurrency=1 test/core/services/dlsite_service_test.dart test/proxy_client_headers_test.dart test/dlsite_parser_test.dart --reporter expanded`：55 项通过。覆盖持久化后读取、登录正文、搜索重试、更新及清空 Cookie、失效会话、API 及图片域名范围。
3. `flutter test --no-pub --concurrency=1 test/core/services/dlsite_image_cookie_test.dart --reporter expanded`：2 项通过。保留真实 HTTP 下载流程，将目的地映射至本机服务器；服务器确认两条官方图片请求携带 Cookie，外部图片请求不携带，三张图片均成功写入。共享下载路径及 DLsite 服务下载路径均验证。
4. `flutter test --no-pub integration_test/dlsite_cookie_settings_windows_test.dart -d windows --reporter expanded`：2 项通过。Windows 原生应用中验证浅色、深色设置页的读取、取消、保存、重开、清空及落盘，保存后服务立即读取新值。
5. 对六个修改的生产代码文件和四个相关测试文件分两组运行 `flutter analyze --no-pub`：无 error、warning；核心文件组存在 35 条既有代码区域的 info 提示，分析命令因此返回 1；图片管理及确认表单组无诊断。
6. `git diff --check` 通过。

## 范围

测试使用隔离的临时设置、模拟站点响应及本机图片服务器。没有使用真实 DLsite 账号验证线上会话是否有效；真实账号可见内容仍取决于其 Cookie 有效性和站点权限。
