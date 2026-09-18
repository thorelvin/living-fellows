"""
Single-flight command broker.

BF-02. Every POST used to replace `cmd.txt` outright while the mod polled it a
few times a second, so two accepted requests could overwrite each other before
the game ever read the first. The file write was locked, but the *slot* was not
reserved until consumption, and a browser that lost its HTTP response had no way
to find out what happened.

This owns exactly one outstanding gameplay command. It is deliberately not a job
queue: the product controls one radio, and a second in-flight command is an
error rather than something to schedule.

Guarantees, stated precisely:

  * Admission is serialized. Authentication, validation, duplicate lookup,
    freshness, the busy check and the reservation all happen under one lock.
    Checking `busy` outside the lock and only locking the file write is what
    allowed the overwrite.
  * The same request id with the same payload returns the original receipt.
    The same id with a different payload is refused.
  * A receipt survives the response. A browser that slept through the result
    can fetch it by id.
  * The active receipt is persisted before the command is emitted, so a crash
    around file replacement is reconciled rather than forgotten.

It does NOT promise exactly-once execution across arbitrary crashes. An expired
idempotency record is not proof that its command never ran, which is why the
retention window is explicit and a reconciled-but-unresolved command reports
`unknown` rather than silently freeing the slot.
"""

from __future__ import annotations

import json
import threading
import time
from pathlib import Path

# Outcomes that mean the command can no longer execute, so the slot is free.
TERMINAL = {"applied", "rejected", "expired", "cancelled", "superseded"}
# Outcomes that mean work may still be happening.
IN_FLIGHT = {"emitted", "queued", "running"}

RECEIPT_RETENTION = 64
RECEIPT_TTL_SECONDS = 600
# How long an unread envelope stays acceptable to the mod.
ACCEPTANCE_WINDOW_MS = 4000


class Busy(Exception):
    """Another command is still capable of executing."""

    def __init__(self, active_id: str) -> None:
        super().__init__("busy")
        self.active_id = active_id


class Conflict(Exception):
    """Same request id, different payload."""


