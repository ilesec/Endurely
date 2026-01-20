from typing import List, Optional
from sqlalchemy.orm import Session
from datetime import datetime
import json
from app.database import SavedProgram, WorkoutHistory
from app.models import TrainingProgram


class ProgramRepository:
    """Repository for managing training programs in the database."""
    
    @staticmethod
    def save_program(db: Session, program: TrainingProgram, request_data: dict, user_id: Optional[int] = None) -> SavedProgram:
        """Save a training program to the database."""
        db_program = SavedProgram(
            user_id=user_id,
            sport_type=request_data.get("sport_type", "triathlon"),  # Default to triathlon for backward compatibility
            goal=request_data["goal"],
            fitness_level=request_data["fitness_level"],
            duration_weeks=request_data["duration_weeks"],
            available_hours_per_week=request_data["available_hours_per_week"],
            program_json=program.model_dump_json(),
            notes=program.notes
        )
        db.add(db_program)
        db.commit()
        db.refresh(db_program)
        return db_program
    
    @staticmethod
    def get_program(db: Session, program_id: int, user_id: Optional[int] = None) -> Optional[SavedProgram]:
        """Retrieve a program by ID."""
        query = db.query(SavedProgram).filter(SavedProgram.id == program_id)
        if user_id is not None:
            query = query.filter(SavedProgram.user_id == user_id)
        return query.first()
    
    @staticmethod
    def list_programs(
        db: Session, 
        skip: int = 0, 
        limit: int = 100,
        goal: Optional[str] = None,
        user_id: Optional[int] = None
    ) -> List[SavedProgram]:
        """List all saved programs with optional filtering."""
        query = db.query(SavedProgram)
        if user_id is not None:
            query = query.filter(SavedProgram.user_id == user_id)
        if goal:
            query = query.filter(SavedProgram.goal == goal)
        return query.order_by(SavedProgram.created_at.desc()).offset(skip).limit(limit).all()
    
    @staticmethod
    def delete_program(db: Session, program_id: int, user_id: Optional[int] = None) -> bool:
        """Delete a program by ID."""
        query = db.query(SavedProgram).filter(SavedProgram.id == program_id)
        if user_id is not None:
            query = query.filter(SavedProgram.user_id == user_id)
        program = query.first()
        if program:
            db.delete(program)
            db.commit()
            return True
        return False


class WorkoutHistoryRepository:
    """Repository for managing workout history."""
    
    @staticmethod
    def log_workout(
        db: Session,
        program_id: Optional[int],
        sport: str,
        title: str,
        duration_minutes: int,
        distance_km: Optional[float],
        notes: Optional[str],
        rating: Optional[int],
        user_id: Optional[int] = None
    ) -> WorkoutHistory:
        """Log a completed workout."""
        workout = WorkoutHistory(
            user_id=user_id,
            program_id=program_id,
            sport=sport,
            title=title,
            duration_minutes=duration_minutes,
            distance_km=distance_km,
            notes=notes,
            rating=rating
        )
        db.add(workout)
        db.commit()
        db.refresh(workout)
        return workout
    
    @staticmethod
    def get_workout_history(
        db: Session,
        program_id: Optional[int] = None,
        sport: Optional[str] = None,
        skip: int = 0,
        limit: int = 100,
        user_id: Optional[int] = None
    ) -> List[WorkoutHistory]:
        """Retrieve workout history with optional filtering."""
        query = db.query(WorkoutHistory)
        if user_id is not None:
            query = query.filter(WorkoutHistory.user_id == user_id)
        if program_id:
            query = query.filter(WorkoutHistory.program_id == program_id)
        if sport:
            query = query.filter(WorkoutHistory.sport == sport)
        return query.order_by(WorkoutHistory.completed_at.desc()).offset(skip).limit(limit).all()
    
    @staticmethod
    def get_workout_stats(db: Session, sport: Optional[str] = None, user_id: Optional[int] = None) -> dict:
        """Get aggregate statistics for workouts."""
        query = db.query(WorkoutHistory)
        if user_id is not None:
            query = query.filter(WorkoutHistory.user_id == user_id)
        if sport:
            query = query.filter(WorkoutHistory.sport == sport)
        
        workouts = query.all()
        
        if not workouts:
            return {
                "total_workouts": 0,
                "total_duration_minutes": 0,
                "total_distance_km": 0,
                "average_rating": 0
            }
        
        total_duration = sum(w.duration_minutes for w in workouts)
        total_distance = sum(w.distance_km or 0 for w in workouts)
        ratings = [w.rating for w in workouts if w.rating]
        avg_rating = sum(ratings) / len(ratings) if ratings else 0
        
        return {
            "total_workouts": len(workouts),
            "total_duration_minutes": total_duration,
            "total_distance_km": round(total_distance, 2),
            "average_rating": round(avg_rating, 2)
        }
