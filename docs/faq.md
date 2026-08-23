# 常见问题

## 软件无响应、卡顿或数据不更新？

可以尝试**重启软件**解决。如果重启后问题仍然存在，请在 [GitHub Issues](https://github.com/LinYuanovo/HGame-Manager/issues) 或 [B站](https://space.bilibili.com/345721873)私信作者，说明具体情况和复现步骤。

## 能否支持xxx站点？

一般站点不做特殊支持，请自行尝试 [添加自定义解析器](/guide/add-games#方式二-其他-acg-站点-自定义解析器)，如无法解决再去 [GitHub Issues](https://github.com/LinYuanovo/HGame-Manager/issues) 或 [B站](https://space.bilibili.com/345721873)私信作者，说明具体情况和复现步骤。

## 存档扫描失败怎么办？

存档扫描不保证 100% 成功。如果扫描失败：

1. 确认游戏已被标记为「已玩」状态，且本地确实运行过该游戏
2. 确认 `source_url.txt` 和游戏启动文件（.exe）在同一目录或者放在 `HGMDatas` 文件夹下
3. 手动填写存档路径，之后依然可以通过软件快速打开存档位置

详见 [存档管理](/guide/saves)。

## 刮削不到游戏信息？

- 检查 `source_url.txt` 中的链接是否正确、是否需要登录（Cookie 过期）
- 内置站点失效时，可尝试配置 [自定义解析器](/guide/add-games#方式二：其他-acg-站点（自定义解析器）)
- 也可以直接 [添加本地游戏](/guide/add-games#方式三：直接添加本地游戏) 后手动编辑信息

## 检查更新的结果准确吗？

检查结果仅供参考，不一定准确，请自行判断。检查期间请不要切换页面，否则可能无法收到反馈。

## 更新软件会丢失数据吗？

软件数据存储在 exe 同级的 `hgame_manager_data` 目录中，正常替换 exe 文件不会丢失数据。但建议更新前先备份数据目录。详见 [软件更新](/guide/update-app)。

## 如何上传存档到云端？

在「设置」中填写 WebDAV 配置后，即可在存档管理中使用「上传至云端」「下载」「恢复」等功能。详见 [WebDav](/guide/WebDav)。
