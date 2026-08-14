package textpolisher

import (
	"os"
	"testing"
)

func TestLoadConfigUsesGoAICompatDefaults(t *testing.T) {
	cfg, err := LoadConfig(func(key string) string {
		if key == "AI_TEXT_API_KEY" {
			return "test-key"
		}
		return ""
	})
	if err != nil {
		t.Fatalf("LoadConfig returned error: %v", err)
	}

	if cfg.BaseURL != "https://opencode.ai/zen/go/v1" {
		t.Fatalf("BaseURL = %q", cfg.BaseURL)
	}
	if cfg.Model != "gpt-5.6-luna" {
		t.Fatalf("Model = %q", cfg.Model)
	}
}

func TestLoadConfigFallsBackToOpenCodeAPIKey(t *testing.T) {
	cfg, err := LoadConfig(func(key string) string {
		if key == "OPENCODE_API_KEY" {
			return "test-key"
		}
		return ""
	})
	if err != nil {
		t.Fatalf("LoadConfig returned error: %v", err)
	}
	if cfg.APIKey != "test-key" {
		t.Fatal("LoadConfig did not read OPENCODE_API_KEY fallback")
	}
}

func TestLoadConfigRequiresProviderAPIKey(t *testing.T) {
	_, err := LoadConfig(func(string) string { return "" })
	if err == nil {
		t.Fatal("LoadConfig returned nil error, want missing API key error")
	}
}

func TestTranslateTargetLanguage(t *testing.T) {
	tests := []struct {
		name   string
		env    string
		source string
		want   string
	}{
		{name: "auto Chinese to English", source: "你好，世界", want: "英语"},
		{name: "auto English to Chinese", source: "hello world", want: "简体中文"},
		{name: "explicit English", env: "en", source: "你好", want: "英语"},
		{name: "explicit Chinese", env: "zh", source: "hello", want: "简体中文"},
		{name: "custom target", env: "Japanese", source: "hello", want: "Japanese"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := TranslateTargetLanguage(tt.source, tt.env)
			if got != tt.want {
				t.Fatalf("TranslateTargetLanguage() = %q, want %q", got, tt.want)
			}
		})
	}
}

func TestPreserveBoundaryWhitespace(t *testing.T) {
	got := PreserveBoundaryWhitespace("\n  原文\t", "润色后")
	want := "\n  润色后\t"
	if got != want {
		t.Fatalf("PreserveBoundaryWhitespace() = %q, want %q", got, want)
	}
}

func TestHTTPClientManualProxy(t *testing.T) {
	cfg := Config{ProxyMode: "manual", ProxyServer: "http://127.0.0.1:1080"}
	client, err := NewHTTPClient(cfg)
	if err != nil {
		t.Fatalf("NewHTTPClient returned error: %v", err)
	}
	if client == nil || client.Transport == nil {
		t.Fatal("NewHTTPClient returned nil client or transport")
	}
}

func TestMain(m *testing.M) {
	os.Exit(m.Run())
}
