from sqlalchemy import create_engine, Column, Integer, String, Float, DateTime, Text, ForeignKey, Boolean
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker, relationship
from datetime import datetime
from app.config import settings

Base = declarative_base()
engine = create_engine(settings.database_url, connect_args={"check_same_thread": False})
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


class User(Base):
    """Database model for users."""
    __tablename__ = "users"
    
    id = Column(Integer, primary_key=True, index=True)
    oid = Column(String, unique=True, index=True, nullable=False)  # Entra External ID object ID
    email = Column(String, unique=True, index=True, nullable=False)
    name = Column(String, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)
    last_login = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    is_active = Column(Boolean, default=True)
    
    # Relationships
    programs = relationship("SavedProgram", back_populates="user", cascade="all, delete-orphan")
    workout_history = relationship("WorkoutHistory", back_populates="user", cascade="all, delete-orphan")


class SavedProgram(Base):
    """Database model for saved training programs."""
    __tablename__ = "training_programs"
    
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    created_at = Column(DateTime, default=datetime.utcnow)
    sport_type = Column(String, nullable=False, default="triathlon")  # triathlon, running, cycling, duathlon, aquathlon
    goal = Column(String, nullable=False)
    fitness_level = Column(String, nullable=False)
    duration_weeks = Column(Integer, nullable=False)
    available_hours_per_week = Column(Integer, nullable=False)
    program_json = Column(Text, nullable=False)  # Store full program as JSON
    notes = Column(Text)
    
    # Relationship
    user = relationship("User", back_populates="programs")


class WorkoutHistory(Base):
    """Database model for tracking completed workouts."""
    __tablename__ = "workout_history"
    
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    program_id = Column(Integer, nullable=True)  # Reference to SavedProgram
    completed_at = Column(DateTime, default=datetime.utcnow)
    sport = Column(String, nullable=False)
    title = Column(String, nullable=False)
    duration_minutes = Column(Integer, nullable=False)
    distance_km = Column(Float, nullable=True)
    notes = Column(Text)
    rating = Column(Integer)  # 1-5 difficulty/satisfaction rating
    
    # Relationship
    user = relationship("User", back_populates="workout_history")


def init_db():
    """Initialize the database tables."""
    Base.metadata.create_all(bind=engine)


def get_db():
    """Dependency for getting database sessions."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
