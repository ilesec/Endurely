"""Agent implementation using Azure AI Studio (Azure OpenAI-compatible endpoint)."""
from typing import Dict, Any
from openai import AzureOpenAI
import json
from azure.identity import DefaultAzureCredential

from app.config import settings
from app.utils import assign_weekdays_to_workouts
from app.prompts import SYSTEM_PROMPT, build_user_prompt
from app.models import WorkoutRequest, TrainingProgram


class TriathlonWorkoutAgentAzureAI:
    """AI Agent using Azure AI Studio (model determined by deployment name)."""
    
    def __init__(self):
        if not settings.azure_ai_endpoint:
            raise ValueError("AZURE_AI_ENDPOINT is required when LLM_PROVIDER=azure_ai")

        auth_mode = (settings.azure_ai_auth or "api_key").lower().strip()
        if auth_mode in {"entra_id", "aad", "managed_identity", "mi"}:
            credential = DefaultAzureCredential(
                managed_identity_client_id=settings.azure_ai_managed_identity_client_id
            )

            def token_provider() -> str:
                token = credential.get_token("https://cognitiveservices.azure.com/.default")
                return token.token

            self.client = AzureOpenAI(
                azure_endpoint=settings.azure_ai_endpoint,
                azure_ad_token_provider=token_provider,
                api_version=settings.azure_ai_api_version,
            )
        else:
            if not settings.azure_ai_api_key:
                raise ValueError(
                    "AZURE_AI_API_KEY is required when AZURE_AI_AUTH=api_key"
                )
            self.client = AzureOpenAI(
                azure_endpoint=settings.azure_ai_endpoint,
                api_key=settings.azure_ai_api_key,
                api_version=settings.azure_ai_api_version,
            )

        if not settings.azure_ai_deployment_name:
            raise ValueError(
                "AZURE_AI_DEPLOYMENT_NAME is required when LLM_PROVIDER=azure_ai"
            )
        self.deployment_name = settings.azure_ai_deployment_name

    def _create_chat_completion(
        self,
        *,
        messages: list[dict[str, str]],
        temperature: float | None,
        max_output_tokens: int,
        json_object: bool = True,
    ):
        """Create a chat completion with cross-model token-parameter compatibility.

        Some newer models (including GPT-5 family) require `max_completion_tokens`
        instead of `max_tokens`.
        """

        common_kwargs: dict[str, Any] = {
            "model": self.deployment_name,
            "messages": messages,
        }

        # When supported, JSON mode makes the model return a single JSON object.
        if json_object:
            common_kwargs["response_format"] = {"type": "json_object"}

        # Some models only support the default temperature (1) and reject any explicit value.
        if temperature is not None:
            common_kwargs["temperature"] = temperature

        def _call_with_max_completion_tokens(kwargs: dict[str, Any]):
            return self.client.chat.completions.create(
                **kwargs,
                max_completion_tokens=max_output_tokens,
            )

        def _call_with_max_tokens(kwargs: dict[str, Any]):
            return self.client.chat.completions.create(
                **kwargs,
                max_tokens=max_output_tokens,
            )

        effective_kwargs = common_kwargs

        try:
            return _call_with_max_completion_tokens(effective_kwargs)
        except Exception as exc:  # pragma: no cover
            message = str(exc)

            # Retry without temperature if the model only accepts default temperature.
            if "Unsupported value" in message and "temperature" in message:
                effective_kwargs = dict(effective_kwargs)
                effective_kwargs.pop("temperature", None)
                try:
                    return _call_with_max_completion_tokens(effective_kwargs)
                except Exception as exc2:  # pragma: no cover
                    message = str(exc2)

            # Retry without JSON mode if the model/endpoint doesn't support it.
            if (
                "response_format" in effective_kwargs
                and ("Unsupported parameter" in message or "Unrecognized request argument" in message)
                and "response_format" in message
            ):
                effective_kwargs = dict(effective_kwargs)
                effective_kwargs.pop("response_format", None)
                return _call_with_max_completion_tokens(effective_kwargs)

            if "Unsupported parameter" in message and "max_completion_tokens" in message:
                return _call_with_max_tokens(effective_kwargs)
            if "Unsupported parameter" in message and "max_tokens" in message:
                return _call_with_max_completion_tokens(effective_kwargs)
            raise
    
    def _extract_json_object_text(self, content: str) -> str:
        """Extract JSON from response, removing markdown and extra text."""
        content = (content or "").strip()

        # Remove markdown code blocks if present.
        if "```json" in content:
            content = content.split("```json")[1].split("```")[0].strip()
        elif "```" in content:
            content = content.split("```", 1)[1].split("```")[0].strip()

        # If there's leading/trailing chatter, extract the first JSON object.
        first_brace = content.find("{")
        last_brace = content.rfind("}")
        if first_brace != -1 and last_brace != -1 and last_brace > first_brace:
            content = content[first_brace : last_brace + 1]

        return content
    
    def generate_program(self, request: WorkoutRequest) -> TrainingProgram:
        """Generate a complete training program using Azure AI."""
        # For longer programs (>6 weeks), generate week-by-week to avoid token limits
        if request.duration_weeks > 6:
            return self._generate_program_progressive(request)
        
        response = self._create_chat_completion(
            messages=[
                {"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user", "content": build_user_prompt(request, concise=True)},
            ],
            temperature=None,
            max_output_tokens=16000,
            json_object=True,
        )

        choice = response.choices[0]
        raw_content = getattr(choice.message, "content", None)
        finish_reason = getattr(choice, "finish_reason", None)

        # Extract the JSON from the response
        content = self._extract_json_object_text(raw_content or "")

        if not content.strip():
            raise ValueError(
                "Model returned no content. "
                f"finish_reason={finish_reason!r}. "
                "This can happen with auth/deployment issues, content filtering, or unsupported parameters."
            )
        
        # Check if we hit the length limit and got truncated JSON
        if finish_reason == "length":
            raise ValueError(
                f"Model hit token limit (finish_reason='length'). "
                f"Received {len(content)} chars but JSON may be incomplete. "
                f"Try: 1) Reduce duration_weeks (currently {request.duration_weeks}), "
                f"2) Increase max_output_tokens (currently 16000), "
                f"or 3) Use a model with larger output capacity."
            )
        
        # Parse JSON and validate with Pydantic
        try:
            program_data = json.loads(content)
        except json.JSONDecodeError as exc:
            preview = content[:800].replace("\n", "\\n")
            raise ValueError(
                "Model did not return valid JSON. "
                f"First 800 chars: {preview!r}"
            ) from exc
        
        # Auto-assign weekdays if the AI didn't provide them
        program_data = assign_weekdays_to_workouts(program_data)
        
        program = TrainingProgram(**program_data)
        
        return program
    
    def _generate_program_progressive(self, request: WorkoutRequest) -> TrainingProgram:
        """Generate a program week-by-week for longer training plans."""
        from app.models import WeekPlan
        from app.prompts import RACE_DISTANCES
        
        # Determine periodization phases
        total_weeks = request.duration_weeks
        base_weeks = int(total_weeks * 0.6)
        build_weeks = int(total_weeks * 0.25)
        peak_weeks = max(1, int(total_weeks * 0.1))
        taper_weeks = total_weeks - base_weeks - build_weeks - peak_weeks
        
        weeks = []
        week_num = 1
        
        # Generate each week
        for phase_name, phase_weeks in [
            ("Base", base_weeks),
            ("Build", build_weeks),
            ("Peak", peak_weeks),
            ("Taper", taper_weeks)
        ]:
            for i in range(phase_weeks):
                week_data = self.generate_single_week(
                    request=request,
                    week_number=week_num,
                    phase=phase_name
                )
                weeks.append(WeekPlan(**week_data))
                week_num += 1
        
        # Build complete program
        program = TrainingProgram(
            goal=request.goal,
            fitness_level=request.fitness_level,
            duration_weeks=request.duration_weeks,
            weeks=weeks,
            notes=f"{request.duration_weeks}-week {request.goal.value} program with {base_weeks}w base, {build_weeks}w build, {peak_weeks}w peak, {taper_weeks}w taper phases"
        )
        
        return program
    
    def generate_single_week(
        self, 
        request: WorkoutRequest,
        week_number: int,
        phase: str
    ) -> Dict[str, Any]:
        """Generate a single week of training (useful for ongoing programs)."""
        from app.prompts import RACE_DISTANCES
        
        goal_value = request.goal.value if hasattr(request.goal, 'value') else request.goal
        race_distance = RACE_DISTANCES.get(goal_value, goal_value)
        
        prompt = f"""Create Week {week_number} of a {request.duration_weeks}-week {race_distance} training program.

**Phase**: {phase}
**Fitness Level**: {request.fitness_level.value}
**Available Hours**: {request.available_hours_per_week} hours/week

Return a JSON object with this structure (be CONCISE in descriptions):
```json
{{
  "week_number": {week_number},
  "focus": "{phase} Training",
  "workouts": [
    {{
      "sport": "swim|bike|run",
      "title": "Brief title",
      "total_duration_minutes": 60,
      "total_distance_km": 5.0,
      "warmup": "Brief description",
      "main_set": [
        {{
          "duration_minutes": 30,
          "distance_km": 3.0,
          "intensity": "Zone 2",
          "description": "Brief description"
        }}
      ],
      "cooldown": "Brief description",
      "notes": "Brief notes"
    }}
  ],
  "weekly_volume_hours": 6.5,
  "weekly_distance_km": 45.0
}}
```

Create 5-6 workouts. Include swim, bike, run. Keep descriptions under 10 words. Return ONLY valid JSON.
"""
        
        response = self._create_chat_completion(
            messages=[
                {"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user", "content": prompt},
            ],
            temperature=None,
            max_output_tokens=3000,
            json_object=True,
        )
        
        content = self._extract_json_object_text(response.choices[0].message.content)

        try:
            week_data = json.loads(content)
            # Auto-assign weekdays if missing
            week_data = assign_weekdays_to_workouts({"weeks": [week_data]})["weeks"][0]
            return week_data
        except json.JSONDecodeError as exc:
            preview = content[:800].replace("\n", "\\n")
            raise ValueError(
                "Model did not return valid JSON. "
                f"First 800 chars: {preview!r}"
            ) from exc
