# iOS CI 接入指南（GitHub Actions → TestFlight）

这套 CI 会在 **GitHub Actions 的 macOS 机器**上自动完成：
> 拉代码 → 装 Flutter → 签名 → 打包 `.ipa` → 上传 **TestFlight**

你**不需要**再拥有一台 Mac。整个配置大约需要 **30 分钟**，主要时间花在 Apple 开发者后台准备证书。

---

## 0. 前提条件

- **Apple Developer 账号**（年费 $99/年）。免费账号无法使用 Provisioning Profile 上传 TestFlight。
- GitHub 仓库已托管你的代码（本项目当前还未推到 GitHub，需要先建仓库并推送）。

---

## 1. 修改 Bundle ID（必做！）

当前 iOS 的 Bundle ID 是占位符 `com.example.flutterApplication`，**不能**直接用于上架。

需要改成你自己的唯一 ID，例如：`com.yourcompany.bms`。

**两种改法，任选其一：**

**方法 A：用 Xcode 改（推荐，最直观）**
1. 在 Mac 上用 Xcode 打开 `ios/Runner.xcworkspace`
2. 选中 Runner → TARGETS → Runner → **Signing & Capabilities**
3. 把 Bundle Identifier 改为你的 ID，并勾选 **Automatically manage signing**，选择你的 Team

**方法 B：直接改配置文件**
- 编辑 `ios/Runner.xcodeproj/project.pbxproj`，把里面所有 `com.example.flutterApplication` 替换成你的新 ID
- 同时在 `ios/Runner/Info.plist` 的 `CFBundleDisplayName` 里确认应用显示名（当前是“小龙电动”）

改完后，在 Apple 开发者后台用**这个 Bundle ID** 完成下面的注册。

---

## 2. 在 Apple Developer 后台准备证书

登录 https://developer.apple.com → **Certificates, Identifiers & Profiles**

### 2.1 注册 App ID（Identifiers）
- 点 **+** 新建 App ID，App 类型选 **App**
- Bundle ID 填第 1 步改好的 ID（如 `com.yourcompany.bms`）
- 按需勾选能力：**Bluetooth**（你用了 BLE）、**Push Notifications**（如需要）

### 2.2 创建发布证书（Certificates）
1. 本地生成密钥：钥匙串访问 → 证书助理 → 从证书颁发机构请求证书
2. 在开发者后台 Certificates 点 **+** → 选 **App Store and Ad Hoc** → 上传上面的 `.certSigningRequest`
3. 下载生成的 `.cer`，双击导入钥匙串

### 2.3 导出 .p12（私钥必须一起导出！）
1. 钥匙串访问 → 找到刚才导入的证书，右键 → **导出**
2. 选 `.p12` 格式，**设置一个密码**（这个密码就是 `CERTIFICATE_PASSWORD`）

### 2.4 创建发布 Provisioning Profile
1. Profiles 点 **+** → 选 **App Store Connect** → 选刚注册的 App ID
2. 勾选你的发布证书 → 生成并下载 `.mobileprovision`

---

## 3. 创建 App Store Connect API Key

这个 Key 用于 **CI 无账号登录直接上传 TestFlight**：

1. 进入 https://appstoreconnect.apple.com → 右上角头像 → **Users and Access** → **Integrations** → **App Store Connect API**
2. 点 **+** 生成 Key，权限勾 **App Manager**（或更高）
3. 记下 **Key ID**（形如 `A1B2C3D4E5`）和 **Issuer ID**（一长串 UUID）
4. **只下载一次** 的 `.p8` 文件，保存好

---

## 4. 把凭据存进 GitHub Secrets

在 GitHub 仓库 → **Settings → Secrets and variables → Actions → New repository secret**，逐个添加：

| Secret 名称 | 内容 | 示例 |
|---|---|---|
| `CERTIFICATE_P12_BASE64` | .p12 文件的 base64 | `MIIJ...` |
| `CERTIFICATE_PASSWORD` | .p12 导出时设置的密码 | `abc123` |
| `PROVISIONING_PROFILE_BASE64` | .mobileprovision 文件的 base64 | `MIIK...` |
| `TEAM_ID` | 开发者团队 ID（10 位） | `ABCDE12345` |
| `APPSTORE_API_KEY_ID` | API Key ID | `A1B2C3D4E5` |
| `APPSTORE_API_ISSUER_ID` | API Issuer ID（UUID） | `2f9b...-...` |
| `APPSTORE_API_KEY_FILE_BASE64` | .p8 私钥文件的 base64 | `MIGE...` |

> **Windows 下生成 base64 的方法：**
> ```bash
> certutil -encode <文件> tmp.b64   # 然后删掉首尾的 -----BEGIN CERTIFICATE----- 等注释行
> # 或直接：
> powershell -Command "[Convert]::ToBase64String([IO.File]::ReadAllBytes('文件路径'))"
> ```
> 把输出整串复制到 Secret 里即可（不要带换行）。

还要把 `ios/ExportOptions.plist` 里的 `YOUR_TEAM_ID` **换成你的真实 Team ID**。

---

## 5. 触发打包

推到 GitHub 后：

- **手动触发**：仓库 **Actions** 页面 → 左侧选 **iOS Release** → 右侧 **Run workflow** 按钮
- **自动触发**：推送以 `v` 开头的 tag，例如：
  ```bash
  git tag v1.0.1
  git push origin v1.0.1
  ```

构建产物（`.ipa`）可在每次运行的 **Artifacts** 里下载。

---

## 6. 常见问题

| 问题 | 原因 / 解决办法 |
|---|---|
| `The selected provisioning profile is missing` | Profile 的 Bundle ID 或证书不匹配，重新生成 profile 并更新 Secret |
| `The request couldn't be completed because a CFBundleIdentifier already exists...` | 上传了**重复的构建号**。`flutter build ipa` 用的是 `pubspec.yaml` 的 `version: 1.0.0+1`。每次上传前**上调 `+1`**（或脚本里自动递增） |
| `altool: Error: This app ... is not in the ... account` | API Key 权限不足，需 **App Manager** 角色；或 Team ID 不对 |
| `No profiles for 'com.xxx' were found` | App ID 没注册，或 Bundle ID 还没改（第 1 步） |
| 相机扫码在真机闪退/无权限 | `Info.plist` 缺少 `NSCameraUsageDescription`，需要补上（见下） |

### 建议一并处理：相机权限声明

你的 App 用到了 `mobile_scanner`（扫码），但 `ios/Runner/Info.plist` **没有** `NSCameraUsageDescription`，真机上调用相机会被系统拒绝甚至闪退。建议在 `Info.plist` 的 `<dict>` 里加上：

```xml
<key>NSCameraUsageDescription</key>
<string>用于扫描电池二维码信息</string>
```

---

## 7. 版本号与文件清单

**每次发版前记得**：
1. `pubspec.yaml` 里递增版本：`version: 1.0.1+2`（`+` 后面是构建号，TestFlight 要求每次上传递增）
2. iOS 的 `CFBundleShortVersionString` / `CFBundleVersion` 会自动读取这个值，无需手动改

**本次接入新增的文件**：
- `.github/workflows/ios.yml` — CI 工作流
- `ios/ExportOptions.plist` — 导出配置（需填你的 Team ID）
- 本指南 `docs/ios-ci-接入指南.md`
