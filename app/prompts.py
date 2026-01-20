"""Shared prompt templates for endurance training program generation."""

SYSTEM_PROMPT = """You are an expert endurance sports coach with 20+ years of experience training athletes for triathlon, running, cycling, duathlon, and aquathlon events.

Your role is to create structured, periodized training programs that include:
- Sport-specific workouts with intervals and intensity zones (swim, bike, run)
- Proper warmup and cooldown protocols
- Progressive overload and recovery weeks

Key principles:

**Intensity Zones**:
- Zone 1: Recovery (very easy)
- Zone 2: Aerobic/Endurance (comfortable)
- Zone 3: Tempo (moderately hard)
- Zone 4: Threshold (hard, sustained)
- Zone 5: VO2 Max (very hard, intervals)

**Periodization**:
- Base Phase (60-70%): Build aerobic base, Zone 2 focus
- Build Phase (20-30%): Add intensity, Zone 3-4
- Peak Phase (5-10%): Race-specific intensity
- Taper Phase (1-2 weeks): Reduce volume, maintain intensity

**Weekly Structure**:
- Monday: Recovery or rest
- Tuesday: Intensity/speed work
- Wednesday: Endurance
- Thursday: Tempo or technique
- Friday: Easy or rest
- Saturday: Long session
- Sunday: Long session or brick/transition workout (for multi-sport)

You must respond with valid JSON matching the TrainingProgram schema."""


RACE_DISTANCES = {
    # Triathlon
    "sprint": "Sprint Triathlon (750m swim, 20km bike, 5km run)",
    "olympic": "Olympic Triathlon (1.5km swim, 40km bike, 10km run)",
    "half_ironman": "Half Ironman (1.9km swim, 90km bike, 21.1km run)",
    "full_ironman": "Full Ironman (3.8km swim, 180km bike, 42.2km run)",
    # Running
    "5k": "5K Run",
    "10k": "10K Run",
    "half_marathon": "Half Marathon",
    "marathon": "Marathon",
    "ultra_50k": "Ultra Marathon 50K",
    "ultra_100k": "Ultra Marathon 100K",
    # Cycling
    "century": "Century Ride (100 miles / 160km)",
    "gran_fondo": "Gran Fondo (100-200km)",
    "double_century": "Double Century (200 miles / 320km)",
    # Duathlon
    "duathlon_sprint": "Sprint Duathlon (5km run, 20km bike, 2.5km run)",
    "duathlon_standard": "Standard Duathlon (10km run, 40km bike, 5km run)",
    "duathlon_long": "Long Duathlon (10km run, 60km bike, 10km run)",
    # Aquathlon
    "aquathlon_sprint": "Sprint Aquathlon (750m swim, 5km run)",
    "aquathlon_standard": "Standard Aquathlon (1km swim, 5km run)",
}


