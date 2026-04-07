"""3-channel proxy rotation system: DIRECT, DECODO, SMARTPROXY.

Channel weights control ASIN distribution. Ban detection triggers failover
to healthy channels proportionally.
"""
import os
import time
import random
from dataclasses import dataclass, field
from typing import Optional


@dataclass
class ChannelConfig:
    name: str
    url: Optional[str]          # None for direct
    weight: float
    batch_size: int
    enabled: bool = True
    # Health stats
    success_count: int = 0
    fail_count: int = 0
    last_ban: float = 0.0       # epoch seconds
    cooldown_until: float = 0.0 # epoch seconds


class ProxyRotator:
    """Distributes ASINs across DIRECT / DECODO / SMARTPROXY channels.

    Config is driven entirely by env vars so no restart is required for
    weight changes (use reconfigure()).
    """

    COOLDOWN_SECONDS = 3600  # 1 hour ban cooldown

    def __init__(self):
        self.channels: dict[str, ChannelConfig] = {}
        self._pending: dict[str, list[str]] = {}  # channel → remaining ASINs
        self._load_config()

    # ------------------------------------------------------------------
    # Config loading
    # ------------------------------------------------------------------

    def _parse_ratio(self, ratio_str: str) -> dict[str, float]:
        """Parse 'direct:decodo:smart' weight string → dict."""
        parts = ratio_str.split(":")
        if len(parts) != 3:
            raise ValueError(f"PROXY_RATIO must be 'direct:decodo:smart', got: {ratio_str!r}")
        names = ["direct", "decodo", "smart"]
        return {name: float(w) for name, w in zip(names, parts)}

    def _load_config(self):
        ratio_str = os.environ.get("PROXY_RATIO", "5:2.5:2.5")
        weights = self._parse_ratio(ratio_str)

        default_batch = int(os.environ.get("CHANNEL_BATCH_SIZE", "500"))

        self.channels = {
            "direct": ChannelConfig(
                name="direct",
                url=None,
                weight=weights["direct"],
                batch_size=int(os.environ.get("DIRECT_BATCH_SIZE", str(default_batch))),
                enabled=True,
            ),
            "decodo": ChannelConfig(
                name="decodo",
                url=os.environ.get("DECODO_PROXY_URL"),
                weight=weights["decodo"],
                batch_size=int(os.environ.get("DECODO_BATCH_SIZE", str(default_batch))),
                enabled=bool(os.environ.get("DECODO_PROXY_URL")),
            ),
            "smart": ChannelConfig(
                name="smart",
                url=os.environ.get("SMARTPROXY_URL"),
                weight=weights["smart"],
                batch_size=int(os.environ.get("SMART_BATCH_SIZE", str(default_batch))),
                enabled=bool(os.environ.get("SMARTPROXY_URL")),
            ),
        }

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def distribute_asins(
        self, asins: list[str], daily_limit: int = 5000
    ) -> dict[str, list[str]]:
        """Split ASINs across healthy channels by weight.

        Returns dict channel → asin_list.  The sum of all lists equals
        min(len(asins), daily_limit).
        """
        work = asins[:daily_limit]
        healthy = {n: c for n, c in self.channels.items() if c.enabled and not self.is_banned(n)}

        if not healthy:
            return {}

        total_weight = sum(c.weight for c in healthy.values())
        result: dict[str, list[str]] = {n: [] for n in healthy}

        # Weighted round-robin bucket fill
        idx = 0
        for name, cfg in healthy.items():
            share = int(len(work) * cfg.weight / total_weight)
            result[name] = work[idx: idx + share]
            idx += share

        # Remainder goes to the highest-weight channel
        if idx < len(work):
            top = max(healthy, key=lambda n: healthy[n].weight)
            result[top].extend(work[idx:])

        # Store pending so failover can redistribute
        self._pending = {n: list(lst) for n, lst in result.items()}
        return result

    def get_proxy(self, channel: str) -> Optional[str]:
        """Return proxy URL for channel, or None for direct."""
        cfg = self.channels.get(channel)
        if cfg is None:
            return None
        return cfg.url

    def is_banned(self, channel: str) -> bool:
        cfg = self.channels.get(channel)
        if cfg is None:
            return False
        return time.time() < cfg.cooldown_until

    def record_success(self, channel: str) -> None:
        cfg = self.channels.get(channel)
        if cfg:
            cfg.success_count += 1

    def record_failure(self, channel: str, is_ban: bool = False) -> None:
        cfg = self.channels.get(channel)
        if cfg is None:
            return
        cfg.fail_count += 1
        if is_ban:
            cfg.last_ban = time.time()
            cfg.cooldown_until = time.time() + self.COOLDOWN_SECONDS

    def redistribute_from(self, banned_channel: str) -> dict[str, list[str]]:
        """Move remaining ASINs from a banned channel to healthy channels.

        Returns the updated pending dict.
        """
        orphans = self._pending.pop(banned_channel, [])
        if not orphans:
            return self._pending

        healthy = {
            n: c
            for n, c in self.channels.items()
            if n != banned_channel and c.enabled and not self.is_banned(n)
        }
        if not healthy:
            return self._pending  # nowhere to send them

        total_weight = sum(c.weight for c in healthy.values())
        idx = 0
        for name, cfg in healthy.items():
            share = int(len(orphans) * cfg.weight / total_weight)
            self._pending.setdefault(name, []).extend(orphans[idx: idx + share])
            idx += share

        # Remainder
        if idx < len(orphans):
            top = max(healthy, key=lambda n: healthy[n].weight)
            self._pending.setdefault(top, []).extend(orphans[idx:])

        return self._pending

    def reconfigure(self, ratio_str: str) -> None:
        """Hot-reconfigure channel weights without restart."""
        weights = self._parse_ratio(ratio_str)
        for name, w in weights.items():
            if name in self.channels:
                self.channels[name].weight = w

    @property
    def stats(self) -> dict:
        """Per-channel health stats + estimated cost indicator."""
        result = {}
        for name, cfg in self.channels.items():
            total = cfg.success_count + cfg.fail_count
            result[name] = {
                "enabled": cfg.enabled,
                "weight": cfg.weight,
                "batch_size": cfg.batch_size,
                "success_count": cfg.success_count,
                "fail_count": cfg.fail_count,
                "success_rate": cfg.success_count / total if total else None,
                "banned": self.is_banned(name),
                "cooldown_until": cfg.cooldown_until if self.is_banned(name) else None,
                # cost proxy: direct=free, decodo/smart=paid per request
                "is_paid": cfg.url is not None,
            }
        return result
