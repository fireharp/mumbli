"""OpenAI text polishing service.

Takes raw transcription, runs through GPT-4o-mini for light cleanup.
"""

import os

from openai import AsyncOpenAI

POLISHING_PROMPT = """\
You are a text polishing assistant. Clean up this dictated text:
- Remove filler words (um, uh, like, you know)
- Fix grammar and punctuation
- If the speaker corrected themselves (e.g., "at 4, actually 3"), keep only the correction
- Keep the speaker's voice and intent — do NOT rewrite heavily
- Output only the cleaned text, nothing else

Dictated text: {transcription}"""


_client: AsyncOpenAI | None = None


def _get_client() -> AsyncOpenAI:
    global _client
    if _client is None:
        _client = AsyncOpenAI(api_key=os.environ["OPENAI_API_KEY"])
    return _client


async def polish_text(transcription: str) -> str:
    """Run the transcription through GPT-4o-mini for light polishing."""
    if not transcription.strip():
        return ""

    client = _get_client()
    response = await client.chat.completions.create(
        model="gpt-4o-mini",
        messages=[
            {
                "role": "user",
                "content": POLISHING_PROMPT.format(transcription=transcription),
            }
        ],
        temperature=0.3,
        max_tokens=2048,
    )
    return response.choices[0].message.content or transcription
