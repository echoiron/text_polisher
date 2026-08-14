package main

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"strings"
	"time"

	"text_polisher/macos/text-polisher/internal/textpolisher"
)

func main() {
	if err := run(); err != nil {
		notify("文本处理失败", err.Error())
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func run() error {
	action, skipCopy, err := parseArgs(os.Args)
	if err != nil {
		return err
	}

	cfg, err := textpolisher.LoadConfig(os.Getenv)
	if err != nil {
		return err
	}

	oldClipboard, _ := readClipboard()
	if !skipCopy {
		if err := writeClipboard(""); err != nil {
			return err
		}
		if err := copySelection(); err != nil {
			restoreClipboard(oldClipboard)
			return err
		}
	} else {
		time.Sleep(150 * time.Millisecond)
	}

	source, err := readClipboard()
	if err != nil {
		restoreClipboard(oldClipboard)
		return err
	}
	if strings.TrimSpace(source) == "" {
		restoreClipboard(oldClipboard)
		return errors.New("没有复制到文本。请先选中要处理的文字")
	}

	notify("文本处理", statusText(action))

	client, err := textpolisher.NewHTTPClient(cfg)
	if err != nil {
		restoreClipboard(oldClipboard)
		return err
	}

	ctx, cancel := context.WithTimeout(context.Background(), 70*time.Second)
	defer cancel()

	result, err := textpolisher.RunAction(ctx, action, source, cfg, client)
	if err != nil {
		restoreClipboard(oldClipboard)
		return err
	}

	if err := writeClipboard(result); err != nil {
		restoreClipboard(oldClipboard)
		return err
	}

	strategy := pasteStrategy(cfg, frontmostAppName())
	if strategy == strategyCopy {
		notify("文本处理", "结果已复制到剪贴板")
		return nil
	}

	if strategy == strategyReplaceTerminalInput {
		if err := replaceTerminalInput(source); err != nil {
			return err
		}
		return nil
	}

	if err := pasteClipboard(); err != nil {
		return err
	}
	return nil
}

func parseArgs(args []string) (textpolisher.Action, bool, error) {
	if len(args) < 2 || len(args) > 3 {
		return "", false, errors.New("usage: text-polisher polish|translate [--skip-copy]")
	}

	action, err := parseAction(args[1])
	if err != nil {
		return "", false, err
	}

	skipCopy := false
	if len(args) == 3 {
		if args[2] != "--skip-copy" {
			return "", false, fmt.Errorf("unsupported option %q; use --skip-copy", args[2])
		}
		skipCopy = true
	}

	return action, skipCopy, nil
}

func parseAction(value string) (textpolisher.Action, error) {
	switch strings.ToLower(strings.TrimSpace(value)) {
	case string(textpolisher.ActionPolish):
		return textpolisher.ActionPolish, nil
	case string(textpolisher.ActionTranslate):
		return textpolisher.ActionTranslate, nil
	default:
		return "", fmt.Errorf("unsupported action %q; use polish or translate", value)
	}
}

func statusText(action textpolisher.Action) string {
	if action == textpolisher.ActionTranslate {
		return "正在翻译..."
	}
	return "正在润色..."
}

type pasteStrategyName string

const (
	strategyPaste                pasteStrategyName = "paste"
	strategyCopy                 pasteStrategyName = "copy"
	strategyReplaceTerminalInput pasteStrategyName = "replace_terminal_input"
)

func pasteStrategy(cfg textpolisher.Config, appName string) pasteStrategyName {
	mode := strings.ToLower(strings.TrimSpace(cfg.TerminalMode))
	if mode == "always_copy" {
		return strategyCopy
	}
	if !isTerminalApp(appName) {
		return strategyPaste
	}

	switch mode {
	case "copy":
		return strategyCopy
	case "paste":
		return strategyPaste
	default:
		return strategyReplaceTerminalInput
	}
}

func isTerminalApp(appName string) bool {
	switch strings.ToLower(strings.TrimSpace(appName)) {
	case "terminal", "iterm2", "warp", "wezterm", "alacritty", "kitty", "termius":
		return true
	default:
		return false
	}
}

func copySelection() error {
	if err := runAppleScript(`tell application "System Events" to keystroke "c" using command down`); err != nil {
		return fmt.Errorf("复制选中文本失败，请确认已给终端或 Karabiner 相关进程辅助功能权限: %w", err)
	}
	time.Sleep(180 * time.Millisecond)
	return nil
}

func pasteClipboard() error {
	if err := runAppleScript(`tell application "System Events" to keystroke "v" using command down`); err != nil {
		return fmt.Errorf("粘贴结果失败，请确认已给终端或 Karabiner 相关进程辅助功能权限: %w", err)
	}
	return nil
}

func replaceTerminalInput(source string) error {
	if err := runAppleScript(`tell application "System Events" to keystroke "e" using control down`); err != nil {
		return fmt.Errorf("移动到终端输入末尾失败，请确认辅助功能权限: %w", err)
	}
	time.Sleep(80 * time.Millisecond)

	clearCount := countTextLines(source) + 3
	for i := 0; i < clearCount; i++ {
		if err := runAppleScript(`tell application "System Events" to keystroke "u" using control down`); err != nil {
			return fmt.Errorf("清空终端输入失败，请确认辅助功能权限: %w", err)
		}
		time.Sleep(25 * time.Millisecond)
	}

	return pasteClipboard()
}

func countTextLines(text string) int {
	normalized := strings.ReplaceAll(text, "\r\n", "\n")
	normalized = strings.ReplaceAll(normalized, "\r", "\n")
	return len(strings.Split(normalized, "\n"))
}

func frontmostAppName() string {
	out, err := exec.Command("osascript", "-e", `tell application "System Events" to get name of first process whose frontmost is true`).Output()
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(out))
}

func runAppleScript(script string) error {
	cmd := exec.Command("osascript", "-e", script)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("%w: %s", err, strings.TrimSpace(stderr.String()))
	}
	return nil
}

func readClipboard() (string, error) {
	out, err := exec.Command("pbpaste").Output()
	if err != nil {
		return "", fmt.Errorf("读取剪贴板失败: %w", err)
	}
	return string(out), nil
}

func writeClipboard(text string) error {
	cmd := exec.Command("pbcopy")
	stdin, err := cmd.StdinPipe()
	if err != nil {
		return fmt.Errorf("打开剪贴板写入失败: %w", err)
	}
	if err := cmd.Start(); err != nil {
		return fmt.Errorf("启动 pbcopy 失败: %w", err)
	}
	if _, err := io.WriteString(stdin, text); err != nil {
		stdin.Close()
		return fmt.Errorf("写入剪贴板失败: %w", err)
	}
	if err := stdin.Close(); err != nil {
		return fmt.Errorf("关闭剪贴板写入失败: %w", err)
	}
	if err := cmd.Wait(); err != nil {
		return fmt.Errorf("保存剪贴板失败: %w", err)
	}
	return nil
}

func restoreClipboard(text string) {
	_ = writeClipboard(text)
}

func notify(title, message string) {
	_ = exec.Command(
		"osascript",
		"-e",
		fmt.Sprintf(`display notification %s with title %s`, appleScriptString(message), appleScriptString(title)),
	).Run()
}

func appleScriptString(value string) string {
	value = strings.ReplaceAll(value, `\`, `\\`)
	value = strings.ReplaceAll(value, `"`, `\"`)
	value = strings.ReplaceAll(value, "\r", " ")
	value = strings.ReplaceAll(value, "\n", " ")
	return `"` + value + `"`
}
