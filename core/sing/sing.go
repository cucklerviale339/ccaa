package sing

import (
	"context"
	"fmt"
	"os"
	"sync"

	"github.com/InazumaV/V2bX/api/panel"
	"github.com/sagernet/sing-box/log"

	"github.com/InazumaV/V2bX/conf"
	vCore "github.com/InazumaV/V2bX/core"
	box "github.com/sagernet/sing-box"
	"github.com/sagernet/sing-box/adapter"
)

var _ vCore.Core = (*Sing)(nil)

type DNSConfig struct {
	Servers []map[string]interface{} `json:"servers"`
	Rules   []map[string]interface{} `json:"rules"`
}

type Sing struct {
	box                       *box.Box
	ctx                       context.Context
	hookServer                *HookServer
	router                    adapter.Router
	logFactory                log.Factory
	users                     *UserMap
	nodeReportMinTrafficBytes map[string]int64
	nodeStates                sync.Map // map[string]*NodeState
	coreConfig                *conf.CoreConfig
	baseConfigData            []byte
	started                   bool
	boxAccess                 sync.Mutex
}

type UserMap struct {
	uidMap  map[string]int
	mapLock sync.RWMutex
}

type NodeState struct {
	info   *panel.NodeInfo
	config *conf.Options
	users  []panel.UserInfo
}

func init() {
	vCore.RegisterCore("sing", New)
}

func New(c *conf.CoreConfig) (vCore.Core, error) {
	var baseConfigData []byte
	if len(c.SingConfig.OriginalPath) != 0 {
		data, err := os.ReadFile(c.SingConfig.OriginalPath)
		if err != nil {
			return nil, fmt.Errorf("read original config error: %s", err)
		}
		baseConfigData = data
	}
	os.Setenv("SING_DNS_PATH", "")
	hs := &HookServer{
		counter: sync.Map{},
	}
	s := &Sing{
		coreConfig:     c,
		baseConfigData: baseConfigData,
		hookServer:     hs,
		users: &UserMap{
			uidMap: make(map[string]int),
		},
		nodeReportMinTrafficBytes: make(map[string]int64),
		nodeStates:                sync.Map{},
	}
	ctx, b, err := s.createBox()
	if err != nil {
		return nil, err
	}
	s.ctx = ctx
	s.box = b
	s.router = b.Router()
	s.logFactory = b.LogFactory()
	return s, nil
}

func (b *Sing) Start() error {
	b.boxAccess.Lock()
	defer b.boxAccess.Unlock()
	if b.started {
		return nil
	}
	if err := b.box.Start(); err != nil {
		return err
	}
	b.started = true
	return nil
}

func (b *Sing) Close() error {
	b.boxAccess.Lock()
	defer b.boxAccess.Unlock()
	if err := b.box.Close(); err != nil {
		return err
	}
	b.started = false
	return nil
}

func (b *Sing) Protocols() []string {
	return []string{
		"vmess",
		"vless",
		"shadowsocks",
		"trojan",
		"tuic",
		"anytls",
		"hysteria",
		"hysteria2",
	}
}

func (b *Sing) Type() string {
	return "sing"
}
