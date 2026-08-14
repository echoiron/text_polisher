#Requires AutoHotkey v2.0
#SingleInstance Force
SendMode "Input"
SetWorkingDir A_ScriptDir

; Alt+Shift+1：使用 OpenAI 兼容接口润色选中文本
; 推荐将 API Key 放在 Windows 用户环境变量中，脚本内不要写真实密钥
; 运行前可按需设置以下供应商环境变量：
;   setx DEEPSEEK_API_KEY "sk-..."
;   setx DASHSCOPE_API_KEY "sk-..."
;   setx OPENCODE_API_KEY "sk-..."   ; OpenCode Go 订阅后从 https://opencode.ai/auth 获取 API 密钥
;
; 供应商选择：
;   DEFAULT_PROVIDER 可直接在脚本中修改默认供应商
;   setx AI_TEXT_PROVIDER "deepseek"  ; 环境变量优先级最高
;   setx AI_TEXT_PROVIDER "dashscope"
;   setx AI_TEXT_PROVIDER "qwen"
;   setx AI_TEXT_PROVIDER "opencode"
;   setx AI_TEXT_PROVIDER "opencode_luna"
;
; 供应商默认配置：
;   deepseek  -> https://api.deepseek.com/chat/completions, model deepseek-v4-flash
;   dashscope -> https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions, model deepseek-v4-flash-0731
;   opencode       -> https://opencode.ai/zen/go/v1/chat/completions, model deepseek-v4-flash (OpenCode Go 订阅服务)
;   opencode_luna  -> https://opencode.ai/zen/go/v1/responses, model gpt-5.6-luna (Responses API)
;
; OPENAI_COMPAT_API_URL 和 OPENAI_COMPAT_MODEL 可覆盖供应商默认配置
; 可选：setx AI_TEXT_ENABLE_THINKING "true" 会添加供应商专属 thinking 字段；脚本刻意不启用流式返回
; 可选代理，默认使用本地手动代理 http://127.0.0.1:1080：
;   setx AI_TEXT_PROXY_MODE "system"  ; 使用 WinHTTP 系统代理
;   setx AI_TEXT_PROXY_MODE "manual"  ; 使用手动代理，并配合 AI_TEXT_PROXY_SERVER
;   setx AI_TEXT_PROXY_SERVER "http://127.0.0.1:7890"
;   setx AI_TEXT_PROXY_MODE "direct"  ; 强制直连
; Alt+Shift+2：翻译选中文本。默认自动判断目标语言：中文译为英文，其他语言译为简体中文
; 可用 setx AI_TEXT_TRANSLATE_TARGET "english" 固定目标语言（取值 auto/en/zh，或直接写目标语言名）
DEFAULT_PROVIDER := "opencode_luna"
DEFAULT_PROXY_MODE := "manual"
DEFAULT_PROXY_SERVER := "http://127.0.0.1:1080"
; 供应商优先级：环境变量 > 脚本默认值
PROVIDER := GetConfiguredProvider()
API_KEY := GetProviderApiKey(PROVIDER)
API_URL := GetProviderApiUrl(PROVIDER)
MODEL := GetProviderModel(PROVIDER)
WINDOWS_TERMINAL_MODE := "auto"
statusGui := ""
statusDotsCtrl := ""
statusTextCtrl := ""
statusDotsFrame := 0

GetConfiguredProvider() {
    global DEFAULT_PROVIDER

    ; 环境变量用于临时或长期覆盖脚本默认值，适合不改脚本就切换模型供应商
    envProvider := EnvGet("AI_TEXT_PROVIDER")
    if (envProvider = "")
        envProvider := EnvGet("OPENAI_COMPAT_PROVIDER")
    if (envProvider != "")
        return NormalizeProvider(envProvider, "环境变量")

    return NormalizeProvider(DEFAULT_PROVIDER, "脚本默认值")
}

NormalizeProvider(provider, sourceName := "配置") {
    provider := StrLower(Trim(provider))
    if (provider = "qwen" || provider = "aliyun")
        provider := "dashscope"

    if (provider = "go")
        provider := "opencode"
    if (provider = "luna" || provider = "gpt_luna" || provider = "gpt-5.6-luna")
        provider := "opencode_luna"

    if (provider != "deepseek" && provider != "dashscope" && provider != "opencode" && provider != "opencode_luna")
        throw Error(sourceName "中的供应商不支持：" provider "。可选值：deepseek、dashscope、qwen、opencode、go、opencode_luna、luna。")

    return provider
}

