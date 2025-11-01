# StoreKit 配置文件设置指南

## 问题说明
虽然 StoreKit 配置文件 `eAIP Pad.storekit` 已经存在并包含了订阅产品配置，但需要在 Xcode 的 Scheme 中正确关联才能使用。

## 配置步骤

### 方法 1: 在 Xcode Scheme 中配置（推荐）

1. **打开 Scheme 设置**
   - 在 Xcode 中，点击顶部工具栏中的 Scheme 选择器（通常在运行/停止按钮旁边）
   - 选择 "Edit Scheme..."

2. **配置 StoreKit 配置**
   - 在左侧选择 "Run"（运行）
   - 点击 "Options"（选项）标签
   - 找到 "StoreKit Configuration"（StoreKit 配置）部分
   - 在下拉菜单中选择 `eAIP Pad.storekit`

3. **保存设置**
   - 点击 "Close" 关闭对话框
   - 重新运行应用

### 方法 2: 在项目设置中配置（如果方法1不可用）

1. **选择 Scheme**
   - 在 Xcode 中，点击 Scheme 选择器
   - 选择 "Manage Schemes..."

2. **编辑 Scheme**
   - 选择你的 "eAIP Pad" scheme
   - 点击 "Edit..."

3. **设置 StoreKit 配置**
   - 在左侧选择 "Run"
   - 切换到 "Options" 标签
   - 在 "StoreKit Configuration" 中选择 `eAIP Pad.storekit`

### 验证配置

配置完成后，运行应用并检查控制台输出。你应该看到：

```
✅ 成功加载产品: eAIP Pad 月度订阅 - ¥19.99
   产品ID: com.usagijin.eaip.monthly
   产品类型: autoRenewableSubscription
```

而不是：

```
⚠️ 未找到产品: com.usagijin.eaip.monthly
```

## 当前配置的产品

根据 `eAIP Pad.storekit` 文件，已配置的产品：

- **产品ID**: `com.usagijin.eaip.monthly`
- **产品名称**: eAIP Pad 月度订阅
- **价格**: ¥19.99
- **订阅周期**: 月度 (P1M)
- **试用期**: 1个月免费试用
- **订阅组**: eAIP Pad 订阅

## 注意事项

1. **仅用于开发测试**
   - StoreKit 配置文件仅用于 Xcode 开发和测试
   - 生产环境需要使用 App Store Connect 中配置的真实产品

2. **真机测试**
   - 如果在真机上测试，也需要在 Scheme 中配置 StoreKit 配置文件
   - 确保使用沙盒测试账号

3. **App Store Connect**
   - 如果需要在生产环境中使用，必须在 App Store Connect 中创建对应的订阅产品
   - 产品ID必须与配置文件中的ID一致

## 故障排除

如果配置后仍然无法加载产品：

1. **检查配置文件位置**
   - 确保 `eAIP Pad.storekit` 文件在项目根目录
   - 在 Xcode 中，文件应该显示在项目导航器中

2. **重启 Xcode**
   - 有时需要重启 Xcode 才能生效

3. **清理构建**
   - Product → Clean Build Folder (⇧⌘K)
   - 然后重新运行

4. **检查产品ID**
   - 确保代码中的产品ID与配置文件中的ID完全一致
   - 当前代码使用: `com.usagijin.eaip.monthly`

