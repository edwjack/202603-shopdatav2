"""Adaptive per-channel rate limiting for the scraper.

Delays auto-adjust based on consecutive success/failure streaks:
- 5 consecutive successes → speed up (×0.85, floor 10s direct / 8s proxy)
- 1 CAPTCHA/block       → slow down (×1.5 + 0–3s jitter, ceiling 45s)
- 3 consecutive blocks  → should_pause returns True
"""
import random
from dataclasses import dataclass, field

from scraper.config import RATE_LIMITS


# Per-channel delay floors (seconds)
_FLOOR = {
    "direct": 10.0,
    "decodo": 8.0,
    "smart": 8.0,
}
_CEILING = 45.0
_DEFAULT_FLOOR = 8.0


@dataclass
class ChannelState:
    base_delay: float
    current_delay: float = field(init=False)
    consecutive_success: int = 0
    consecutive_fail: int = 0

    def __post_init__(self):
        self.current_delay = self.base_delay


class AdaptiveRateLimiter:
    """Maintains independent delay state for each scraping channel."""

    def __init__(self):
        base = RATE_LIMITS["amazon"]["mean"]  # default 18 s
        self._states: dict[str, ChannelState] = {}
        self._base_delay = base

    def _get_state(self, channel: str) -> ChannelState:
        if channel not in self._states:
            self._states[channel] = ChannelState(base_delay=self._base_delay)
        return self._states[channel]

    def record_success(self, channel: str) -> None:
        state = self._get_state(channel)
        state.consecutive_success += 1
        state.consecutive_fail = 0

        if state.consecutive_success >= 5:
            floor = _FLOOR.get(channel, _DEFAULT_FLOOR)
            state.current_delay = max(floor, state.current_delay * 0.85)
            state.consecutive_success = 0  # reset streak counter after adjustment

    def record_failure(self, channel: str, is_ban: bool = False) -> None:
        state = self._get_state(channel)
        state.consecutive_fail += 1
        state.consecutive_success = 0

        # Any CAPTCHA or block → back off
        jitter = random.uniform(0, 3)
        state.current_delay = min(_CEILING, state.current_delay * 1.5 + jitter)

    def get_delay(self, channel: str) -> float:
        return self._get_state(channel).current_delay

    def should_pause(self, channel: str) -> bool:
        """Return True when 3+ consecutive blocks have been recorded."""
        return self._get_state(channel).consecutive_fail >= 3

    def reset(self, channel: str) -> None:
        """Reset channel state back to base delay."""
        if channel in self._states:
            state = self._states[channel]
            state.current_delay = state.base_delay
            state.consecutive_success = 0
            state.consecutive_fail = 0
