from enum import Enum
from typing import List, Optional
from pydantic import BaseModel, Field, field_validator


class Sport(str, Enum):
    SWIM = "swim"
    BIKE = "bike"
    RUN = "run"


class Weekday(str, Enum):
    MONDAY = "Monday"
    TUESDAY = "Tuesday"
    WEDNESDAY = "Wednesday"
    THURSDAY = "Thursday"
    FRIDAY = "Friday"
    SATURDAY = "Saturday"
    SUNDAY = "Sunday"


class SportType(str, Enum):
    """Type of endurance sport/event"""
    TRIATHLON = "triathlon"
    RUNNING = "running"
    CYCLING = "cycling"
    DUATHLON = "duathlon"
    AQUATHLON = "aquathlon"


class RaceDistance(str, Enum):
    # Triathlon distances
    SPRINT = "sprint"  # 750m swim, 20km bike, 5km run
    OLYMPIC = "olympic"  # 1.5km swim, 40km bike, 10km run
    HALF_IRONMAN = "half_ironman"  # 1.9km swim, 90km bike, 21.1km run
    FULL_IRONMAN = "full_ironman"  # 3.8km swim, 180km bike, 42.2km run
    
    # Running distances
    FIVE_K = "5k"
    TEN_K = "10k"
    HALF_MARATHON = "half_marathon"
    MARATHON = "marathon"
    ULTRA_50K = "ultra_50k"
    ULTRA_100K = "ultra_100k"
    
    # Cycling distances
    CENTURY = "century"  # 100 miles / 160km
    GRAN_FONDO = "gran_fondo"  # 100-200km
    DOUBLE_CENTURY = "double_century"  # 200 miles / 320km
    
    # Duathlon distances
    DUATHLON_SPRINT = "duathlon_sprint"  # 5km run, 20km bike, 2.5km run
    DUATHLON_STANDARD = "duathlon_standard"  # 10km run, 40km bike, 5km run
    DUATHLON_LONG = "duathlon_long"  # 10km run, 60km bike, 10km run
    
    # Aquathlon distances
    AQUATHLON_SPRINT = "aquathlon_sprint"  # 750m swim, 5km run
    AQUATHLON_STANDARD = "aquathlon_standard"  # 1km swim, 5km run


class FitnessLevel(str, Enum):
    BEGINNER = "beginner"
    INTERMEDIATE = "intermediate"
    ADVANCED = "advanced"


class WorkoutInterval(BaseModel):
    duration_minutes: Optional[int] = None
    distance_km: Optional[float] = None
    intensity: str  # e.g., "Zone 2", "Easy", "Threshold", "Recovery"
    description: str


class Workout(BaseModel):
    sport: Sport
    title: str
    day: Weekday  # Required field - must be specified
    is_rest_day: bool = False
    total_duration_minutes: int
    total_distance_km: Optional[float] = None
    warmup: str = ""  # Optional for rest days
    main_set: List[WorkoutInterval] = []  # Empty for rest days
    cooldown: str = ""  # Optional for rest days
    notes: Optional[str] = None
    
    @field_validator('sport', mode='before')
    @classmethod
    def lowercase_sport(cls, v):
        if isinstance(v, str):
            v = v.lower().strip()
            # Map rest days and brick workouts to valid sports
            if v == 'rest':
                return 'swim'  # Default to swim for rest days (is_rest_day will be true)
            if 'bike' in v and 'run' in v:  # brick, bike-run, bike/run, etc.
                return 'bike'  # Brick workouts are bike-to-run transitions, use bike as primary
            if v in ['swim', 'bike', 'run']:
                return v
            # If none match, default to run
            return 'run'
        return v


class WeekPlan(BaseModel):
    week_number: int
    focus: str  # e.g., "Base Building", "Threshold Work", "Race Week"
    workouts: List[Workout]
    weekly_volume_hours: float
    weekly_distance_km: float


class TrainingProgram(BaseModel):
    goal: RaceDistance
    fitness_level: FitnessLevel
    duration_weeks: int
    weeks: List[WeekPlan]
    notes: str
    
    @field_validator('goal', 'fitness_level', mode='before')
    @classmethod
    def lowercase_enums(cls, v):
        if isinstance(v, str):
            # Handle variations like "sprint triathlon" -> "sprint"
            v = v.lower().replace(' triathlon', '').strip()
            # Map common variations
            if v in ['70.3', 'half-ironman', 'half ironman']:
                return 'half_ironman'
            if v in ['140.6', 'full-ironman', 'full ironman', 'ironman']:
                return 'full_ironman'
            return v
        return v


class WorkoutRequest(BaseModel):
    sport_type: SportType = Field(default=SportType.TRIATHLON, description="Type of endurance sport")
    goal: RaceDistance
    fitness_level: FitnessLevel
    available_hours_per_week: int = Field(ge=3, le=30)
    current_week: int = Field(default=1, ge=1)
    duration_weeks: int = Field(default=12, ge=4, le=52)
    focus_areas: Optional[List[str]] = None  # e.g., ["swimming technique", "bike endurance"]