GetProviderApiKey(provider) {
    if (provider = "dashscope")
        return EnvGet("DASHSCOPE_API_KEY")
    if (provider = "opencode" || provider = "opencode_luna")
        return EnvGet("OPENCODE_API_KEY")

    return EnvGet("DEEPSEEK_API_KEY")
}

GetProviderApiUrl(provider) {
    customUrl := EnvGet("OPENAI_COMPAT_API_URL")
    if (customUrl != "")
        return customUrl

    if (provider = "dashscope")
        return "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
    if (provider = "opencode")
        return "https://opencode.ai/zen/go/v1/chat/completions"
    if (provider = "opencode_luna")
        return "https://opencode.ai/zen/go/v1/responses"

    return "https://api.deepseek.com/chat/completions"
}

; 提供商模型
GetProviderModel(provider) {
    customModel := EnvGet("OPENAI_COMPAT_MODEL")
    if (customModel != "")
        return customModel

    if (provider = "dashscope")
        return "deepseek-v4-flash-0731"
    if (provider = "opencode")
        return "deepseek-v4-flash"
    if (provider = "opencode_luna")
        return "gpt-5.6-luna"

    return "deepseek-v4-flash"
}

GetProviderDisplayName(provider) {
    if (provider = "dashscope")
        return "千问供应商"
    if (provider = "opencode")
        return "OpenCode Go"
    if (provider = "opencode_luna")
        return "OpenCode Luna"

    return "DeepSeek"
}
; Alt+Shift+1：润色选中文本
$!+1::PolishSelectedText()

; Alt+Shift+2：翻译选中文本
$!+2::TranslateSelectedText()

PolishSelectedText() {
    RunSelectedTextAction("润色", "文本润色工具", CallPolishApi, "Alt+Shift+1")
}

TranslateSelectedText() {
    RunSelectedTextAction("翻译", "文本翻译工具", CallTranslateApi, "Alt+Shift+2")
}

RunSelectedTextAction(actionName, actionTitle, CallApi, hotkeyHint) {
    global API_KEY, PROVIDER

    if (API_KEY = "") {
        MsgBox "没有找到 " GetProviderDisplayName(PROVIDER) " 的 API Key。`n`nDeepSeek：setx DEEPSEEK_API_KEY `"你的 DeepSeek API Key`"`n千问供应商：setx DASHSCOPE_API_KEY `"你的 DashScope API Key`"`nOpenCode Go：setx OPENCODE_API_KEY `"你的 OpenCode Go API Key`"`n`n请使用 Windows 用户环境变量保存密钥。", actionTitle, "Icon!"
        return
    }

    oldClipboard := ClipboardAll()
    A_Clipboard := ""
    Send "^c"

    if !ClipWait(1) {
        A_Clipboard := oldClipboard
        MsgBox "没有复制到文本。请先选中要" actionName "的文字，再按 " hotkeyHint "。", actionTitle, "Icon!"
        return
    }

    sourceText := A_Clipboard
    if (Trim(sourceText) = "") {
        A_Clipboard := oldClipboard
        MsgBox "选中的内容为空。", actionTitle, "Icon!"
        return
    }

    ShowStatus("正在" actionName)

    try {
        resultText := CallApi(sourceText)
        if (Trim(resultText) = "")
            throw Error("接口返回内容为空。")

        resultText := PreserveBoundaryWhitespace(sourceText, resultText)
        A_Clipboard := resultText
        ClipWait(1)

        if (IsWindowsTerminalActive()) {
            terminalMode := ResolveWindowsTerminalMode()
            if (terminalMode = "wsl_codex") {
                ReplaceWslCodexInput(sourceText)
            } else if (terminalMode = "replace_line") {
                ReplaceWindowsTerminalInput()
            } else if (terminalMode = "copy") {
                ShowStatus("Windows Terminal 中" actionName "结果已复制到剪贴板。")
                Sleep 1800
                HideStatus()
            } else {
                Send "^v"
                Sleep 150
                HideStatus()
            }
        } else {
            Send "^v"
            Sleep 150
            HideStatus()
        }
    } catch as err {
        HideStatus()
        A_Clipboard := oldClipboard
        MsgBox actionName "失败：`n" err.Message, actionTitle, "Iconx"
    }
}

