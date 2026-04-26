"""
Agent tests demonstrating LangGraph-like testing patterns with deterministic fakes.
- Component testing with FakeLLM-equivalent
- Golden snapshot testing
- Conversation history
- Error handling via portable ErrorLLM
"""

import json

import pytest


# Minimal LLM fakes (avoid version-specific FakeLLM behavior)
class SimpleLLM:
    def __init__(self, responses):
        self._responses = list(responses)

    def invoke(self, _input):
        if not self._responses:
            raise RuntimeError("No LLM responses left")
        return self._responses.pop(0)


class ErrorLLM:
    def invoke(self, _input):
        raise RuntimeError("Service unavailable")


# Example agent under test
class BookingAgent:
    def __init__(self, llm):
        self.llm = llm
        self.history = []

    def run(self, input: str):
        self.history.append(input)
        try:
            llm_response = self.llm.invoke(input)
        except Exception as e:
            return {"status": "error", "message": f"LLM error: {str(e)}", "retry": True}

        return {
            "status": "complete",
            "intent": "book_flight",
            "message": llm_response,
            "history_count": len(self.history),
        }


@pytest.mark.component
@pytest.mark.agents
def test_agent_extracts_user_intent():
    agent = BookingAgent(llm=SimpleLLM(responses=["User wants to book a flight to NYC"]))
    result = agent.run(input="I need to fly to NYC tomorrow")
    assert result["status"] == "complete"
    assert result["intent"] == "book_flight"
    assert "NYC" in result["message"]


@pytest.mark.component
@pytest.mark.agents
def test_agent_handles_llm_error():
    agent = BookingAgent(llm=ErrorLLM())
    result = agent.run(input="Book flight to NYC")
    assert result["status"] == "error"
    assert "error" in result["message"].lower()
    assert result["retry"] is True


@pytest.mark.component
@pytest.mark.agents
def test_agent_maintains_conversation_history():
    agent = BookingAgent(llm=SimpleLLM(responses=["A", "B", "C"]))
    assert agent.run("one")["history_count"] == 1
    assert agent.run("two")["history_count"] == 2
    assert agent.run("three")["history_count"] == 3


@pytest.mark.golden
@pytest.mark.agents
def test_agent_output_format(golden):
    agent = BookingAgent(llm=SimpleLLM(responses=["Flight booking confirmed for NYC"]))
    result = agent.run(input="Book flight to NYC tomorrow")
    golden.assert_match(json.dumps(result, indent=2, sort_keys=True), "agent_booking_output.json")


@pytest.mark.component
@pytest.mark.agents
@pytest.mark.p0
def test_critical_agent_workflow():
    agent = BookingAgent(llm=SimpleLLM(responses=["Booking confirmed"]))
    result = agent.run(input="Book flight")
    assert result["status"] == "complete"
