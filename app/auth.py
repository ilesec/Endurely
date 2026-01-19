"""Authentication module for Entra External ID (Azure AD B2C)."""
import msal
from fastapi import Request, HTTPException, status
from fastapi.responses import RedirectResponse
from typing import Optional, Dict, Any
from datetime import datetime, timedelta
from itsdangerous import URLSafeTimedSerializer, BadSignature
from app.config import settings
from app.database import SessionLocal, User


class AuthManager:
    """Manages authentication with Entra External ID."""
    
    def __init__(self):
        self.enabled = settings.enable_auth
        if not self.enabled:
            return
            
        if not all([settings.entra_tenant_id, settings.entra_client_id, settings.entra_client_secret]):
            raise ValueError("Authentication is enabled but Entra External ID credentials are not configured")
        
        self.tenant_id = settings.entra_tenant_id
        self.client_id = settings.entra_client_id
        self.client_secret = settings.entra_client_secret
        self.redirect_uri = settings.entra_redirect_uri
        
        # MSAL authority URL for Entra External ID
        # If CIAM domain is provided, use the ciamlogin.com format
        # Otherwise fall back to login.microsoftonline.com/v2.0
        if settings.entra_ciam_domain:
            # Format: https://<domain>.ciamlogin.com
            self.authority = f"https://{settings.entra_ciam_domain}.ciamlogin.com"
        else:
            # Fallback: https://login.microsoftonline.com/<tenant-id>/v2.0
            self.authority = f"https://login.microsoftonline.com/{self.tenant_id}/v2.0"
        
        # Scopes for OpenID Connect authentication
        # For Entra External ID (CIAM), use client ID with /.default suffix
        if settings.entra_ciam_domain:
            self.scopes = [f"{self.client_id}/.default"]
        else:
            self.scopes = ["openid", "profile", "email"]
        
        # Session serializer for secure cookies
        self.serializer = URLSafeTimedSerializer(settings.session_secret_key)
    
    def get_msal_app(self) -> msal.ConfidentialClientApplication:
        """Create MSAL application instance."""
        return msal.ConfidentialClientApplication(
            self.client_id,
            authority=self.authority,
            client_credential=self.client_secret,
        )
    
    def get_auth_url(self, state: str = None) -> str:
        """Get authorization URL for login."""
        app = self.get_msal_app()
        auth_url = app.get_authorization_request_url(
            scopes=self.scopes,
            state=state,
            redirect_uri=self.redirect_uri,
        )
        return auth_url
    
    async def handle_callback(self, code: str, state: str = None) -> Dict[str, Any]:
        """Handle OAuth callback and exchange code for tokens."""
        app = self.get_msal_app()
        
        result = app.acquire_token_by_authorization_code(
            code,
            scopes=self.scopes,
            redirect_uri=self.redirect_uri,
        )
        
        if "error" in result:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail=f"Authentication failed: {result.get('error_description', result['error'])}"
            )
        
        return result
    
    def create_session_token(self, user_data: Dict[str, Any]) -> str:
        """Create a secure session token."""
        return self.serializer.dumps(user_data)
    
    def verify_session_token(self, token: str, max_age: int = 86400 * 7) -> Optional[Dict[str, Any]]:
        """Verify and decode session token. Default max age is 7 days."""
        try:
            return self.serializer.loads(token, max_age=max_age)
        except BadSignature:
            return None
    
    async def get_or_create_user(self, token_data: Dict[str, Any]) -> User:
        """Get existing user or create new one from token data."""
        db = SessionLocal()
        try:
            # Extract user info from token - handle different claim structures
            # Azure AD uses 'oid', External ID might use 'sub'
            oid = token_data.get("oid") or token_data.get("sub")
            # Try multiple email claim names
            email = (token_data.get("preferred_username") or 
                    token_data.get("email") or 
                    token_data.get("upn") or
                    token_data.get("unique_name"))
            name = token_data.get("name") or email
            
            if not oid:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=f"Invalid token: missing user identifier (oid/sub). Available claims: {list(token_data.keys())}"
                )
            
            if not email:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=f"Invalid token: missing email. Available claims: {list(token_data.keys())}"
                )
            
            # Try to find existing user
            user = db.query(User).filter(User.oid == oid).first()
            
            if user:
                # Update last login
                user.last_login = datetime.utcnow()
                db.commit()
                db.refresh(user)
            else:
                # Create new user
                user = User(
                    oid=oid,
                    email=email,
                    name=name,
                    created_at=datetime.utcnow(),
                    last_login=datetime.utcnow(),
                    is_active=True,
                )
                db.add(user)
                db.commit()
                db.refresh(user)
            
            return user
        finally:
            db.close()
    
    async def get_current_user(self, request: Request) -> Optional[User]:
        """Get current authenticated user from request."""
        if not self.enabled:
            # If auth is disabled, return a default user for development
            return self._get_default_user()
        
        # Get session token from cookie
        token = request.cookies.get("session_token")
        if not token:
            return None
        
        # Verify token
        user_data = self.verify_session_token(token)
        if not user_data:
            return None
        
        # Get user from database
        db = SessionLocal()
        try:
            user = db.query(User).filter(User.oid == user_data["oid"]).first()
            return user
        finally:
            db.close()
    
    def _get_default_user(self) -> User:
        """Get or create default user for development (when auth is disabled)."""
        db = SessionLocal()
        try:
            user = db.query(User).filter(User.email == "dev@example.com").first()
            if not user:
                user = User(
                    oid="dev-user-123",
                    email="dev@example.com",
                    name="Development User",
                    created_at=datetime.utcnow(),
                    last_login=datetime.utcnow(),
                    is_active=True,
                )
                db.add(user)
                db.commit()
                db.refresh(user)
            return user
        finally:
            db.close()
    
    async def require_auth(self, request: Request) -> User:
        """Require authentication. Raises HTTPException if not authenticated."""
        user = await self.get_current_user(request)
        if not user:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Not authenticated",
                headers={"WWW-Authenticate": "Bearer"},
            )
        return user
    
    def logout(self) -> RedirectResponse:
        """Logout user by clearing session."""
        response = RedirectResponse(url="/", status_code=status.HTTP_302_FOUND)
        response.delete_cookie("session_token")
        return response


# Global auth manager instance
auth_manager = AuthManager()
