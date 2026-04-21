package sing

import (
	"sync"
	"testing"

	"github.com/InazumaV/V2bX/common/counter"
	"github.com/InazumaV/V2bX/common/format"
)

func TestGetUserTrafficSliceUsesTaggedUIDMap(t *testing.T) {
	t.Parallel()

	const sharedUUID = "same-uuid"

	tagOneCounter := counter.NewTrafficCounter()
	tagOneCounter.Tx(sharedUUID, 10)
	tagOneCounter.Rx(sharedUUID, 20)

	tagTwoCounter := counter.NewTrafficCounter()
	tagTwoCounter.Tx(sharedUUID, 30)
	tagTwoCounter.Rx(sharedUUID, 40)

	hook := &HookServer{}
	hook.counter.Store("tag-a", tagOneCounter)
	hook.counter.Store("tag-b", tagTwoCounter)

	s := &Sing{
		hookServer: hook,
		users: &UserMap{
			uidMap: map[string]int{
				format.UserTag("tag-a", sharedUUID): 101,
				format.UserTag("tag-b", sharedUUID): 202,
			},
			mapLock: sync.RWMutex{},
		},
		nodeReportMinTrafficBytes: map[string]int64{
			"tag-a": 0,
			"tag-b": 0,
		},
	}

	tagOneTraffic, err := s.GetUserTrafficSlice("tag-a", false)
	if err != nil {
		t.Fatalf("unexpected error for tag-a: %v", err)
	}
	if len(tagOneTraffic) != 1 {
		t.Fatalf("expected one traffic record for tag-a, got %d", len(tagOneTraffic))
	}
	if tagOneTraffic[0].UID != 101 {
		t.Fatalf("unexpected uid for tag-a: %d", tagOneTraffic[0].UID)
	}

	tagTwoTraffic, err := s.GetUserTrafficSlice("tag-b", false)
	if err != nil {
		t.Fatalf("unexpected error for tag-b: %v", err)
	}
	if len(tagTwoTraffic) != 1 {
		t.Fatalf("expected one traffic record for tag-b, got %d", len(tagTwoTraffic))
	}
	if tagTwoTraffic[0].UID != 202 {
		t.Fatalf("unexpected uid for tag-b: %d", tagTwoTraffic[0].UID)
	}
}
