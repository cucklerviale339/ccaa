package sing

import (
	"errors"

	"github.com/InazumaV/V2bX/api/panel"
	"github.com/InazumaV/V2bX/common/counter"
	"github.com/InazumaV/V2bX/common/format"
	"github.com/InazumaV/V2bX/core"
)

func (b *Sing) AddUsers(p *core.AddUsersParams) (added int, err error) {
	stateValue, ok := b.nodeStates.Load(p.Tag)
	if !ok {
		return 0, errors.New("the inbound not found")
	}
	state := stateValue.(*NodeState)

	b.users.mapLock.Lock()
	for i := range p.Users {
		b.users.uidMap[format.UserTag(p.Tag, p.Users[i].Uuid)] = p.Users[i].Id
	}
	mergedUsers := make([]panel.UserInfo, 0, len(state.users)+len(p.Users))
	seen := make(map[string]panel.UserInfo, len(state.users)+len(p.Users))
	for _, user := range state.users {
		seen[user.Uuid] = user
	}
	for _, user := range p.Users {
		seen[user.Uuid] = user
	}
	for _, user := range state.users {
		if current, exists := seen[user.Uuid]; exists {
			mergedUsers = append(mergedUsers, current)
			delete(seen, user.Uuid)
		}
	}
	for _, user := range p.Users {
		if current, exists := seen[user.Uuid]; exists {
			mergedUsers = append(mergedUsers, current)
			delete(seen, user.Uuid)
		}
	}
	state.users = mergedUsers
	b.users.mapLock.Unlock()

	if err = b.rebuildInbound(p.Tag); err != nil {
		return 0, err
	}
	return len(p.Users), nil
}

func (b *Sing) GetUserTraffic(tag, uuid string, reset bool) (up int64, down int64) {
	if v, ok := b.hookServer.counter.Load(tag); ok {
		c := v.(*counter.TrafficCounter)
		up = c.GetUpCount(uuid)
		down = c.GetDownCount(uuid)
		if reset {
			c.Reset(uuid)
		}
		return
	}
	return 0, 0
}

func (b *Sing) GetUserTrafficSlice(tag string, reset bool) ([]panel.UserTraffic, error) {
	trafficSlice := make([]panel.UserTraffic, 0)
	hook := b.hookServer
	b.users.mapLock.RLock()
	defer b.users.mapLock.RUnlock()
	if v, ok := hook.counter.Load(tag); ok {
		c := v.(*counter.TrafficCounter)
		c.Counters.Range(func(key, value interface{}) bool {
			uuid := key.(string)
			userTag := format.UserTag(tag, uuid)
			traffic := value.(*counter.TrafficStorage)
			up := traffic.UpCounter.Load()
			down := traffic.DownCounter.Load()
			if up+down > b.nodeReportMinTrafficBytes[tag] {
				if reset {
					traffic.UpCounter.Store(0)
					traffic.DownCounter.Store(0)
				}
				if b.users.uidMap[userTag] == 0 {
					c.Delete(uuid)
					return true
				}
				trafficSlice = append(trafficSlice, panel.UserTraffic{
					UID:      b.users.uidMap[userTag],
					Upload:   up,
					Download: down,
				})
			}
			return true
		})
		if len(trafficSlice) == 0 {
			return nil, nil
		}
		return trafficSlice, nil
	}
	return nil, nil
}

func (b *Sing) DelUsers(users []panel.UserInfo, tag string, _ *panel.NodeInfo) error {
	stateValue, ok := b.nodeStates.Load(tag)
	if !ok {
		return errors.New("the inbound not found")
	}
	state := stateValue.(*NodeState)

	b.users.mapLock.Lock()
	deleted := make(map[string]struct{}, len(users))
	for i := range users {
		if v, ok := b.hookServer.counter.Load(tag); ok {
			c := v.(*counter.TrafficCounter)
			c.Delete(users[i].Uuid)
		}
		delete(b.users.uidMap, format.UserTag(tag, users[i].Uuid))
		deleted[users[i].Uuid] = struct{}{}
	}

	remainingUsers := make([]panel.UserInfo, 0, len(state.users))
	for _, user := range state.users {
		if _, exists := deleted[user.Uuid]; !exists {
			remainingUsers = append(remainingUsers, user)
		}
	}
	state.users = remainingUsers
	b.users.mapLock.Unlock()

	return b.rebuildInbound(tag)
}
