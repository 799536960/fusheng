# 浮声本机发布流程

以后每次修改代码后，发布到本机 `/Applications/浮声.app` 必须使用固定脚本：

```bash
./script/publish_local.sh
```

不要手动执行 `ditto <新 app> /Applications/浮声.app` 来覆盖旧应用。直接合并覆盖会保留旧 bundle 中已经不存在的文件，之前出现过 `FushengTests.xctest` 和 XCTest 框架残留在正式安装包里的问题，最终导致签名校验失败，并影响辅助功能权限和全局快捷键监听。

## 默认流程

`./script/publish_local.sh` 默认会执行完整发布：

1. 使用独立 DerivedData 运行测试。
2. 使用另一个独立 DerivedData 执行普通构建。
3. 停止当前运行中的浮声。
4. 删除旧的 `/Applications/浮声.app`。
5. 复制最新构建出的 `Fusheng.app` 到 `/Applications/浮声.app`。
6. 使用 `codesign --verify --deep --strict` 校验安装后的 app。
7. 检查安装包中是否存在 `FushengTests.xctest`、`XCTest.framework` 等测试残留。
8. 启动 `/Applications/浮声.app` 并确认进程存在。

任何一步失败，脚本都会中止，不会继续打开一个不可信的安装包。

## 常用命令

完整发布并启动：

```bash
./script/publish_local.sh
```

快速发布，跳过测试：

```bash
./script/publish_local.sh --skip-tests
```

只安装和校验，不启动：

```bash
./script/publish_local.sh --no-launch
```

通过 Codex Run 按钮运行时，入口是：

```bash
./script/build_and_run.sh
```

查看运行日志：

```bash
./script/build_and_run.sh --logs
```

查看浮声子系统日志：

```bash
./script/build_and_run.sh --telemetry
```

## 发布后的人工检查

如果怀疑安装包又被污染，可以运行：

```bash
codesign --verify --deep --strict --verbose=4 /Applications/浮声.app
find /Applications/浮声.app/Contents -maxdepth 2 -type d | sort
```

正常情况下，`Contents` 下不应该出现：

- `PlugIns/FushengTests.xctest`
- `Frameworks/XCTest.framework`
- `Frameworks/XCTestCore.framework`
- 其他 XCTest 或 Testing 测试框架