CallPolishApi(text) {
    global PROVIDER

    systemPrompt := "你是一个中文文本润色助手。请在不改变原意的前提下，让文字更自然、清晰、得体。只输出润色后的文本，不要解释，不要加标题。"
    ;systemPrompt := "你是一个中文文本润色助手。请只对自然语言表达进行润色，在不改变原意、不增删事实信息的前提下，使文本更自然、清晰、准确、得体。必须保留原文的格式结构，包括换行、缩进、列表、编号、Markdown 标记、代码片段、命令、路径、变量名和专有名词。不要改写代码、命令、配置项、URL、文件路径、产品名称、模块名、类名、函数名或资源名称。只输出润色后的文本，不要解释，不要加标题。"
    ; OpenCode Luna 使用 /responses，不兼容 Chat Completions 的 messages 请求体
    if (PROVIDER = "opencode_luna")
        return CallResponsesApi(text, systemPrompt)

    return CallChatCompletions(text, systemPrompt)
}

CallTranslateApi(text) {
    global PROVIDER

    systemPrompt := "你是一个专业翻译助手。请将用户提供的文本翻译成" GetTranslateTargetLanguage(text) "，只输出译文，不要解释，不要加标题。"
    if (PROVIDER = "opencode_luna")
        return CallResponsesApi(text, systemPrompt)

    return CallChatCompletions(text, systemPrompt)
}

GetTranslateTargetLanguage(sourceText) {
    target := StrLower(Trim(EnvGet("AI_TEXT_TRANSLATE_TARGET")))
    if (target = "")
        target := "auto"

    if (target = "auto") {
        if RegExMatch(sourceText, "[\x{4E00}-\x{9FFF}]")
            return "英语"
        return "简体中文"
    }

    if (target = "zh" || target = "cn" || target = "chinese" || target = "中文" || target = "简体中文")
        return "简体中文"
    if (target = "en" || target = "english" || target = "英语")
        return "英语"

    return target
}

CallChatCompletions(text, systemPrompt) {
    global API_KEY, API_URL, MODEL, PROVIDER

    body := BuildChatCompletionsBody(text, systemPrompt)

    http := ComObject("WinHttp.WinHttpRequest.5.1")
    http.Open("POST", API_URL, true)
    ConfigureHttpProxy(http)
    http.SetTimeouts(5000, 5000, 30000, 60000)
    http.SetRequestHeader("Content-Type", "application/json; charset=utf-8")
    http.SetRequestHeader("Authorization", "Bearer " API_KEY)
    http.Send(Utf8Bytes(body))
    WaitForHttpResponse(http, 65)

    status := http.Status
    response := Utf8Text(http.ResponseBody)
    if (status < 200 || status >= 300)
        throw Error("HTTP " status "`n" response)

    return ExtractAssistantContent(response)
}



CallResponsesApi(text, systemPrompt) {
    global API_KEY, API_URL, MODEL

    body := BuildResponsesBody(text, systemPrompt)

    http := ComObject("WinHttp.WinHttpRequest.5.1")
    http.Open("POST", API_URL, true)
    ConfigureHttpProxy(http)
    http.SetTimeouts(5000, 5000, 30000, 60000)
    http.SetRequestHeader("Content-Type", "application/json; charset=utf-8")
    http.SetRequestHeader("Authorization", "Bearer " API_KEY)
    http.Send(Utf8Bytes(body))
    WaitForHttpResponse(http, 65)

    status := http.Status
    response := Utf8Text(http.ResponseBody)
    if (status < 200 || status >= 300)
        throw Error("HTTP " status "`n" response)

    return ExtractResponsesContent(response)
}

ExtractResponsesContent(json) {
    q := Chr(34)
    ; 兼容 Responses API 常见的 output_text 字段，以及 output.content[].text 结构
    pattern := q "output_text" q "\s*:\s*" q "((?:\\.|[^" q "\\])*)" q
    if RegExMatch(json, pattern, &match)
        return JsonUnescape(match[1])

    pattern := q "type" q "\s*:\s*" q "output_text" q ".*?" q "text" q "\s*:\s*" q "((?:\\.|[^" q "\\])*)" q
    if RegExMatch(json, pattern, &match)
        return JsonUnescape(match[1])

    throw Error("无法解析 Responses API 返回：`n" json)
}

