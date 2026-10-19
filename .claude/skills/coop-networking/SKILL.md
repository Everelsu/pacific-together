---
name: coop-networking
description: Choose and implement networking for a co-op mod: sync model, transport library, and a way for friends to connect without port forwarding (Steam Spacewar relay, EOS, VPN), plus wrapping an existing UDP netcode in a relay.
---

# Co-op networking

- Sync model: host-authoritative state sync for most single-player engines; lockstep only for deterministic games.
- Transport: ENet, GameNetworkingSockets, Steam Networking Messages, EOS P2P, LiteNetLib, or the engine's own netcode.
- No port forwarding: Steam relay via AppID 480 (players run Steam, appear as "playing Spacewar"); a mock `steam_api.dll` for one-PC tests.
- Existing UDP netcode: a local relay next to the game, one socket per remote connection on the host, connection ids so reconnects on map change work.
- Always test with lag and loss emulation.

Details: `coop-anything/playbook/networking.md`, `coop-anything/playbook/networking-steam-spacewar.md`.
