"""FastAPI application for AI-powered endurance training program generator.

Features:
- Multi-sport support (triathlon, running, cycling, duathlon, aquathlon)
- Multi-user authentication with Microsoft Entra External ID
- Session-based authentication with httponly cookies
- Azure OpenAI with managed identity (no API keys)
- User data isolation
- RESTful API and web interface
"""
from fastapi import FastAPI, Depends, HTTPException, Request
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.orm import Session
from sqlalchemy import text
from typing import List, Optional
import json
import uvicorn
import sys
import logging

from app.database import init_db, get_db, User
from app.models import WorkoutRequest, TrainingProgram, RaceDistance, Sport
from app.config import settings
from app.repository import ProgramRepository, WorkoutHistoryRepository
from app.auth import auth_manager

logger = logging.getLogger(__name__)


def validate_configuration():
    """Validate required configuration at startup."""
    # Skip validation in production for faster startup
    # Config errors will be caught when endpoints are called
    pass

# Initialize FastAPI app
app = FastAPI(
    title="Triathlon Program Generator",
    description="AI-powered triathlon training program generator",
    version="1.0.0"
)

# Add CORS middleware to allow credentials
app.add_middleware(
    CORSMiddleware,
    allow_origins=["https://endurely-app.azurewebsites.net", "http://localhost:8000"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Initialize database
init_db()

# Setup templates
templates = Jinja2Templates(directory="app/templates")

# Lazy-load agent for faster startup
_agent = None

def get_agent():
    """Get or create the agent instance (lazy initialization)."""
    global _agent
    if _agent is None:
        from app.agent_azure_ai import TriathlonWorkoutAgentAzureAI
        _agent = TriathlonWorkoutAgentAzureAI()
    return _agent


# Authentication Endpoints

@app.get("/auth/login")
async def login():
    """Redirect to Entra External ID login page."""
    if not auth_manager.enabled:
        raise HTTPException(status_code=404, detail="Authentication is not enabled")
    
    auth_url = auth_manager.get_auth_url()
    return RedirectResponse(url=auth_url)


@app.get("/auth/callback")
async def auth_callback(code: str, state: str = None):
    """Handle OAuth callback from Entra External ID."""
    if not auth_manager.enabled:
        raise HTTPException(status_code=404, detail="Authentication is not enabled")
    
    try:
        # Exchange code for token
        token_data = await auth_manager.handle_callback(code, state)
        
        # Get or create user
        user = await auth_manager.get_or_create_user(token_data.get("id_token_claims", {}))
        
        # Create session token
        session_token = auth_manager.create_session_token({
            "oid": user.oid,
            "email": user.email,
            "name": user.name,
        })
        
        # Set cookie and redirect
        response = RedirectResponse(url="/", status_code=302)
        response.set_cookie(
            key="session_token",
            value=session_token,
            httponly=True,
            secure=True,
            samesite="lax",
            max_age=86400 * 7,  # 7 days
            path="/",
        )
        return response
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Authentication failed: {str(e)}")


@app.get("/auth/logout")
async def logout():
    """Logout current user."""
    return auth_manager.logout()


@app.get("/api/auth/user")
async def get_current_user_info(request: Request):
    """Get current authenticated user information."""
    user = await auth_manager.get_current_user(request)
    if not user:
        return {
            "authenticated": False,
            "auth_enabled": auth_manager.enabled,
        }
    
    return {
        "authenticated": True,
        "email": user.email,
        "name": user.name,
        "auth_enabled": auth_manager.enabled,
    }


# Health Check Endpoints

@app.get("/health")
async def health_check():
    """Health check endpoint for monitoring and container orchestration."""
    return {
        "status": "healthy",
        "service": "triathlon-program-generator",
        "version": "1.0.0",
        "llm_provider": "azure_ai",
        "auth_enabled": auth_manager.enabled,
    }


@app.get("/health/ready")
async def readiness_check(db: Session = Depends(get_db)):
    """Readiness check - verifies database connectivity and LLM configuration."""
    try:
        # Check database
        db.execute(text("SELECT 1"))
        
        # Check Azure AI configuration
        if not settings.azure_ai_endpoint:
            return {"status": "not_ready", "reason": "AZURE_AI_ENDPOINT not configured"}
        if settings.azure_ai_auth == "api_key" and not settings.azure_ai_api_key:
            return {"status": "not_ready", "reason": "AZURE_AI_API_KEY not configured"}
        
        return {
            "status": "ready",
            "database": "connected",
            "llm_provider": "azure_ai"
        }
    except Exception as e:
        return {"status": "not_ready", "reason": str(e)}


@app.get("/health/live")
async def liveness_check():
    """Liveness check - basic endpoint to verify the service is running."""
    return {"status": "alive"}


# API Endpoints

@app.post("/api/workouts/generate", response_model=dict)
async def generate_workout(
    request: WorkoutRequest,
    db: Session = Depends(get_db),
    user: User = Depends(auth_manager.require_auth)
):
    """Generate a new training program using the AI agent."""
    try:
        # Generate program using AI (lazy-loaded agent)
        agent = get_agent()
        program = agent.generate_program(request)
        
        # Save to database with user association
        saved_program = ProgramRepository.save_program(
            db=db,
            program=program,
            request_data=request.model_dump(),
            user_id=user.id
        )
        
        return {
            "id": saved_program.id,
            "program": program.model_dump(),
            "message": "Training program generated successfully"
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error generating program: {str(e)}")


@app.get("/api/workouts", response_model=List[dict])
async def list_workouts(
    skip: int = 0,
    limit: int = 100,
    goal: Optional[RaceDistance] = None,
    db: Session = Depends(get_db),
    user: User = Depends(auth_manager.require_auth)
):
    """List all saved workout programs for the current user."""
    programs = ProgramRepository.list_programs(
        db=db,
        skip=skip,
        limit=limit,
        goal=goal.value if goal else None,
        user_id=user.id
    )
    
    return [
        {
            "id": p.id,
            "created_at": p.created_at.isoformat(),
            "goal": p.goal,
            "fitness_level": p.fitness_level,
            "duration_weeks": p.duration_weeks,
            "available_hours_per_week": p.available_hours_per_week,
            "notes": p.notes
        }
        for p in programs
    ]


@app.get("/api/workouts/{program_id}", response_model=dict)
async def get_workout(
    program_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(auth_manager.require_auth)
):
    """Get a specific workout program by ID."""
    program = ProgramRepository.get_program(
        db=db,
        program_id=program_id,
        user_id=user.id
    )
    
    if not program:
        raise HTTPException(status_code=404, detail="Program not found")
    
    return {
        "id": program.id,
        "created_at": program.created_at.isoformat(),
        "goal": program.goal,
        "fitness_level": program.fitness_level,
        "duration_weeks": program.duration_weeks,
        "program": json.loads(program.program_json)
    }


@app.delete("/api/workouts/{program_id}")
async def delete_workout(
    program_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(auth_manager.require_auth)
):
    """Delete a workout program."""
    success = ProgramRepository.delete_program(
        db=db,
        program_id=program_id,
        user_id=user.id
    )
    
    if not success:
        raise HTTPException(status_code=404, detail="Program not found")
    
    return {"message": "Program deleted successfully"}


@app.post("/api/history/log")
async def log_workout(
    program_id: Optional[int] = None,
    sport: Sport = Sport.RUN,
    title: str = "Workout",
    duration_minutes: int = 60,
    distance_km: Optional[float] = None,
    notes: Optional[str] = None,
    rating: Optional[int] = None,
    db: Session = Depends(get_db),
    user: User = Depends(auth_manager.require_auth)
):
    """Log a completed workout."""
    workout = WorkoutHistoryRepository.log_workout(
        db=db,
        program_id=program_id,
        sport=sport.value,
        title=title,
        duration_minutes=duration_minutes,
        distance_km=distance_km,
        notes=notes,
        rating=rating,
        user_id=user.id
    )
    
    return {
        "id": workout.id,
        "message": "Workout logged successfully"
    }


@app.get("/api/history")
async def get_workout_history(
    program_id: Optional[int] = None,
    sport: Optional[Sport] = None,
    skip: int = 0,
    limit: int = 100,
    db: Session = Depends(get_db),
    user: User = Depends(auth_manager.require_auth)
):
    """Get workout history for the current user."""
    workouts = WorkoutHistoryRepository.get_workout_history(
        db=db,
        program_id=program_id,
        sport=sport.value if sport else None,
        skip=skip,
        limit=limit,
        user_id=user.id
    )
    
    return [
        {
            "id": w.id,
            "completed_at": w.completed_at.isoformat(),
            "sport": w.sport,
            "title": w.title,
            "duration_minutes": w.duration_minutes,
            "distance_km": w.distance_km,
            "notes": w.notes,
            "rating": w.rating
        }
        for w in workouts
    ]


@app.get("/api/stats")
async def get_stats(sport: Optional[Sport] = None, db: Session = Depends(get_db)):
    """Get workout statistics."""
    stats = WorkoutHistoryRepository.get_workout_stats(
        db=db,
        sport=sport.value if sport else None
    )
    return stats


# Web Interface

@app.get("/", response_class=HTMLResponse)
async def home(request: Request):
    """Serve the main web interface."""
    return templates.TemplateResponse("index.html", {"request": request})


@app.get("/programs/{program_id}", response_class=HTMLResponse)
async def view_program(request: Request, program_id: int):
    """View a specific training program."""
    return templates.TemplateResponse(
        "program.html",
        {"request": request, "program_id": program_id}
    )


if __name__ == "__main__":
    import os
    port = int(os.getenv("PORT", 8000))
    print(f"Starting Triathlon Program Generator on port {port}...")
    print(f"Navigate to http://localhost:{port} to access the web interface")
    uvicorn.run(app, host="0.0.0.0", port=port)