BuildChatCompletionsBody(text, systemPrompt) {
    global MODEL, PROVIDER

    bodyObj := Map(
        "model", MODEL,
        "messages", [
            Map("role", "system", "content", systemPrompt),
            Map("role", "user", "content", text)
        ],
        "temperature", 0.4
    )
    ApplyChatProviderOptions(bodyObj, PROVIDER)
    ; 第二个参数给足够大的展开层级，第三个参数用空字符串输出压缩 JSON
    return JSON.stringify(bodyObj, 10000000, "")
}

BuildResponsesBody(text, systemPrompt) {
    global MODEL

    ; Responses API 可以接收字符串 input；这里把系统提示和用户文本合并，保持请求体简单
    bodyObj := Map(
        "model", MODEL,
        "input", systemPrompt "`n`n" text,
        "temperature", 0.4
    )
    ApplyResponsesProviderOptions(bodyObj)
    return JSON.stringify(bodyObj, 10000000, "")
}

; thinking 参数默认关闭，因为当前响应解析器处理的是非流式 JSON
ApplyChatProviderOptions(bodyObj, provider) {
    if !IsTruthy(EnvGet("AI_TEXT_ENABLE_THINKING"))
        return

    if (provider = "dashscope") {
        bodyObj["enable_thinking"] := JSON.true
        return
    }
    if (provider != "deepseek")
        return

    bodyObj["thinking"] := Map("type", "enabled")
    bodyObj["reasoning_effort"] := GetReasoningEffort()
}

ApplyResponsesProviderOptions(bodyObj) {
    if !IsTruthy(EnvGet("AI_TEXT_ENABLE_THINKING"))
        return

    bodyObj["reasoning"] := Map("effort", GetReasoningEffort())
}

GetReasoningEffort() {
    reasoningEffort := EnvGet("AI_TEXT_REASONING_EFFORT")
    if (reasoningEffort = "")
        return "high"
    return reasoningEffort
}

IsTruthy(value) {
    value := StrLower(Trim(value))
    return value = "1" || value = "true" || value = "yes" || value = "on"
}

ConfigureHttpProxy(http) {
    global DEFAULT_PROXY_MODE, DEFAULT_PROXY_SERVER

    proxyMode := StrLower(Trim(EnvGet("AI_TEXT_PROXY_MODE")))
    if (proxyMode = "")
        proxyMode := DEFAULT_PROXY_MODE

    ; WinHTTP 的 system 模式读取 netsh winhttp 代理配置，不等同于 Windows 设置里的用户代理
    ; Clash/v2rayN/sing-box 等本地代理更适合用 manual 指定 127.0.0.1 端口
    if (proxyMode = "system" || proxyMode = "default") {
        http.SetProxy(0)
        return
    }

    if (proxyMode = "direct" || proxyMode = "none") {
        http.SetProxy(1)
        return
    }

    if (proxyMode = "manual") {
        proxyServer := Trim(EnvGet("AI_TEXT_PROXY_SERVER"))
        if (proxyServer = "")
            proxyServer := DEFAULT_PROXY_SERVER
        if (proxyServer = "")
            throw Error("AI_TEXT_PROXY_MODE=manual 时必须设置 AI_TEXT_PROXY_SERVER，例如：http://127.0.0.1:7890")

        proxyBypass := EnvGet("AI_TEXT_PROXY_BYPASS")
        http.SetProxy(2, proxyServer, proxyBypass)
        return
    }

    throw Error("AI_TEXT_PROXY_MODE 不支持：" proxyMode "。可选值：system、manual、direct。")
}

; WinHttp 使用异步等待，这样接口响应较慢时，“正在润色”动画仍能继续更新
WaitForHttpResponse(http, timeoutSeconds := 65) {
    startTick := A_TickCount
    lastDotsTick := 0

    while !http.WaitForResponse(0.05) {
        nowTick := A_TickCount
        if ((nowTick - lastDotsTick) >= 260) {
            UpdateStatusDots()
            lastDotsTick := nowTick
        }
        Sleep 10
        if ((A_TickCount - startTick) > timeoutSeconds * 1000)
            throw Error("请求超时。")
    }
}
ExtractAssistantContent(json) {
    ; Chat Completions 响应内容位于 choices[0].message.content
    ; 这里提取第一个名为 content 的 JSON 字符串并做反转义
    q := Chr(34)
    pattern := q "content" q "\s*:\s*" q "((?:\\.|[^" q "\\])*)" q
    if !RegExMatch(json, pattern, &match)
        throw Error("无法解析接口返回：`n" json)

    return JsonUnescape(match[1])
}

