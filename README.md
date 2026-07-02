# Work Report Skill 开源模板

这是一个用于自动填写网页报工表单的 Codex Skill 模板。它通过 OpenCLI 控制浏览器，优先使用快速脚本直接填写页面控件，并同步底层数据模型，避免每次都手动点击多个查找弹窗。

这个版本已经脱敏：仓库里不应该包含真实内网地址、项目名称、客户名称、人员姓名、员工编号、项目编号、GUID 或 Cookie/Token。真实环境参数请放在本地配置文件 `report-config.local.json` 中。

## 目录说明

| 文件 | 作用 |
|------|------|
| `SKILL.md` | Codex Skill 说明和执行策略。 |
| `fast_work_report.ps1` | 主执行脚本，读取本地配置并执行新增、保存、验证。 |
| `fast_work_report.js` | Node 包装入口，实际调用 PowerShell 脚本。 |
| `gs_report_tiny.js` | 浏览器端最小实验辅助函数。 |
| `report-config.example.json` | 配置模板，只放占位符。 |
| `report-config.local.json` | 你的真实配置文件，需要自己创建，不要提交。 |
| `.gitignore` | 默认忽略 `report-config.local.json` 和 `*.local.json`。 |

## 使用前准备

1. 安装并连接 OpenCLI。
2. 确认浏览器扩展已连接，可以执行：

```powershell
opencli doctor
```

3. 复制配置模板：

```powershell
Copy-Item .\report-config.example.json .\report-config.local.json
```

4. 打开 `report-config.local.json`，按你的系统实际情况修改参数。

## 运行方式

