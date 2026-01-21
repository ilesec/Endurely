from pydantic_settings import BaseSettings
from pydantic import Field, AliasChoices
from typing import Optional


class Settings(BaseSettings):
    # Azure AI / OpenAI settings
    azure_ai_endpoint: Optional[str] = Field(
        default=None,
        validation_alias=AliasChoices(
            "AZURE_AI_ENDPOINT",
            "AZURE_OPENAI_ENDPOINT",
            "azure_ai_endpoint",
        ),
    )
    azure_ai_api_key: Optional[str] = Field(
        default=None,
        validation_alias=AliasChoices(
            "AZURE_AI_API_KEY",
            "AZURE_OPENAI_API_KEY",
            "AZURE_OPENAI_KEY",
            "azure_ai_api_key",
        ),
    )
    azure_ai_deployment_name: Optional[str] = Field(
        default=None,
        validation_alias=AliasChoices(
            "AZURE_AI_DEPLOYMENT_NAME",
            "AZURE_OPENAI_DEPLOYMENT_NAME",
            "AZURE_OPENAI_DEPLOYMENT",
            "azure_ai_deployment_name",
        ),
    )
    # Azure AI auth mode: "entra_id" (Managed Identity, recommended) or "api_key"
    azure_ai_auth: str = Field(
        default="entra_id",
        validation_alias=AliasChoices(
            "AZURE_AI_AUTH",
            "AZURE_OPENAI_AUTH",
            "AZURE_OPENAI_AUTH_MODE",
            "azure_ai_auth",
        ),
    )
    # For user-assigned managed identity (optional). Leave empty for system-assigned.
    azure_ai_managed_identity_client_id: Optional[str] = Field(
        default=None,
        validation_alias=AliasChoices(
            "AZURE_AI_MANAGED_IDENTITY_CLIENT_ID",
            "AZURE_OPENAI_MANAGED_IDENTITY_CLIENT_ID",
            "azure_ai_managed_identity_client_id",
        ),
    )
    
    # Database - Azure SQL Database
    database_url: str = Field(
        default="",
        validation_alias=AliasChoices("DATABASE_URL", "database_url"),
    )
    
    # Authentication (Entra External ID)
    enable_auth: bool = Field(
        default=False,
        validation_alias=AliasChoices("ENABLE_AUTH", "enable_auth"),
    )
    entra_tenant_id: Optional[str] = Field(
        default=None,
        validation_alias=AliasChoices("ENTRA_TENANT_ID", "entra_tenant_id"),
    )
    entra_client_id: Optional[str] = Field(
        default=None,
        validation_alias=AliasChoices("ENTRA_CLIENT_ID", "entra_client_id"),
    )
    entra_client_secret: Optional[str] = Field(
        default=None,
        validation_alias=AliasChoices("ENTRA_CLIENT_SECRET", "entra_client_secret"),
    )
    entra_redirect_uri: str = Field(
        default="http://localhost:8000/auth/callback",
        validation_alias=AliasChoices("ENTRA_REDIRECT_URI", "entra_redirect_uri"),
    )
    # CIAM domain for External ID (e.g., "triathlonapp" for triathlonapp.ciamlogin.com)
    entra_ciam_domain: Optional[str] = Field(
        default=None,
        validation_alias=AliasChoices("ENTRA_CIAM_DOMAIN", "entra_ciam_domain"),
    )
    session_secret_key: str = Field(
        default="change-me-in-production-use-openssl-rand-hex-32",
        validation_alias=AliasChoices("SESSION_SECRET_KEY", "session_secret_key"),
    )
    
    class Config:
        env_file = ".env"


settings = Settings()
