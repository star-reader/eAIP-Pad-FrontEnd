# Sign in with Apple 配置指南

## ⚠️ 重要提示
Sign in with Apple 需要正确的配置才能工作。请按照以下步骤完成配置。

## 📱 Xcode 配置步骤

### 1. 启用 Sign in with Apple Capability

1. 在 Xcode 中打开项目 `eAIP Pad.xcodeproj`
2. 选择左侧的项目文件（蓝色图标）
3. 在 TARGETS 列表中选择 `eAIP Pad`
4. 点击顶部的 `Signing & Capabilities` 标签
5. 点击左上角的 `+ Capability` 按钮
6. 在搜索框中输入 "Sign in with Apple"
7. 双击添加 `Sign in with Apple` 功能

✅ 添加成功后，您会在 Capabilities 列表中看到 "Sign in with Apple" 项

### 2. 配置 Bundle Identifier

1. 在 `Signing & Capabilities` 标签页
2. 找到 `Bundle Identifier` 字段
3. 确保它是唯一的，建议格式：`com.[yourname].eaip-pad`
   - 例如：`com.johndoe.eaip-pad`
   - 注意：不要使用 `com.apple.` 开头

### 3. 配置 Team（如果需要真机测试）

1. 在 `Signing & Capabilities` 标签页
2. 在 `Team` 下拉菜单中选择您的 Apple Developer Team
3. 如果没有 Team：
   - 点击 "Add an Account..."
   - 使用您的 Apple ID 登录
   - 选择个人团队即可（免费）

## 🖥️ 模拟器测试注意事项

### 模拟器限制
- ✅ 可以弹出 Sign in with Apple 面板
- ✅ 可以选择 Apple ID
- ❌ 但可能因为没有配置的 App ID 而失败

### 推荐测试方式

**方案 1：使用真机测试（推荐）**
1. 连接您的 iPhone 或 iPad
2. 在设备上登录 Apple ID（设置 > 登录 iPhone）
3. 在 Xcode 中选择您的设备运行

**方案 2：模拟器测试**
1. 打开模拟器的设置 (Settings)
2. 点击顶部登录 Apple ID
3. 使用您的测试 Apple ID 登录
4. 返回应用继续测试

## 🌐 Apple Developer 后台配置（真机必需）

如果要在真机上测试，需要在 Apple Developer 后台配置：

1. 访问 https://developer.apple.com/account
2. 登录您的 Apple Developer 账号
3. 进入 `Certificates, Identifiers & Profiles`
4. 选择 `Identifiers`
5. 找到或创建您的 App ID（与 Bundle Identifier 一致）
6. 编辑 App ID，勾选 `Sign in with Apple`
7. 保存配置

## 🔍 常见错误及解决方案

### 错误代码 1000
**错误信息**：`AuthorizationError error 1000`

**可能原因**：
1. 用户点击了取消按钮
2. 模拟器没有登录 Apple ID
3. Bundle Identifier 与 Apple Developer 后台配置不匹配
4. 没有添加 Sign in with Apple Capability

**解决方案**：
1. 确保在模拟器设置中登录了 Apple ID
2. 检查 Xcode 中是否正确添加了 `Sign in with Apple` Capability
3. 确认 Bundle Identifier 是唯一的
4. 尝试在真机上测试

### 错误代码 1001
**错误信息**：`Unknown error`

**解决方案**：
- 重启 Xcode
- 清理构建文件夹（Product > Clean Build Folder）
- 重新构建项目

## ✅ 验证配置清单

在测试前，请确认以下项目：

- [ ] 已在 Xcode 中添加 `Sign in with Apple` Capability
- [ ] Bundle Identifier 已配置且唯一
- [ ] 模拟器或真机已登录 Apple ID
- [ ] （真机）Apple Developer 后台已启用 Sign in with Apple
- [ ] 项目可以正常构建运行

## 🚀 测试步骤

1. 启动应用
2. 看到登录页面
3. 点击"使用 Apple 账号登录"按钮
4. 弹出 Sign in with Apple 面板
5. 选择 Apple ID 或点击"继续"
6. 输入密码（如需要）
7. 选择是否共享邮箱
8. 点击"继续"
9. 应用应该完成登录并进入主界面

## 📞 仍然遇到问题？

如果按照上述步骤仍然无法登录，请检查：

1. Xcode 控制台的完整错误日志
2. 确认后端 API 是否正常运行（`http://localhost:6644/`）
3. 检查网络连接
4. 查看本项目的 DEBUG 日志输出

---

**提示**：第一次配置可能需要重启 Xcode 和模拟器才能生效。