推荐直接运行 PowerShell 脚本：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\fast_work_report.ps1 -Date 2026-07-04 -Content "需求方案梳理与问题跟进"
```

也可以通过 Node 包装入口运行：

```powershell
node .\fast_work_report.js -Date 2026-07-04 -Content "需求方案梳理与问题跟进"
```

如果不传 `-Content`，脚本会使用 `report-config.local.json` 里的 `defaults.content`。

## 需要修改哪些参数

所有环境相关参数都在 `report-config.local.json` 中。通常需要改下面这些部分。

### 1. 基础连接参数

```json
{
  "targetUrl": "https://example.internal/work-report/main",
  "opencliSession": "tape"
}
```

- `targetUrl`：报工系统页面地址。改成你自己的报工入口 URL。
- `opencliSession`：OpenCLI 浏览器会话名。默认通常是 `tape`，如果你绑定了别的 session，需要同步修改。

### 2. 默认报工内容

```json
"defaults": {
  "hours": 8,
  "content": "Work item follow-up"
}
```

- `hours`：默认工时。
- `content`：不传 `-Content` 时使用的默认工作内容。

### 3. iframe 和菜单 ID

```json
"frameIds": {
  "home": "HOME_IFRAME_ID",
  "worklog": "WORKLOG_IFRAME_ID"
},
"selectors": {
  "worklogMenuId": "WORKLOG_MENU_ID"
}
```

- `frameIds.home`：首页 iframe 的 DOM ID。
- `frameIds.worklog`：报工页面 iframe 的 DOM ID。
- `selectors.worklogMenuId`：左侧或首页中“我的报工/工作日志”菜单的 DOM ID。

这些值通常需要在浏览器开发者工具里查看页面 DOM，或者用 OpenCLI eval 探测。

### 4. 表单控件 ID

```json
"selectors": {
  "newButtonId": "NEW_BUTTON_DOM_ID",
  "formRootId": "FORM_ROOT_ID",
  "dateInputId": "WORK_DATE_INPUT_ID",
  "hiddenDateInputId": "WORK_DATE_HIDDEN_INPUT_ID",
  "hoursInputId": "WORK_HOURS_INPUT_ID",
  "contentInputId": "WORK_CONTENT_TEXTAREA_ID",
  "managerInputId": "MANAGER_TEXT_INPUT_ID",
  "saveAndCloseText": "Save and Close"
}
```

- `newButtonId`：新增按钮 DOM ID。
- `formRootId`：表单根节点 ID，用于获取页面的 `viewInstance`。
- `dateInputId`：可见日期输入框 ID。
- `hiddenDateInputId`：隐藏日期字段 ID。有些系统必须同时写可见和隐藏日期。
- `hoursInputId`：工时输入框 ID。脚本默认按 EasyUI `numberbox` 处理。
- `contentInputId`：工作内容文本框 ID。
- `managerInputId`：项目经理/负责人显示字段 ID，可为空或按实际系统修改。
- `saveAndCloseText`：保存并关闭按钮的显示文本，比如中文系统里可能是 `保存并关闭`。

### 5. lookup 显示字段

```json
"lookups": {
  "project": {
    "controlId": "PROJECT_LOOKUP_ID",
    "value": "PROJECT_VALUE_OR_CODE",
    "text": "Project display name"
  }
}
```

每个 lookup 都有三类值：

- `controlId`：页面 lookup 控件 DOM ID。
- `value`：系统内部值，可能是编号、GUID 或主键。
- `text`：页面上展示给用户看的名称。

模板里包含这些 lookup：

- `project`：项目名称。
- `customer`：客户。
- `stage`：作业环节/项目工作。
- `category`：活动类别。
- `product`：产品。

你的系统如果没有某些字段，可以删掉对应项，但脚本逻辑也要同步调整。

### 6. 底层模型字段

```json
"model": {
  "managerName": "Manager display name",
  "fields": {
    "Project": "PROJECT_MODEL_ID",
    "Project_Code": "PROJECT_CODE",
    "Project_Name": "Project display name"
  }
}
```

这是最关键的一段。很多企业系统保存时校验的不是 DOM 输入框，而是底层模型，例如 Knockout 的 `currentItem`。因此只调用：

```javascript
lookupbox('setValue', value)
lookupbox('setText', text)
```

可能不够，还必须同步模型字段。

常见必填模型字段包括：

- `Project` / `Project_Code` / `Project_Name`
- `Customer` / `Customer_Name`
- `ProjectStageRecord` / `ProjectStage` / `ProjectStage_Name`
- `ProjectStageRecord_Owner` / `ProjectStage_Owner_Name`
- `Category` / `Category_Code` / `Category_Name`
- `Product` / `Product_Name`

不同系统字段名可能不同。你需要结合页面源码、开发者工具或保存前校验逻辑调整。

### 7. 验证参数

```json
"verification": {
  "recordCountSelector": ".pagination-info"
}
```

- `recordCountSelector`：列表分页/记录数元素选择器。保存后脚本会读取它，并检查目标日期和内容是否出现在列表中。

## 如何定位参数

可以用浏览器开发者工具，也可以用 OpenCLI eval。示例：

```powershell
opencli browser tape eval "document.title"
```

查看某个 iframe：

```powershell
opencli browser tape eval "Array.from(document.querySelectorAll('iframe')).map(f => ({id:f.id, src:f.src}))"
```

查看当前报工 iframe 里的按钮文本：

```powershell
opencli browser tape eval "(() => { const f=document.getElementById('WORKLOG_IFRAME_ID'); const d=f.contentDocument; return Array.from(d.querySelectorAll('a.l-btn')).map(a=>a.textContent.trim()).join('|'); })()"
```

查看 lookup 控件和隐藏值：

```powershell
opencli browser tape eval "(() => { const f=document.getElementById('WORKLOG_IFRAME_ID'); const d=f.contentDocument; return Array.from(d.querySelectorAll('input')).map((e,i)=>({i,id:e.id,cls:e.className,value:e.value})); })()"
```

## 安全注意事项

不要提交这些内容：

- `report-config.local.json`
- 内网 URL
- 客户名称
- 项目名称
- 人员姓名
- 员工编号
- 项目编号
- 业务 GUID / 主键
- Cookie、Token、Authorization、Bearer 等凭据

提交前建议扫描：

```powershell
rg -n "(token|cookie|secret|password|Authorization|Bearer|你的公司名|你的客户名|你的项目编号|[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})" .
```

## 常见问题

### 页面上显示有值，但保存仍提示必填

优先检查 `model.fields` 是否同步了底层模型字段。很多系统保存时读的是模型，不是输入框。

### 日期保存成了当天，而不是指定日期

检查是否同时设置了 `dateInputId` 和 `hiddenDateInputId`。

### 工时还是默认值

检查页面是否使用 EasyUI `numberbox`。如果不是，需要改 `fast_work_report.ps1` 中设置工时的逻辑。

### 保存后列表没变化

检查：

- `saveAndCloseText` 是否和按钮文本完全一致。
- `recordCountSelector` 是否正确。
- 目标日期和内容是否能在列表文本中被搜索到。
- 页面是否弹出了校验提示但脚本没有捕获。