class Broker:
    def __init__(self, mailbox, state_path: Path) -> None:
        self._mailbox = mailbox
        self._state_path = state_path
        self._lock = threading.RLock()
        self._receipts: dict[str, dict] = {}
        self._order: list[str] = []
        self._active: str | None = None
        self._reconcile_on_start()

    # ------------------------------------------------------------- receipts

    def _put(self, receipt: dict) -> None:
        rid = receipt["request_id"]
        if rid not in self._receipts:
            self._order.append(rid)
        self._receipts[rid] = receipt
        while len(self._order) > RECEIPT_RETENTION:
            oldest = self._order.pop(0)
            # Never evict the active command: losing it would let a second
            # command in while the first can still execute.
            if oldest == self._active:
                self._order.append(oldest)
                break
            self._receipts.pop(oldest, None)

    def receipt(self, request_id: str) -> dict | None:
        with self._lock:
            found = self._receipts.get(request_id)
            return dict(found) if found else None

    def receipts(self) -> list[dict]:
        with self._lock:
            return [dict(self._receipts[r]) for r in self._order if r in self._receipts]

    # -------------------------------------------------------- crash recovery

    def _reconcile_on_start(self) -> None:
        """A receipt on disk means a command was emitted and its outcome was
        never established. It is not assumed to have failed."""
        try:
            saved = json.loads(self._state_path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return
        if not isinstance(saved, dict) or "request_id" not in saved:
            return
        saved["status"] = "unknown"
        saved["reason"] = "host_restarted_before_outcome"
        saved["reconciled"] = True
        self._receipts[saved["request_id"]] = saved
        self._order.append(saved["request_id"])
        # Deliberately left active: until the game reports what happened, the
        # host must not admit a second command.
        self._active = saved["request_id"]

    def _persist_active(self, receipt: dict | None) -> None:
        try:
            if receipt is None:
                self._state_path.unlink(missing_ok=True)
            else:
                temp = self._state_path.with_suffix(".tmp")
                temp.write_text(json.dumps(receipt), encoding="utf-8")
                temp.replace(self._state_path)
        except OSError:
            pass  # persistence is best effort; never fail a command over it

    # ------------------------------------------------------------ admission

    def admit(self, request_id: str, payload_key: str, envelope_builder) -> dict:
        """Reserve the slot and emit one command. Returns its receipt.

        `envelope_builder(sequence, deadline_ms)` returns the pairs to frame.
        Raises Busy or Conflict.
        """
        with self._lock:
            existing = self._receipts.get(request_id)
            if existing is not None:
                if existing.get("payload_key") != payload_key:
                    raise Conflict("request id reused with a different command")
                return dict(existing)

            if self._active is not None:
                active = self._receipts.get(self._active)
                if active and active.get("status") in TERMINAL:
                    self._active = None
                    self._persist_active(None)
                else:
                    raise Busy(self._active)

            deadline_ms = int(time.time() * 1000) + ACCEPTANCE_WINDOW_MS
            receipt = {
                "request_id": request_id,
                "payload_key": payload_key,
                "status": "emitted",
                "reason": "",
                "created": time.time(),
                "deadline_ms": deadline_ms,
                "sequence": None,
            }
            # Persisted BEFORE emission: a crash between write and reply must
            # leave evidence that a command may have been delivered.
            self._active = request_id
            self._persist_active(receipt)

            try:
                sequence = self._mailbox.send_command(
                    envelope_builder(deadline_ms), request_id
                )
            except OSError as error:
                receipt["status"] = "unknown"
                receipt["reason"] = f"write_failed:{type(error).__name__}"
                self._put(receipt)
                # The write may have partially landed; do not free the slot on
                # the assumption that nothing happened.
                self._persist_active(receipt)
                return dict(receipt)

            receipt["sequence"] = sequence
            self._put(receipt)
            self._persist_active(receipt)
            return dict(receipt)

    # ------------------------------------------------------------- outcomes

    def apply_results(self, results: list[dict], watermark: int | None) -> None:
        """Fold the mod's reported outcomes into the receipts."""
        with self._lock:
            for result in results:
                rid = result.get("id")
                if not rid:
                    continue
                receipt = self._receipts.get(rid)
                if receipt is None:
                    continue
                status = result.get("status") or "unknown"
                receipt["status"] = status
                receipt["reason"] = result.get("reason", "")
                if status in TERMINAL and self._active == rid:
                    self._active = None
                    self._persist_active(None)

            # A reconciled receipt whose command was never consumed by the game
            # can be released: the watermark proves the mod moved past it.
            if self._active is not None and watermark is not None:
                receipt = self._receipts.get(self._active)
                if receipt and receipt.get("reconciled") and receipt.get("sequence") is not None:
                    if watermark >= receipt["sequence"]:
                        receipt["status"] = "unknown"
                        receipt["reason"] = "consumed_before_restart"
                        self._active = None
                        self._persist_active(None)

    def expire_stale(self) -> None:
        """Release the slot when an emitted command's acceptance window has
        passed and the mod never reported it. The command cannot execute after
        its deadline, because the mod rejects an expired envelope."""
        with self._lock:
            if self._active is None:
                return
            receipt = self._receipts.get(self._active)
            if receipt is None:
                self._active = None
                return
            if receipt.get("status") not in ("emitted",):
                return
            if receipt.get("reconciled"):
                return
            if int(time.time() * 1000) > receipt.get("deadline_ms", 0) + 1000:
                receipt["status"] = "expired"
                receipt["reason"] = "not_consumed_before_deadline"
                self._active = None
                self._persist_active(None)

            cutoff = time.time() - RECEIPT_TTL_SECONDS
            for rid in list(self._order):
                entry = self._receipts.get(rid)
                if entry and rid != self._active and entry.get("created", 0) < cutoff:
                    self._order.remove(rid)
                    self._receipts.pop(rid, None)

    @property
    def active(self) -> str | None:
        with self._lock:
            return self._active
