package sing

import (
	"net/netip"
	"testing"

	"github.com/InazumaV/V2bX/conf"
)

func TestResolveOriginDirectOptions(t *testing.T) {
	t.Parallel()

	t.Run("disabled when same tag outbound is off", func(t *testing.T) {
		t.Parallel()

		options, ok, err := resolveOriginDirectOptions(&conf.Options{
			SingOptions: &conf.SingOptions{
				EnableSameTagOutbound: false,
			},
		})
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if ok {
			t.Fatalf("expected disabled result, got enabled: %#v", options)
		}
	})

	t.Run("uses explicit send ip", func(t *testing.T) {
		t.Parallel()

		options, ok, err := resolveOriginDirectOptions(&conf.Options{
			SendIP: "203.0.113.10",
			SingOptions: &conf.SingOptions{
				EnableSameTagOutbound: true,
			},
		})
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if !ok {
			t.Fatal("expected outbound options to be enabled")
		}
		if options.UseOrigin {
			t.Fatal("expected explicit send ip to disable origin auto bind")
		}
		if options.Inet4BindAddress == nil {
			t.Fatal("expected ipv4 bind address")
		}
		if got := options.Inet4BindAddress.Build(netip.Addr{}); got != netip.MustParseAddr("203.0.113.10") {
			t.Fatalf("unexpected bind address: %s", got)
		}
	})

	t.Run("falls back to listen ip when send ip is wildcard", func(t *testing.T) {
		t.Parallel()

		options, ok, err := resolveOriginDirectOptions(&conf.Options{
			ListenIP: "203.0.113.20",
			SendIP:   "0.0.0.0",
			SingOptions: &conf.SingOptions{
				EnableSameTagOutbound: true,
			},
		})
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if !ok {
			t.Fatal("expected outbound options to be enabled")
		}
		if options.Inet4BindAddress == nil {
			t.Fatal("expected ipv4 bind address")
		}
		if got := options.Inet4BindAddress.Build(netip.Addr{}); got != netip.MustParseAddr("203.0.113.20") {
			t.Fatalf("unexpected bind address: %s", got)
		}
	})

	t.Run("uses origin when both ips are wildcard", func(t *testing.T) {
		t.Parallel()

		options, ok, err := resolveOriginDirectOptions(&conf.Options{
			ListenIP: "0.0.0.0",
			SendIP:   "0.0.0.0",
			SingOptions: &conf.SingOptions{
				EnableSameTagOutbound: true,
				AutoSendThroughOrigin: true,
			},
		})
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if !ok {
			t.Fatal("expected outbound options to be enabled")
		}
		if !options.UseOrigin {
			t.Fatal("expected origin auto bind to be enabled")
		}
		if options.Inet4BindAddress != nil || options.Inet6BindAddress != nil {
			t.Fatal("expected wildcard config to avoid static bind addresses")
		}
	})

	t.Run("stays disabled when wildcard config does not allow auto origin", func(t *testing.T) {
		t.Parallel()

		options, ok, err := resolveOriginDirectOptions(&conf.Options{
			ListenIP: "0.0.0.0",
			SendIP:   "0.0.0.0",
			SingOptions: &conf.SingOptions{
				EnableSameTagOutbound: true,
				AutoSendThroughOrigin: false,
			},
		})
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if ok {
			t.Fatalf("expected disabled result, got enabled: %#v", options)
		}
	})
}
