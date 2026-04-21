package sing

import (
	"context"
	"fmt"
	"net"
	"net/netip"
	"sync"

	"github.com/sagernet/sing-box/adapter"
	sbOutbound "github.com/sagernet/sing-box/adapter/outbound"
	"github.com/sagernet/sing-box/common/dialer"
	"github.com/sagernet/sing-box/log"
	"github.com/sagernet/sing-box/option"
	"github.com/sagernet/sing/common/json/badoption"
	M "github.com/sagernet/sing/common/metadata"
	N "github.com/sagernet/sing/common/network"
	"github.com/sagernet/sing/service"
)

const originDirectOutboundType = "v2bx-origin-direct"

type OriginDirectOutboundOptions struct {
	option.DialerOptions
	UseOrigin bool
}

type OriginDirectOutbound struct {
	sbOutbound.Adapter
	ctx               context.Context
	logger            log.ContextLogger
	connectionManager adapter.ConnectionManager
	baseOptions       option.DialerOptions
	useOrigin         bool
	staticDialer      N.Dialer
	dialerCache       sync.Map
}

var (
	_ adapter.Outbound                  = (*OriginDirectOutbound)(nil)
	_ adapter.ConnectionHandlerEx       = (*OriginDirectOutbound)(nil)
	_ adapter.PacketConnectionHandlerEx = (*OriginDirectOutbound)(nil)
)

func registerOriginDirectOutbound(registry *sbOutbound.Registry) {
	sbOutbound.Register[OriginDirectOutboundOptions](registry, originDirectOutboundType, newOriginDirectOutbound)
}

func newOriginDirectOutbound(ctx context.Context, _ adapter.Router, logger log.ContextLogger, tag string, options OriginDirectOutboundOptions) (adapter.Outbound, error) {
	options.UDPFragmentDefault = true
	connectionManager := service.FromContext[adapter.ConnectionManager](ctx)
	if connectionManager == nil {
		return nil, fmt.Errorf("missing connection manager")
	}
	outbound := &OriginDirectOutbound{
		Adapter:           sbOutbound.NewAdapterWithDialerOptions(originDirectOutboundType, tag, []string{N.NetworkTCP, N.NetworkUDP}, options.DialerOptions),
		ctx:               ctx,
		logger:            logger,
		connectionManager: connectionManager,
		baseOptions:       options.DialerOptions,
		useOrigin:         options.UseOrigin,
	}
	if bindAddr, ok := bindAddrFromOptions(options.DialerOptions); ok || !options.UseOrigin {
		staticDialer, err := outbound.buildDialer(bindAddr, ok)
		if err != nil {
			return nil, err
		}
		outbound.staticDialer = staticDialer
	}
	return outbound, nil
}

func (o *OriginDirectOutbound) DialContext(ctx context.Context, network string, destination M.Socksaddr) (net.Conn, error) {
	ctx, metadata := adapter.ExtendContext(ctx)
	metadata.Outbound = o.Tag()
	metadata.Destination = destination
	outboundDialer, err := o.newDialerFromMetadata(*metadata, nil)
	if err != nil {
		return nil, err
	}
	o.logger.InfoContext(ctx, "outbound connection to ", destination)
	return outboundDialer.DialContext(ctx, network, destination)
}

func (o *OriginDirectOutbound) ListenPacket(ctx context.Context, destination M.Socksaddr) (net.PacketConn, error) {
	ctx, metadata := adapter.ExtendContext(ctx)
	metadata.Outbound = o.Tag()
	metadata.Destination = destination
	outboundDialer, err := o.newDialerFromMetadata(*metadata, nil)
	if err != nil {
		return nil, err
	}
	o.logger.InfoContext(ctx, "outbound packet connection")
	return outboundDialer.ListenPacket(ctx, destination)
}

