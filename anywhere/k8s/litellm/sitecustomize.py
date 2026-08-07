"""Runtime monkeypatch for ChatGPT provider non-stream / chat-completions.

Upstream bug (BerriAI/litellm #26309 / #25429 / #29396): the Codex backend
streams real content via ``response.output_item.done``/``output_text.done``
SSE events but sends a terminal ``response.completed`` carrying ``output: []``.
LiteLLM's *streaming* iterator only reads ``response.completed.output``, so the
chat-completions bridge (which forces ``stream=true`` upstream) gets an empty
output and raises ``ChatgptException - Unknown items in responses API
response: []``.

Fix (mirrors upstream PR #31332): accumulate ``output_item.done`` /
``output_text.done`` items while streaming and backfill the completed
response's ``output`` when it arrives empty. Applies only to the ChatGPT
custom provider, preserving the standard OpenAI path untouched.

Applied via sitecustomize so it loads on interpreter startup; idempotent
(guarded by a marker attribute).
"""

import importlib

_sink = importlib.import_module("litellm.responses.streaming_iterator")


def _install() -> None:
    if getattr(_sink, "_opencode_chatgpt_backfill_installed", False):
        return

    orig_process_chunk = _sink.BaseResponsesAPIStreamingIterator._process_chunk
    orig_init = _sink.BaseResponsesAPIStreamingIterator.__init__

    def _init(self, *args, **kwargs):
        orig_init(self, *args, **kwargs)
        self._litellm_chatgpt_streamed_output_items = {}
        # text-only items keyed by output_index for providers that emit only
        # OUTPUT_TEXT_DONE (no OUTPUT_ITEM_DONE) at some indices
        self._litellm_chatgpt_streamed_text_items = {}

    def _process_chunk(self, chunk):
        try:
            event = orig_process_chunk(self, chunk)
        except Exception:
            raise

        if event is None:
            return event

        try:
            provider = (self.custom_llm_provider or "").lower()
            if provider != "chatgpt":
                return event

            event_type = getattr(event, "type", None)
            if event_type == "response.output_item.done":
                item = getattr(event, "item", None)
                if item is not None:
                    index = getattr(event, "output_index", None)
                    if index is None:
                        index = len(self._litellm_chatgpt_streamed_output_items)
                    try:
                        idx = int(index)
                    except (TypeError, ValueError):
                        idx = len(self._litellm_chatgpt_streamed_output_items)
                    self._litellm_chatgpt_streamed_output_items[idx] = (
                        item.model_dump() if hasattr(item, "model_dump") else dict(item)
                    )
            elif event_type in ("response.output_text.done",):
                out_text = getattr(event, "output_text", None)
                if out_text not in (None, ""):
                    index = getattr(event, "output_index", None)
                    if index is None:
                        index = len(self._litellm_chatgpt_streamed_text_items)
                    try:
                        idx = int(index)
                    except (TypeError, ValueError):
                        idx = len(self._litellm_chatgpt_streamed_text_items)
                    self._litellm_chatgpt_streamed_text_items[idx] = out_text
            elif event_type in (
                "response.completed",
                "response.incomplete",
                "response.failed",
            ):
                self._backfill_completed_output()

            return event
        except Exception:
            # Never break the hot path because of patch bookkeeping.
            return event

    def _backfill_completed_output(self):
        completed = getattr(self, "completed_response", None)
        if completed is None:
            return
        response = getattr(completed, "response", None)
        if response is None:
            return
        # Merge text-only items into output-item slots (item wins on collision).
        merged = dict(self._litellm_chatgpt_streamed_text_items)
        merged.update(self._litellm_chatgpt_streamed_output_items)
        if not merged:
            return
        current_output = getattr(response, "output", None)
        # Only backfill when the completed response reports empty/missing output
        # (the failure signal). Preserve a vendor-populated output otherwise.
        if current_output:
            return
        ordered = [merged[i] for i in sorted(merged)]
        try:
            setattr(response, "output", ordered)
        except Exception:
            pass

    _sink.BaseResponsesAPIStreamingIterator._process_chunk = _process_chunk
    _sink.BaseResponsesAPIStreamingIterator.__init__ = _init
    _sink.BaseResponsesAPIStreamingIterator._backfill_completed_output = _backfill_completed_output
    _sink._litellm_chatgpt_backfill_installed = True


_install()