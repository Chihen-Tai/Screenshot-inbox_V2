# Screenshot Inbox_V2

A lightweight macOS tool to organize, rename, and manage screenshots efficiently.

Built for users who take a large number of screenshots and need a faster way to clean, sort, and process them.

---

## 🌐 Language / 語言

* English (default)
* 中文（請見下方）

---

## Features

* Smart screenshot renaming (rule-based / AI-ready)
* Automatic organization into folders
* Batch operations (multi-select, delete, move)
* Drag-and-drop interaction (in progress)
* Clean and minimal interface
* Designed for speed and usability

---

## Preview

### Main Interface

![Main UI](./assets/main-ui.png)

### Batch Operations

![Batch Actions](./assets/batch-actions.png)

### Rename Function

![Rename](./assets/rename.png)

---

## Getting Started

### Clone the repository

```bash
git clone https://github.com/Chihen-Tai/Screenshot-inbox_V2.git
cd screenshot-inbox
```

### Install dependencies

```bash
npm install
```

### Run the application

```bash
npm run dev
```

---

## Configuration

Example configuration:

```json
{
  "watchFolders": ["~/Desktop", "~/Downloads"],
  "rename": true,
  "autoSort": true
}
```

You can configure:

* Screenshot source folders
* Rename behavior
* Output directories

---

## Project Structure

```
.
├── src/
├── assets/
├── components/
├── utils/
└── README.md
```

---

## Known Issues

* Rename does not update instantly in UI
* Original file name may not sync immediately
* Drag-and-drop behavior is unstable
* Multi-select (Cmd + A / Shift) is inconsistent

---

## Roadmap

* Fix real-time rename updates
* Improve drag-and-drop interaction
* Add right-click context menu
* Implement PDF export
* Improve UI layout and spacing
* Add compact view / thumbnail resizing

---

## Contributing

Contributions are welcome.
Please open an issue for bugs or feature requests.

---

## License

MIT License

---

# 中文說明（Chinese Version）

## 簡介

Screenshot Inbox 是一個輕量級 macOS 工具，用來快速整理、重新命名與管理截圖。

適合經常截圖但沒有時間整理的使用者。

---

## 功能

* 智慧截圖重新命名（規則 / AI）
* 自動分類至資料夾
* 批次操作（多選、刪除、移動）
* 拖曳操作（開發中）
* 簡潔直覺的介面
* 強調速度與效率

---

## 使用方式

### 下載專案

```bash
git clone hhttps://github.com/Chihen-Tai/Screenshot-inbox_V2.git
cd screenshot-inbox
```

### 安裝套件

```bash
npm install
```

### 啟動

```bash
npm run dev
```

---

## 設定

```json
{
  "watchFolders": ["~/Desktop", "~/Downloads"],
  "rename": true,
  "autoSort": true
}
```

可設定項目：

* 截圖來源資料夾
* 命名規則
* 輸出資料夾

---

## 已知問題

* 重新命名不會即時更新
* 原始檔名可能不同步
* 拖曳操作不穩定
* 多選功能（Cmd / Shift）不穩

---

## 未來規劃

* 修正 rename 即時更新問題
* 改善拖曳體驗
* 加入右鍵選單
* 支援匯出 PDF
* 優化 UI 排版
* 增加縮圖 / 緊湊模式

---

## 圖片放置方式

請建立 `assets/` 資料夾：

```
assets/
├── main-ui.png
├── batch-actions.png
├── rename.png
├── drag-drop.png
└── pdf-export.png
```

建議圖片：

1. 主畫面
2. 批次操作
3. 重新命名
4. 拖曳功能（可選）
5. PDF（未來功能）

---