def build_user_prompt(request, concise: bool = False) -> str:
    """Build user prompt for workout generation.
    
    Args:
        request: WorkoutRequest with training parameters
        concise: If True, use shorter descriptions (for smaller models)
    """
    # Handle both enum and string values
    goal_value = request.goal.value if hasattr(request.goal, 'value') else request.goal
    sport_type_value = request.sport_type.value if hasattr(request.sport_type, 'value') else request.sport_type
    race_distance = RACE_DISTANCES.get(goal_value, goal_value)
    
    # Determine which sports to include based on sport type
    sport_guidance = {
        "triathlon": "Include swim, bike, and run workouts. Add brick workouts (bike-to-run transitions).",
        "running": "Include ONLY run workouts. Focus on varied paces, intervals, tempo runs, and long runs.",
        "cycling": "Include ONLY bike workouts. Focus on endurance rides, intervals, hill work, and tempo efforts.",
        "duathlon": "Include bike and run workouts. Add brick workouts (bike-to-run transitions). NO swimming.",
        "aquathlon": "Include swim and run workouts. Add transition workouts (swim-to-run). NO cycling.",
    }
    
    sports_to_include = sport_guidance.get(sport_type_value, sport_guidance["triathlon"])
    
    prompt = f"""Create a {request.duration_weeks}-week training program:

**Sport Type**: {sport_type_value.title()}
**Goal**: {race_distance}
**Fitness Level**: {request.fitness_level.value}
**Available Time**: {request.available_hours_per_week} hours/week
**Current Week**: {request.current_week}
**Sports**: {sports_to_include}
"""
    
    if request.focus_areas:
        prompt += f"**Focus Areas**: {', '.join(request.focus_areas)}\n"
    
    if concise:
        prompt += """
**JSON Format** (keep descriptions brief, 5-10 words):
```json
{
  "goal": "sprint",
  "fitness_level": "beginner",
  "duration_weeks": 12,
  "weeks": [
    {
      "week_number": 1,
      "focus": "Base Building",
      "workouts": [
        {
          "sport": "swim",
          "title": "Easy Swim",
          "day": "Tuesday",
          "is_rest_day": false,
          "total_duration_minutes": 45,
          "total_distance_km": 1.5,
          "warmup": "10 min easy",
          "main_set": [{"duration_minutes": 25, "distance_km": 1.0, "intensity": "Zone 2", "description": "Steady swim"}],
          "cooldown": "10 min easy",
          "notes": "Focus on technique"
        }
      ],
      "weekly_volume_hours": 6.5,
      "weekly_distance_km": 50.0
    }
  ],
  "notes": "Program overview"
}
```

**CRITICAL**:
1. Create 5-6 workouts per week
2. Distribute workouts across DIFFERENT days (Monday-Sunday)
3. Include swim, bike, run
4. Keep all descriptions under 10 words
5. Include 1 rest day per week (is_rest_day: true, total_duration_minutes: 0)
6. Return ONLY valid JSON
"""
    else:
        prompt += """
**JSON Format**:
```json
{
  "goal": "sprint",
  "fitness_level": "beginner",
  "duration_weeks": 12,
  "weeks": [
    {
      "week_number": 1,
      "focus": "Base Building",
      "workouts": [
        {
          "sport": "swim|bike|run",
          "title": "Workout Title",
          "day": "Monday",
          "is_rest_day": false,
          "total_duration_minutes": 60,
          "total_distance_km": 5.0,
          "warmup": "10 min easy, drills",
          "main_set": [
            {
              "duration_minutes": 30,
              "distance_km": 3.0,
              "intensity": "Zone 2",
              "description": "Continuous aerobic effort"
            }
          ],
          "cooldown": "10 min easy",
          "notes": "Focus on form"
        },
        {
          "sport": "swim",
          "title": "Rest Day",
          "day": "Friday",
          "is_rest_day": true,
          "total_duration_minutes": 0,
          "warmup": "",
          "main_set": [],
          "cooldown": "",
          "notes": "Complete rest"
        }
      ],
      "weekly_volume_hours": 6.5,
      "weekly_distance_km": 50.0
    }
  ],
  "notes": "Program overview and key focus areas"
}
```

**CRITICAL REQUIREMENTS**:
1. Create 5-7 workouts per week
2. **IMPORTANT**: Assign each workout to a DIFFERENT day of the week
   - Use "day": "Monday", "Tuesday", "Wednesday", etc.
   - DO NOT put multiple workouts on the same day
   - Spread workouts evenly across the week
3. **SPORT VALUES**: Use ONLY "swim", "bike", or "run" for the sport field based on the sport type
   - For triathlon: Include all three sports (swim, bike, run)
   - For running: Use ONLY "run"
   - For cycling: Use ONLY "bike"
   - For duathlon: Use "bike" and "run" only (NO swim)
   - For aquathlon: Use "swim" and "run" only (NO bike)
   - For brick/transition workouts, use the primary sport (e.g., "bike" for bike-to-run)
   - For rest days, use any valid sport and set is_rest_day: true
4. Include sport-appropriate workouts based on the sport type
5. Each workout must have specific intervals with intensity zones
6. For multi-sport events (triathlon, duathlon, aquathlon), include at least one brick/transition workout per week
7. Progressive volume with recovery weeks every 3-4 weeks
8. Include at least 1 rest day per week (is_rest_day: true, total_duration_minutes: 0)
9. Order workouts by day (Monday first, Sunday last)
10. Return ONLY the JSON, no markdown or extra text
"""
    
    return prompt
