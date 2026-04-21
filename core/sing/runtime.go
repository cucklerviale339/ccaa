package sing

import (
	"context"
	"fmt"
	"net/netip"
	"sort"
	"strings"

	"github.com/InazumaV/V2bX/api/panel"
	"github.com/InazumaV/V2bX/conf"
	box "github.com/sagernet/sing-box"
	C "github.com/sagernet/sing-box/constant"
	"github.com/sagernet/sing-box/include"
	"github.com/sagernet/sing-box/option"
	"github.com/sagernet/sing/common/json"
	"github.com/sagernet/sing/common/json/badoption"
)

func newSingContext() context.Context {
	ctx := context.Background()
	outboundRegistry := include.OutboundRegistry()
	registerOriginDirectOutbound(outboundRegistry)
	return box.Context(
		ctx,
		include.InboundRegistry(),
		outboundRegistry,
		include.EndpointRegistry(),
		include.DNSTransportRegistry(),
		include.ServiceRegistry(),
	)
}

func (b *Sing) loadOptions(ctx context.Context) (option.Options, error) {
	options := option.Options{}
	if len(b.baseConfigData) != 0 {
		var err error
		options, err = json.UnmarshalExtendedContext[option.Options](ctx, b.baseConfigData)
		if err != nil {
			return option.Options{}, fmt.Errorf("unmarshal original config error: %s", err)
		}
	}
	options.Log = &option.LogOptions{
		Disabled:  b.coreConfig.SingConfig.LogConfig.Disabled,
		Level:     b.coreConfig.SingConfig.LogConfig.Level,
		Timestamp: b.coreConfig.SingConfig.LogConfig.Timestamp,
		Output:    b.coreConfig.SingConfig.LogConfig.Output,
	}
	options.NTP = &option.NTPOptions{
		Enabled:       b.coreConfig.SingConfig.NtpConfig.Enable,
		WriteToSystem: true,
		ServerOptions: option.ServerOptions{
			Server:     b.coreConfig.SingConfig.NtpConfig.Server,
			ServerPort: b.coreConfig.SingConfig.NtpConfig.ServerPort,
		},
	}
	return options, nil
}

func (b *Sing) buildNodeEntries() ([]option.Inbound, []option.Outbound, []option.Rule, error) {
	tags := make([]string, 0)
	b.nodeStates.Range(func(key, _ any) bool {
		tags = append(tags, key.(string))
		return true
	})
	sort.Strings(tags)

	inbounds := make([]option.Inbound, 0, len(tags))
	outbounds := make([]option.Outbound, 0, len(tags))
	rules := make([]option.Rule, 0, len(tags))
	for _, tag := range tags {
		stateValue, ok := b.nodeStates.Load(tag)
		if !ok {
			continue
		}
		state := stateValue.(*NodeState)
		b.users.mapLock.RLock()
		users := append([]panel.UserInfo(nil), state.users...)
		b.users.mapLock.RUnlock()
		inbound, err := getInboundOptions(tag, state.info, state.config)
		if err != nil {
			return nil, nil, nil, err
		}
		if err = applyInboundUsers(&inbound, state.info, users); err != nil {
			return nil, nil, nil, err
		}
		inbounds = append(inbounds, inbound)

		outbound, rule, err := buildNodeOutbound(tag, state.config)
		if err != nil {
			return nil, nil, nil, err
		}
		if outbound != nil && rule != nil {
			outbounds = append(outbounds, *outbound)
			rules = append(rules, *rule)
		}
	}
	return inbounds, outbounds, rules, nil
}

func (b *Sing) createBox() (context.Context, *box.Box, error) {
	ctx := newSingContext()
	options, err := b.loadOptions(ctx)
	if err != nil {
		return nil, nil, err
	}
	inbounds, outbounds, rules, err := b.buildNodeEntries()
	if err != nil {
		return nil, nil, err
	}
	if len(inbounds) > 0 {
		options.Inbounds = append(options.Inbounds, inbounds...)
	}
	if len(outbounds) > 0 {
		options.Outbounds = append(options.Outbounds, outbounds...)
	}
	if len(rules) > 0 {
		if options.Route == nil {
			options.Route = &option.RouteOptions{}
		}
		options.Route.Rules = append(rules, options.Route.Rules...)
	}

	newBox, err := box.New(box.Options{
		Context: ctx,
		Options: options,
	})
	if err != nil {
		return nil, nil, err
	}
	newBox.Router().AppendTracker(b.hookServer)
	return ctx, newBox, nil
}

func (b *Sing) rebuildBoxLocked() error {
	ctx, newBox, err := b.createBox()
	if err != nil {
		return err
	}
	oldBox := b.box
	wasStarted := b.started
	if oldBox != nil {
		if err = oldBox.Close(); err != nil {
			return err
		}
	}
	if wasStarted {
		if err = newBox.Start(); err != nil {
			return err
		}
	}
	b.ctx = ctx
	b.box = newBox
	b.router = newBox.Router()
	b.logFactory = newBox.LogFactory()
	return nil
}

func buildNodeOutbound(tag string, config *conf.Options) (*option.Outbound, *option.Rule, error) {
	options, ok, err := resolveOriginDirectOptions(config)
	if err != nil {
		return nil, nil, err
	}
	if !ok {
		return nil, nil, nil
	}

	outbound := &option.Outbound{
		Type:    originDirectOutboundType,
		Tag:     tag,
		Options: options,
	}
	rule := &option.Rule{
		DefaultOptions: option.DefaultRule{
			RawDefaultRule: option.RawDefaultRule{
				Inbound: badoption.Listable[string]{tag},
			},
			RuleAction: option.RuleAction{
				Action: C.RuleActionTypeRoute,
				RouteOptions: option.RouteActionOptions{
					Outbound: tag,
				},
			},
		},
	}
	return outbound, rule, nil
}

func resolveOriginDirectOptions(config *conf.Options) (*OriginDirectOutboundOptions, bool, error) {
	if config == nil || config.SingOptions == nil || !config.SingOptions.EnableSameTagOutbound {
		return nil, false, nil
	}
	options := &OriginDirectOutboundOptions{}
	bindIP := strings.TrimSpace(config.SendIP)
	switch bindIP {
	case "", "0.0.0.0", "::":
		listenIP := strings.TrimSpace(config.ListenIP)
		switch listenIP {
		case "", "0.0.0.0", "::":
			options.UseOrigin = config.SingOptions.AutoSendThroughOrigin
			if !options.UseOrigin {
				return nil, false, nil
			}
			return options, true, nil
		default:
			bindIP = listenIP
		}
	}
	addr, err := netip.ParseAddr(bindIP)
	if err != nil {
		return nil, false, fmt.Errorf("parse send ip error: %s", err)
	}
	bindAddr := badoption.Addr(addr)
	if addr.Is4() {
		options.Inet4BindAddress = &bindAddr
		return options, true, nil
	}
	options.Inet6BindAddress = &bindAddr
	return options, true, nil
}
