"""Small, bounded single-process counters; authentication groups stay separate."""
from collections import OrderedDict, deque
from threading import Lock
import time


class AuthLimits:
    def __init__(self, clock=None):
        self.clock = clock or time.monotonic
        self.buckets = OrderedDict()
        self.lock = Lock()

    def allow(self, operation, principal, limit, window=60):
        now = self.clock()
        key = (operation, principal)
        with self.lock:
            if len(self.buckets) >= 4096:
                for old in [k for k, q in self.buckets.items() if not q or q[-1] <= now - window]:
                    self.buckets.pop(old, None)
            queue = self.buckets.setdefault(key, deque())
            self.buckets.move_to_end(key)
            while queue and queue[0] <= now - window:
                queue.popleft()
            if len(queue) >= limit:
                return False
            queue.append(now)
            while len(self.buckets) > 8192:
                self.buckets.popitem(last=False)
            return True