func (o *OriginDirectOutbound) NewConnectionEx(ctx context.Context, conn net.Conn, metadata adapter.InboundContext, onClose N.CloseHandlerFunc) {
	metadata.Outbound = o.Tag()
	outboundDialer, err := o.newDialerFromMetadata(metadata, conn.LocalAddr())
	if err != nil {
		N.CloseOnHandshakeFailure(conn, onClose, err)
		o.logger.ErrorContext(ctx, err)
		return
	}
	o.connectionManager.NewConnection(ctx, outboundDialer, conn, metadata, onClose)
}

func (o *OriginDirectOutbound) NewPacketConnectionEx(ctx context.Context, conn N.PacketConn, metadata adapter.InboundContext, onClose N.CloseHandlerFunc) {
	metadata.Outbound = o.Tag()
	outboundDialer, err := o.newDialerFromMetadata(metadata, conn.LocalAddr())
	if err != nil {
		N.CloseOnHandshakeFailure(conn, onClose, err)
		o.logger.ErrorContext(ctx, err)
		return
	}
	o.connectionManager.NewPacketConnection(ctx, outboundDialer, conn, metadata, onClose)
}

func (o *OriginDirectOutbound) newDialerFromMetadata(metadata adapter.InboundContext, localAddr net.Addr) (N.Dialer, error) {
	if o.staticDialer != nil {
		return o.staticDialer, nil
	}
	bindAddr, ok := o.resolveBindAddr(metadata, localAddr)
	cacheKey := "<default>"
	if ok {
		cacheKey = bindAddr.String()
	}
	if cachedDialer, loaded := o.dialerCache.Load(cacheKey); loaded {
		return cachedDialer.(N.Dialer), nil
	}
	newDialer, err := o.buildDialer(bindAddr, ok)
	if err != nil {
		return nil, err
	}
	if cachedDialer, loaded := o.dialerCache.LoadOrStore(cacheKey, newDialer); loaded {
		return cachedDialer.(N.Dialer), nil
	}
	return newDialer, nil
}

func (o *OriginDirectOutbound) buildDialer(bindAddr netip.Addr, ok bool) (N.Dialer, error) {
	dialerOptions := o.baseOptions
	dialerOptions.Inet4BindAddress = nil
	dialerOptions.Inet6BindAddress = nil
	if ok {
		bind := badoption.Addr(bindAddr)
		if bindAddr.Is4() {
			dialerOptions.Inet4BindAddress = &bind
		} else {
			dialerOptions.Inet6BindAddress = &bind
		}
	}
	return dialer.NewWithOptions(dialer.Options{
		Context:        o.ctx,
		Options:        dialerOptions,
		RemoteIsDomain: true,
		DirectOutbound: true,
	})
}

func (o *OriginDirectOutbound) resolveBindAddr(metadata adapter.InboundContext, localAddr net.Addr) (netip.Addr, bool) {
	if bindAddr, ok := bindAddrFromOptions(o.baseOptions); ok {
		return bindAddr, true
	}
	if !o.useOrigin {
		return netip.Addr{}, false
	}
	if metadata.OriginDestination.Addr.IsValid() && !metadata.OriginDestination.Addr.IsUnspecified() {
		return metadata.OriginDestination.Addr, true
	}
	if localAddr == nil {
		return netip.Addr{}, false
	}
	local := M.SocksaddrFromNet(localAddr).Unwrap()
	if local.Addr.IsValid() && !local.Addr.IsUnspecified() {
		return local.Addr, true
	}
	return netip.Addr{}, false
}

func bindAddrFromOptions(options option.DialerOptions) (netip.Addr, bool) {
	if options.Inet4BindAddress != nil {
		addr := options.Inet4BindAddress.Build(netip.Addr{})
		if addr.IsValid() && !addr.IsUnspecified() {
			return addr, true
		}
	}
	if options.Inet6BindAddress != nil {
		addr := options.Inet6BindAddress.Build(netip.Addr{})
		if addr.IsValid() && !addr.IsUnspecified() {
			return addr, true
		}
	}
	return netip.Addr{}, false
}
