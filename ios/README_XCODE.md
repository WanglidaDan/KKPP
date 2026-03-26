# KKPP Xcode 工程

## 生成工程

```bash
cd /Users/wanglida/Desktop/KKPP/ios
xcodegen generate
```

生成后会得到：

- `/Users/wanglida/Desktop/KKPP/ios/KKPP.xcodeproj`

## 打开工程

```bash
open /Users/wanglida/Desktop/KKPP/ios/KKPP.xcodeproj
```

## 需要你在 Xcode 里确认的两项

1. `Signing & Capabilities` 中选择你的 Apple Team。
2. 如需真机联调，把 `Views/ContentView.swift` 里的后端地址改成你的云服务器地址。
