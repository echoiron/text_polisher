package textpolisher

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"regexp"
	"strings"
	"time"

	"github.com/zendev-sh/goai"
	"github.com/zendev-sh/goai/provider/compat"
)

type Action string

const (
	ActionPolish    Action = "polish"
	ActionTranslate Action = "translate"
)

type Config struct {
	BaseURL         string
	APIKey          string
	Model           string
	TranslateTarget string
	ProxyMode       string
	ProxyServer     string
	TerminalMode    string
}

func LoadConfig(getenv func(string) string) (Config, error) {
	cfg := Config{
		BaseURL:         firstNonEmpty(getenv("AI_TEXT_API_BASE_URL"), getenv("OPENAI_COMPAT_BASE_URL"), "https://opencode.ai/zen/go/v1"),
		APIKey:          firstNonEmpty(getenv("AI_TEXT_API_KEY"), getenv("OPENCODE_API_KEY"), getenv("OPENAI_API_KEY")),
		Model:           firstNonEmpty(getenv("AI_TEXT_MODEL"), getenv("OPENAI_COMPAT_MODEL"), "gpt-5.6-luna"),
		TranslateTarget: getenv("AI_TEXT_TRANSLATE_TARGET"),
		ProxyMode:       strings.ToLower(strings.TrimSpace(firstNonEmpty(getenv("AI_TEXT_PROXY_MODE"), "system"))),
		ProxyServer:     firstNonEmpty(getenv("AI_TEXT_PROXY_SERVER"), "http://127.0.0.1:1080"),
		TerminalMode:    strings.ToLower(strings.TrimSpace(firstNonEmpty(getenv("AI_TEXT_MAC_TERMINAL_MODE"), "replace_input"))),
	}

	if strings.TrimSpace(cfg.APIKey) == "" {
		return Config{}, errors.New("missing API key; set AI_TEXT_API_KEY or OPENCODE_API_KEY")
	}
	if strings.TrimSpace(cfg.BaseURL) == "" {
		return Config{}, errors.New("missing API base URL; set AI_TEXT_API_BASE_URL")
	}
	if strings.TrimSpace(cfg.Model) == "" {
		return Config{}, errors.New("missing model; set AI_TEXT_MODEL")
	}

	return cfg, nil
}

func RunAction(ctx context.Context, action Action, source string, cfg Config, client *http.Client) (string, error) {
	if strings.TrimSpace(source) == "" {
		return "", errors.New("selected text is empty")
	}
	if client == nil {
		var err error
		client, err = NewHTTPClient(cfg)
		if err != nil {
			return "", err
		}
	}

	prompt, err := systemPrompt(action, source, cfg)
	if err != nil {
		return "", err
	}

	model := compat.Chat(
		cfg.Model,
		compat.WithBaseURL(cfg.BaseURL),
		compat.WithAPIKey(cfg.APIKey),
		compat.WithHTTPClient(client),
	)
	result, err := goai.GenerateText(ctx, model,
		goai.WithSystem(prompt),
		goai.WithPrompt(source),
		goai.WithTemperature(0.4),
	)
	if err != nil {
		return "", err
	}
	if strings.TrimSpace(result.Text) == "" {
		return "", errors.New("API returned empty content")
	}

	return PreserveBoundaryWhitespace(source, result.Text), nil
}

func NewHTTPClient(cfg Config) (*http.Client, error) {
	transport := http.DefaultTransport.(*http.Transport).Clone()

	switch strings.ToLower(strings.TrimSpace(cfg.ProxyMode)) {
	case "", "system", "default":
		transport.Proxy = http.ProxyFromEnvironment
	case "direct", "none":
		transport.Proxy = nil
	case "manual":
		proxyURL, err := url.Parse(cfg.ProxyServer)
		if err != nil {
			return nil, fmt.Errorf("invalid AI_TEXT_PROXY_SERVER: %w", err)
		}
		transport.Proxy = http.ProxyURL(proxyURL)
	default:
		return nil, fmt.Errorf("unsupported AI_TEXT_PROXY_MODE %q; use system, manual, or direct", cfg.ProxyMode)
	}

	return &http.Client{
		Timeout:   65 * time.Second,
		Transport: transport,
	}, nil
}

func TranslateTargetLanguage(sourceText, configuredTarget string) string {
	target := strings.ToLower(strings.TrimSpace(configuredTarget))
	if target == "" {
		target = "auto"
	}

	if target == "auto" {
		if regexp.MustCompile(`[\x{4E00}-\x{9FFF}]`).MatchString(sourceText) {
			return "英语"
		}
		return "简体中文"
	}

	switch target {
	case "zh", "cn", "chinese", "中文", "简体中文":
		return "简体中文"
	case "en", "english", "英语":
		return "英语"
	default:
		return strings.TrimSpace(configuredTarget)
	}
}

func PreserveBoundaryWhitespace(source, result string) string {
	leading := regexp.MustCompile(`^\s+`).FindString(source)
	trailing := regexp.MustCompile(`\s+$`).FindString(source)
	return leading + strings.TrimSpace(result) + trailing
}

func systemPrompt(action Action, source string, cfg Config) (string, error) {
	switch action {
	case ActionPolish:
		return "你是一个中文文本润色助手。请在不改变原意的前提下，让文字更自然、清晰、得体。只输出润色后的文本，不要解释，不要加标题。", nil
	case ActionTranslate:
		return "你是一个专业翻译助手。请将用户提供的文本翻译成" + TranslateTargetLanguage(source, cfg.TranslateTarget) + "，只输出译文，不要解释，不要加标题。", nil
	default:
		return "", fmt.Errorf("unsupported action %q", action)
	}
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if strings.TrimSpace(value) != "" {
			return value
		}
	}
	return ""
}
