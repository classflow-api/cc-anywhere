// Package presence emits mac_online/mac_offline to phones and phone_count to
// the mac. It does not hold its own state — the hub is the source of truth.
package presence

import (
	"github.com/yoolines/cc-anywhere/internal/protocol"
)

// Broadcaster is the subset of the hub that presence needs. Defined as an
// interface so the hub package can satisfy it without an import cycle.
type Broadcaster interface {
	MacConnSend(env *protocol.Envelope)
	BroadcastToPhones(env *protocol.Envelope)
	PhoneCount() int
	PhoneNames() []string
}

type Service struct {
	hub Broadcaster
}

func New(hub Broadcaster) *Service { return &Service{hub: hub} }

func (s *Service) MacOnline() {
	env, _ := protocol.NewEnvelope(protocol.TypePresenceMacOnline, nil)
	s.hub.BroadcastToPhones(env)
}

func (s *Service) MacOffline() {
	env, _ := protocol.NewEnvelope(protocol.TypePresenceMacOffline, nil)
	s.hub.BroadcastToPhones(env)
}

// PhoneCountChanged notifies the Mac whenever the phone set changes.
func (s *Service) PhoneCountChanged() {
	env, _ := protocol.NewEnvelope(protocol.TypePresencePhoneCount, protocol.PresencePhoneCount{
		Count: s.hub.PhoneCount(),
		Names: s.hub.PhoneNames(),
	})
	s.hub.MacConnSend(env)
}
