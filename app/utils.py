"""Utility functions for the triathlon program generator."""
from typing import Dict, Any, List
from app.models import Weekday


def assign_weekdays_to_workouts(program_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Assign weekdays to workouts that are missing them.
    
    Distributes workouts across Monday-Sunday in order.
    If there are rest days, they're typically placed on Monday or Friday.
    """
    weekdays = [
        Weekday.MONDAY,
        Weekday.TUESDAY,
        Weekday.WEDNESDAY,
        Weekday.THURSDAY,
        Weekday.FRIDAY,
        Weekday.SATURDAY,
        Weekday.SUNDAY,
    ]
    
    # Process each week
    for week in program_data.get("weeks", []):
        workouts = week.get("workouts", [])
        
        if not workouts:
            continue
        
        # Check if any workout is missing the day field
        missing_days = any("day" not in workout for workout in workouts)
        
        if missing_days:
            # Assign days to all workouts in order
            # Sort rest days to be first (typically Monday) or last (Friday)
            rest_workouts = [w for w in workouts if w.get("is_rest_day", False)]
            active_workouts = [w for w in workouts if not w.get("is_rest_day", False)]
            
            # Assign days
            day_index = 0
            
            # If we have a rest day, put it on Monday
            if rest_workouts and len(rest_workouts) > 0:
                rest_workouts[0]["day"] = weekdays[0].value
                day_index = 1
            
            # Assign active workouts to remaining days
            for workout in active_workouts:
                if day_index < len(weekdays):
                    workout["day"] = weekdays[day_index].value
                    day_index += 1
            
            # If we have more rest days, put them at the end
            for i, rest_workout in enumerate(rest_workouts[1:], start=1):
                if day_index < len(weekdays):
                    rest_workout["day"] = weekdays[day_index].value
                    day_index += 1
    
    return program_data
