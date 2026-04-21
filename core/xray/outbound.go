package xray

import (
	"fmt"
	"strings"

	"encoding/json"

	conf2 "github.com/InazumaV/V2bX/conf"
	"github.com/xtls/xray-core/core"
	"github.com/xtls/xray-core/infra/conf"
)

// BuildOutbound build freedom outbund config for addoutbound
func buildOutbound(config *conf2.Options, tag string) (*core.OutboundHandlerConfig, error) {
	outboundDetourConfig := &conf.OutboundDetourConfig{}
	outboundDetourConfig.Protocol = "freedom"
	outboundDetourConfig.Tag = tag

	sendThrough := resolveSendThrough(config)
	if sendThrough != nil {
		outboundDetourConfig.SendThrough = sendThrough
	}

	// Freedom Protocol setting
	var domainStrategy = "Asis"
	if config.XrayOptions.EnableDNS {
		if config.XrayOptions.DNSType != "" {
			domainStrategy = config.XrayOptions.DNSType
		} else {
			domainStrategy = "UseIP"
		}
	}
	proxySetting := &conf.FreedomConfig{
		DomainStrategy: domainStrategy,
	}
	var setting json.RawMessage
	setting, err := json.Marshal(proxySetting)
	if err != nil {
		return nil, fmt.Errorf("marshal proxy config error: %s", err)
	}
	outboundDetourConfig.Settings = &setting
	return outboundDetourConfig.Build()
}

func resolveSendThrough(config *conf2.Options) *string {
	sendIP := strings.TrimSpace(config.SendIP)
	if sendIP != "" && sendIP != "0.0.0.0" && sendIP != "::" {
		return &sendIP
	}

	if config.XrayOptions != nil && config.XrayOptions.AutoSendThroughOrigin {
		sendThrough := "origin"
		return &sendThrough
	}

	if sendIP == "" {
		return nil
	}

	return &sendIP
}