JsonUnescape(value) {
    output := ""
    i := 1
    q := Chr(34)

    while (i <= StrLen(value)) {
        ch := SubStr(value, i, 1)

        if (ch != "\") {
            output .= ch
            i += 1
            continue
        }

        i += 1
        esc := SubStr(value, i, 1)

        if (esc = q)
            output .= q
        else if (esc = "\")
            output .= "\"
        else if (esc = "/")
            output .= "/"
        else if (esc = "b")
            output .= Chr(8)
        else if (esc = "f")
            output .= Chr(12)
        else if (esc = "n")
            output .= "`n"
        else if (esc = "r")
            output .= "`r"
        else if (esc = "t")
            output .= "`t"
        else if (esc = "u") {
            hex := SubStr(value, i + 1, 4)
            if RegExMatch(hex, "^[0-9A-Fa-f]{4}$") {
                output .= Chr("0x" hex)
                i += 4
            } else {
                output .= "\u"
            }
        } else {
            output .= esc
        }

        i += 1
    }

    return output
}

PreserveBoundaryWhitespace(sourceText, polishedText) {
    ; AI 常会吃掉首尾空白；替换选区时保留边界空白可以避免与下一行内容粘连
    leadingWhitespace := ""
    trailingWhitespace := ""

    if RegExMatch(sourceText, "^\s+", &leadingMatch)
        leadingWhitespace := leadingMatch[0]

    if RegExMatch(sourceText, "\s+$", &trailingMatch)
        trailingWhitespace := trailingMatch[0]

    return leadingWhitespace Trim(polishedText) trailingWhitespace
}

IsWindowsTerminalActive() {
    processName := WinGetProcessName("A")
    return processName = "WindowsTerminal.exe" || processName = "WindowsTerminalPreview.exe"
}

; Windows Terminal 需要单独处理，因为鼠标选中的通常是屏幕文本，不是可编辑输入区
ResolveWindowsTerminalMode() {
    global WINDOWS_TERMINAL_MODE

    if (WINDOWS_TERMINAL_MODE != "auto")
        return WINDOWS_TERMINAL_MODE

    title := WinGetTitle("A")
    titleLower := StrLower(title)

    if (InStr(titleLower, "codex") || InStr(titleLower, "ubuntu") || InStr(titleLower, "wsl"))
        return "wsl_codex"

    ; 兼容直接从 Ubuntu-24.04.lnk 启动时的标题，例如 root@DESKTOP-Q1RCCT1: ~
    if RegExMatch(title, "^[^@\s]+@[^:]+:\s")
        return "wsl_codex"

    return "replace_line"
}

ReplaceWindowsTerminalInput() {
    ; Windows Terminal 中的鼠标选择通常是屏幕选择，不是可编辑文本选择
    ; 先清理当前命令行，再粘贴剪贴板中的润色结果
    Send "{Esc}"
    Sleep 80
    Send "{End}"
    Sleep 40
    Send "^{Home}"
    Sleep 80
    Send "^v"
    Sleep 150
    HideStatus()
}

ReplaceWslCodexInput(sourceText) {
    ; WSL 中的 Codex CLI 有自己的多行输入缓冲区
    ; 使用 Ctrl+U 逐行清理输入，避免 Ctrl+C 中断正在运行的 Codex 任务
    clearCount := CountTextLines(sourceText) + 3
    Send "{End}"
    Sleep 80
    Loop clearCount {
        Send "^u"
        Sleep 25
    }
    Send "+{Insert}"
    Sleep 150
    HideStatus()
}

CountTextLines(text) {
    normalized := StrReplace(text, "`r`n", "`n")
    normalized := StrReplace(normalized, "`r", "`n")
    return StrSplit(normalized, "`n").Length
}

ShowStatus(text) {
    global statusGui, statusDotsCtrl, statusTextCtrl, statusDotsFrame

    HideStatus()
    statusDotsFrame := 0

    statusGui := Gui("+AlwaysOnTop -Caption +ToolWindow")
    statusGui.BackColor := "FFFDF2"
    statusGui.MarginX := 12
    statusGui.MarginY := 8
    statusGui.SetFont("s10", "Microsoft YaHei UI")
    statusTextCtrl := statusGui.AddText("xm ym c222222", text)
    statusGui.SetFont("s11", "Microsoft YaHei UI")
    statusDotsCtrl := statusGui.AddText("x+1 yp-1 w34 h22 Center c222222", "···")

    pos := GetStatusPosition()
    statusGui.Show("NoActivate AutoSize x" pos.x " y" pos.y)
    SetTimer UpdateStatusDots, 260
}

HideStatus() {
    global statusGui, statusDotsCtrl, statusTextCtrl, statusDotsFrame

    SetTimer UpdateStatusDots, 0
    if IsObject(statusGui) {
        try statusGui.Destroy()
    }
    statusGui := ""
    statusDotsCtrl := ""
    statusTextCtrl := ""
    statusDotsFrame := 0
    ToolTip
}

UpdateStatusDots() {
    global statusDotsCtrl, statusDotsFrame

    if !IsObject(statusDotsCtrl)
        return

    frames := ["···", "•··", "·•·", "··•"]
    statusDotsFrame := Mod(statusDotsFrame, frames.Length) + 1
    statusDotsCtrl.Text := frames[statusDotsFrame]
}

; 不是所有应用都能取得光标坐标，取不到时回退到鼠标位置
GetStatusPosition() {
    CoordMode "Caret", "Screen"
    CoordMode "Mouse", "Screen"

    x := ""
    y := ""

    try {
        CaretGetPos &x, &y
    } catch {
        MouseGetPos &x, &y
    }

    if !IsNumber(x) || !IsNumber(y)
        MouseGetPos &x, &y

    x += 18
    y += 24

    screenRight := A_ScreenWidth - 220
    screenBottom := A_ScreenHeight - 80

    if (x > screenRight)
        x := screenRight
    if (y > screenBottom)
        y := screenBottom
    if (x < 0)
        x := 0
    if (y < 0)
        y := 0

    return { x: x, y: y }
}

Utf8Bytes(text) {
    ; ADODB.Stream 写文本会带 UTF-8 BOM，切到二进制后从第 3 字节后读取以去掉 BOM
    stream := ComObject("ADODB.Stream")
    stream.Type := 2
    stream.Charset := "utf-8"
    stream.Open()
    stream.WriteText(text)
    stream.Position := 0
    stream.Type := 1
    stream.Position := 3
    bytes := stream.Read()
    stream.Close()
    return bytes
}

Utf8Text(bytes) {
    ; WinHttp ResponseBody 是字节数组，显式按 UTF-8 读取可避免中文乱码
    stream := ComObject("ADODB.Stream")
    stream.Type := 1
    stream.Open()
    stream.Write(bytes)
    stream.Position := 0
    stream.Type := 2
    stream.Charset := "utf-8"
    text := stream.ReadText()
    stream.Close()
    return text
}
; ===== 内嵌 JSON 工具 =====
; 来源：https://github.com/thqby/ahk2_lib/blob/master/JSON.ahk
; 许可：MIT License, Copyright (c) 2023 thqby
/************************************************************************
 * @description: JSON格式字符串序列化和反序列化, 修改自[HotKeyIt/Yaml](https://github.com/HotKeyIt/Yaml)
 * 增加了对true/false/null类型的支持, 保留了数值的类型
 * @author thqby, HotKeyIt
 * @date 2025/12/22
 * @version 1.0.8
 ***********************************************************************/

class JSON {
	static null := ComValue(1, 0), true := ComValue(0xB, 1), false := ComValue(0xB, 0)

	/**
	 * Converts a AutoHotkey Object Notation JSON string into an object.
	 * @param text A valid JSON string.
	 * @param keepbooltype convert true/false/null to JSON.true / JSON.false / JSON.null where it's true, otherwise 1 / 0 / ''
	 * @param as_map object literals are converted to map, otherwise to object
	 */
	static parse(text, keepbooltype := false, as_map := true) {
		keepbooltype ? (_true := this.true, _false := this.false, _null := this.null) : (_true := true, _false := false, _null := "")
		as_map ? (map_set := (maptype := Map).Prototype.Set) : (map_set := (obj, key, val) => obj.%key% := val, maptype := Object)
		NQ := "", LF := "", LP := 0, P := "", R := "", text := LTrim(text, " `t`r`n")
		if !text || !InStr('{[', SubStr(text, 1, 1))
			throw Error("Malformed JSON - unrecognized character.", 0, SubStr(text, 1, 1))
		D := [C := (A := InStr(text, "[") = 1) ? [] : maptype()], text := LTrim(SubStr(text, 2), " `t`r`n"), L := 1, N := 0, V := K := "", J := C, !(Q := InStr(text, '"') != 1) ? text := SubStr(text, 2) : ""
		Loop Parse text, '"' {
			Q := NQ ? 1 : !Q
			NQ := Q && RegExMatch(A_LoopField, '(^|[^\\])(\\\\)*\\$')
			if !Q {
				if (t := Trim(A_LoopField, " `t`r`n")) = "," || (t = ":" && V := 1)
					continue
				else if t && (InStr("{[]},:", SubStr(t, 1, 1)) || A && RegExMatch(t, "m)^(null|false|true|-?\d+(\.\d*)?([eE][-+]\d+)?)\s*[,}\]\r\n]")) {
					Loop Parse t {
						if N && N--
							continue
						if InStr("`n`r `t", A_LoopField)
							continue
						else if InStr("{[", A_LoopField) {
							if !A && !V
								throw Error("Malformed JSON - missing key.", 0, t)
							C := A_LoopField = "[" ? [] : maptype(), A ? D[L].Push(C) : map_set(D[L], K, C), D.Has(++L) ? D[L] := C : D.Push(C), V := "", A := Type(C) = "Array"
							continue
						} else if InStr("]}", A_LoopField) {
							if !A && V
								throw Error("Malformed JSON - missing value.", 0, t)
							else if L = 0
								throw Error("Malformed JSON - to many closing brackets.", 0, t)
							else C := --L = 0 ? "" : D[L], A := Type(C) = "Array"
						} else if !(InStr(" `t`r,", A_LoopField) || (A_LoopField = ":" && V := 1)) {
							if RegExMatch(SubStr(t, A_Index), "m)^(null|false|true|-?\d+(\.\d*)?([eE][-+]\d+)?)\s*[,}\]\r\n]", &R) && (N := R.Len(0) - 2, R := R.1, 1) {
								if A
									C.Push(R = "null" ? _null : R = "true" ? _true : R = "false" ? _false : IsNumber(R) ? R + 0 : R)
								else if V
									map_set(C, K, R = "null" ? _null : R = "true" ? _true : R = "false" ? _false : IsNumber(R) ? R + 0 : R), K := V := ""
								else throw Error("Malformed JSON - missing key.", 0, t)
							} else {
								; Added support for comments without '"'
								if A_LoopField == '/' {
									nt := SubStr(t, A_Index + 1, 1), N := 0
									if nt == '/' {
										if nt := InStr(t, '`n', , A_Index + 2)
											N := nt - A_Index - 1
									} else if nt == '*' {
										if nt := InStr(t, '*/', , A_Index + 2)
											N := nt + 1 - A_Index
									} else nt := 0
									if N
										continue
								}
								throw Error("Malformed JSON - unrecognized character.", 0, A_LoopField " in " t)
							}
						}
					}
				} else if A || InStr(t, ':') > 1
					throw Error("Malformed JSON - unrecognized character.", 0, SubStr(t, 1, 1) " in " t)
			} else if NQ && (P .= A_LoopField '"', 1)
				continue
			else if A
				LF := P A_LoopField, C.Push(InStr(LF, "\") ? UC(LF) : LF), P := ""
			else if V
				LF := P A_LoopField, map_set(C, K, InStr(LF, "\") ? UC(LF) : LF), K := V := P := ""
			else
				LF := P A_LoopField, K := InStr(LF, "\") ? UC(LF) : LF, P := ""
		}
		return J
		UC(S, e := 1) {
			static m := Map('"', '"', "a", "`a", "b", "`b", "t", "`t", "n", "`n", "v", "`v", "f", "`f", "r", "`r")
			local v := ""
			Loop Parse S, "\"
				if !((e := !e) && A_LoopField = "" ? v .= "\" : !e ? (v .= A_LoopField, 1) : 0)
					v .= (t := m.Get(SubStr(A_LoopField, 1, 1), 0)) ? t SubStr(A_LoopField, 2) :
						(t := RegExMatch(A_LoopField, "i)^(u[\da-f]{4}|x[\da-f]{2})\K")) ?
							Chr("0x" SubStr(A_LoopField, 2, t - 2)) SubStr(A_LoopField, t) : "\" A_LoopField,
							e := A_LoopField = "" ? e : !e
			return v
		}
	}

	/**
	 * Converts a AutoHotkey Array/Map/Object to a Object Notation JSON string.
	 * @param obj A AutoHotkey value, usually an object or array or map, to be converted.
	 * @param expandlevel The level of JSON string need to expand, by default expand all.
	 * @param space Adds indentation, white space, and line break characters to the return-value JSON text to make it easier to read.
	 */
	static stringify(obj, expandlevel := unset, space := "  ") {
		expandlevel := IsSet(expandlevel) ? Abs(expandlevel) : 10000000
		return Trim(CO(obj, expandlevel))
		CO(O, J := 0, R := 0, Q := 0) {
			static M1 := "{", M2 := "}", S1 := "[", S2 := "]", N := "`n", C := ",", S := "- ", E := "", K := ":"
			if (OT := Type(O)) = "Array" {
				D := !R ? S1 : ""
				for key, value in O {
					F := (VT := Type(value)) = "Array" ? "S" : InStr("Map,Object", VT) ? "M" : E
					Z := VT = "Array" && value.Length = 0 ? "[]" : ((VT = "Map" && value.count = 0) || (VT = "Object" && ObjOwnPropCount(value) = 0)) ? "{}" : ""
					D .= (J > R ? "`n" CL(R + 2) : "") (F ? (%F%1 (Z ? "" : CO(value, J, R + 1, F)) %F%2) : ES(value)) (OT = "Array" && O.Length = A_Index ? E : C)
				}
			} else {
				D := !R ? M1 : ""
				for key, value in (OT := Type(O)) = "Map" ? (Y := 1, O) : (Y := 0, O.OwnProps()) {
					F := (VT := Type(value)) = "Array" ? "S" : InStr("Map,Object", VT) ? "M" : E
					Z := VT = "Array" && value.Length = 0 ? "[]" : ((VT = "Map" && value.count = 0) || (VT = "Object" && ObjOwnPropCount(value) = 0)) ? "{}" : ""
					D .= (J > R ? "`n" CL(R + 2) : "") (Q = "S" && A_Index = 1 ? M1 : E) ES(key) K (F ? (%F%1 (Z ? "" : CO(value, J, R + 1, F)) %F%2) : ES(value)) (Q = "S" && A_Index = (Y ? O.count : ObjOwnPropCount(O)) ? M2 : E) (J != 0 || R ? (A_Index = (Y ? O.count : ObjOwnPropCount(O)) ? E : C) : E)
					if J = 0 && !R
						D .= (A_Index < (Y ? O.count : ObjOwnPropCount(O)) ? C : E)
				}
			}
			if J > R
				D .= "`n" CL(R + 1)
			if R = 0
				D := RegExReplace(D, "^\R+") (OT = "Array" ? S2 : M2)
			return D
		}
		ES(S) {
			switch Type(S) {
				case "Float":
					if (v := '', d := InStr(S, 'e'))
						v := SubStr(S, d), S := SubStr(S, 1, d - 1)
					if ((StrLen(S) > 17) && (d := RegExMatch(S, "(99999+|00000+)\d{0,3}$")))
						S := Round(S, Max(1, d - InStr(S, ".") - 1))
					return S v
				case "Integer":
					return S
				case "String":
					S := StrReplace(S, "\", "\\")
					S := StrReplace(S, "`t", "\t")
					S := StrReplace(S, "`r", "\r")
					S := StrReplace(S, "`n", "\n")
					S := StrReplace(S, "`b", "\b")
					S := StrReplace(S, "`f", "\f")
					S := StrReplace(S, "`v", "\v")
					S := StrReplace(S, '"', '\"')
					return '"' S '"'
				default:
					return S == this.true ? "true" : S == this.false ? "false" : "null"
			}
		}
		CL(i) {
			Loop (s := "", space ? i - 1 : 0)
				s .= space
			return s
		}
	}
}
