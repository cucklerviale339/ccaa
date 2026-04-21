package sing

import (
	"net"
	"net/netip"
	"testing"

	"github.com/sagernet/sing-box/adapter"
	"github.com/sagernet/sing-box/option"
	"github.com/sagernet/sing/common/json/badoption"
	M "github.com/sagernet/sing/common/metadata"
)

func TestResolveBindAddr(t *testing.T) {
	t.Parallel()

	t.Run("explicit bind address wins", func(t *testing.T) {
		t.Parallel()

		explicit := badoption.Addr(netip.MustParseAddr("203.0.113.30"))
		outbound := &OriginDirectOutbound{
			baseOptions: option.DialerOptions{
				Inet4BindAddress: &explicit,
			},
			useOrigin: true,
		}
		bindAddr, ok := outbound.resolveBindAddr(adapter.InboundContext{
			OriginDestination: M.ParseSocksaddrHostPort("198.51.100.1", 443).Unwrap(),
		}, &net.TCPAddr{IP: net.ParseIP("198.51.100.2"), Port: 443})
		if !ok {
			t.Fatal("expected explicit bind address to be used")
		}
		if bindAddr != netip.MustParseAddr("203.0.113.30") {
			t.Fatalf("unexpected bind address: %s", bindAddr)
		}
	})

	t.Run("origin destination is preferred when available", func(t *testing.T) {
		t.Parallel()

		outbound := &OriginDirectOutbound{useOrigin: true}
		bindAddr, ok := outbound.resolveBindAddr(adapter.InboundContext{
			OriginDestination: M.ParseSocksaddrHostPort("203.0.113.40", 8443).Unwrap(),
			Destination:       M.ParseSocksaddrHostPort("198.51.100.10", 443).Unwrap(),
		}, &net.TCPAddr{IP: net.ParseIP("203.0.113.41"), Port: 8443})
		if !ok {
			t.Fatal("expected origin destination to be used")
		}
		if bindAddr != netip.MustParseAddr("203.0.113.40") {
			t.Fatalf("unexpected bind address: %s", bindAddr)
		}
	})

	t.Run("local address is used when origin destination is empty", func(t *testing.T) {
		t.Parallel()

		outbound := &OriginDirectOutbound{useOrigin: true}
		bindAddr, ok := outbound.resolveBindAddr(adapter.InboundContext{
			Destination: M.ParseSocksaddrHostPort("198.51.100.10", 443).Unwrap(),
		}, &net.TCPAddr{IP: net.ParseIP("203.0.113.50"), Port: 8443})
		if !ok {
			t.Fatal("expected local address to be used")
		}
		if bindAddr != netip.MustParseAddr("203.0.113.50") {
			t.Fatalf("unexpected bind address: %s", bindAddr)
		}
	})

	t.Run("fake quic local address is ignored", func(t *testing.T) {
		t.Parallel()

		destination := M.ParseSocksaddrHostPort("198.51.100.10", 443).Unwrap()
		outbound := &OriginDirectOutbound{useOrigin: true}
		_, ok := outbound.resolveBindAddr(adapter.InboundContext{
			Destination: destination,
		}, &net.TCPAddr{IP: net.ParseIP("198.51.100.10"), Port: 443})
		if ok {
			t.Fatal("expected fake local address to be ignored")
		}
	})

	t.Run("origin binding can be disabled", func(t *testing.T) {
		t.Parallel()

		outbound := &OriginDirectOutbound{useOrigin: false}
		_, ok := outbound.resolveBindAddr(adapter.InboundContext{
			OriginDestination: M.ParseSocksaddrHostPort("203.0.113.60", 8443).Unwrap(),
		}, &net.TCPAddr{IP: net.ParseIP("203.0.113.61"), Port: 8443})
		if ok {
			t.Fatal("expected no bind address when origin binding is disabled")
		}
	})
}
