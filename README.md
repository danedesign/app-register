# Portable App Register

把绿色版 Windows 软件登记成接近“正常安装过”的应用：

- 在开始菜单创建快捷方式。
- 在“设置 > 应用 > 已安装的应用”里显示条目。
- 写入 `App Paths`，让部分软件可以通过运行框或系统查找定位。
- 支持用同一个清单批量登记和批量撤销。

默认只写入当前用户的注册表位置，不需要管理员权限。

## 窗口版：直接拖入 exe

双击：

```text
PortableAppRegister.bat
```

然后把绿色软件的 `.exe` 文件拖到窗口里。工具会自动：

- 先弹出命名窗口，你可以手动输入名称，也可以尝试联网查找官方名称。
- 在开始菜单的 `Portable Apps` 文件夹里创建快捷方式。
- 在 Windows “已安装的应用”里创建条目。
- 给该条目设置卸载入口，卸载时会删除本工具创建的快捷方式和登记项。

如果拖入多个 `.exe`，会一次性全部登记。

窗口下方会显示本工具登记过的软件。选中一个或多个条目后点击 `Remove selected`，会删除对应的开始菜单快捷方式、`App Paths` 和已安装应用登记项，但不会删除你的绿色软件文件。

联网查找名称使用 DuckDuckGo 的网页搜索结果做一次简单猜测。它只是辅助填名字，最终写入开始菜单前仍然可以手动修改。

命名窗口会先给出一个候选列表，再让你选择或手动输入。候选来自本地识别、exe 内部信息、文件夹名、文件名和联网搜索结果。例如 `ps2019.exe` 会优先给出 `Adobe Photoshop 2019`，`pr2020.exe` 会优先给出 `Adobe Premiere Pro 2020`，`GTA-VC.exe` 会优先给出 `Grand Theft Auto: Vice City`，`gamemd.exe` / `ra2md.exe` 会优先给出 `Command & Conquer: Yuri's Revenge`。

窗口版会把自己的记录保存到：

```text
%APPDATA%\PortableAppRegister\apps.json
```

所以如果你手动删掉开始菜单快捷方式，管理窗口仍然能知道这个软件曾经被登记过。重装系统后，如果这个 AppData 目录没有被保留，记录消失是正常的；如果你备份并恢复了这个目录，后续可以继续基于这份记录管理。

如果某个软件登记时报错，窗口会尽量刷新列表，显示已经写入成功的部分；详细错误会写到：

```text
%APPDATA%\PortableAppRegister\errors.log
```

## 使用方法

1. 复制示例清单：

   ```powershell
   Copy-Item .\apps.example.json .\apps.json
   ```

2. 编辑 `apps.json`，把 `exe` 改成你的绿色软件真实路径。

3. 预览将要做的改动：

   ```powershell
   powershell.exe -ExecutionPolicy Bypass -File .\Register-PortableApps.ps1 -Register -Manifest .\apps.json -WhatIf
   ```

4. 正式登记：

   ```powershell
   powershell.exe -ExecutionPolicy Bypass -File .\Register-PortableApps.ps1 -Register -Manifest .\apps.json
   ```

5. 查看本工具登记过的应用：

   ```powershell
   powershell.exe -ExecutionPolicy Bypass -File .\Register-PortableApps.ps1 -List
   ```

6. 撤销登记：

   ```powershell
   powershell.exe -ExecutionPolicy Bypass -File .\Register-PortableApps.ps1 -Unregister -Manifest .\apps.json
   ```

## 清单格式

```json
{
  "apps": [
    {
      "id": "my-tool",
      "name": "My Tool",
      "exe": "D:\\PortableApps\\MyTool\\MyTool.exe",
      "publisher": "My Publisher",
      "version": "1.0.0",
      "startMenuFolder": "Portable Apps",
      "arguments": ""
    }
  ]
}
```

字段说明：

- `id`：稳定唯一标识。建议手写，后续撤销和重复登记会更可靠。
- `name`：开始菜单和已安装应用里显示的名称。
- `exe`：主程序路径。
- `publisher`：发布者，可选。
- `version`：版本号，可选。
- `startMenuFolder`：开始菜单里的文件夹名，可选。
- `arguments`：快捷方式启动参数，可选。
- `icon`：图标路径，可选；不填时使用主程序图标。
- `installLocation`：安装位置，可选；不填时使用主程序所在文件夹。

## 它会写入哪里

当前用户注册表：

- `HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\<id>`
- `HKCU\Software\Microsoft\Windows\CurrentVersion\App Paths\<exe name>`

当前用户开始菜单：

- `%APPDATA%\Microsoft\Windows\Start Menu\Programs`

## 适合的场景

这个工具适合“软件本身已经在固定目录里，只是系统不知道它存在”的绿色软件。重装系统后，只要你的绿色软件目录还在，重新运行登记命令就能恢复开始菜单和已安装应用列表。

它不会复制软件文件，也不会模拟真正安装器做驱动、服务、文件关联、右键菜单、环境变量等复杂安装步骤。需要这些能力的软件，仍然应该使用官方安装包。
