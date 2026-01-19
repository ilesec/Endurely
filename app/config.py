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
    azure_ai_api_version: str = Field(
        default="2024-02-15-preview",
        validation_alias=AliasChoices(
            "AZURE_AI_API_VERSION",
            "AZURE_OPENAI_API_VERSION",
            "azure_ai_api_version",
        ),
    )
    # Azure AI auth mode: "api_key" or "entra_id" (Managed Identity / Entra ID)
    azure_ai_auth: str = Field(
        default="api_key",
        validation_alias=AliasChoices(
            "AZURE_AI_AUTH",
            "AZURE_OPENAI_AUTH",
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
    
    # Database
    database_url: str = "sqlite:///./workouts.db"
    
    # Authentication (Entra External ID)
    enable_auth: bool = Field(
        default=False,
        validation_alias=AliasChoices("ENABLE_AUTH", "enable_auth"),
    )
    entra_tenant_id: Optional[str] = Field(
        default=None,
        validation_alias=AliasChoices("ENTRA_TENANT_ID", "AZURE_AD_TENANT_ID", "entra_tenant_id"),
    )
    entra_client_id: Optional[str] = Field(
        default=None,
        validation_alias=AliasChoices("ENTRA_CLIENT_ID", "AZURE_AD_CLIENT_ID", "entra_client_id"),
    )
    entra_client_secret: Optional[str] = Field(
        default=None,
        validation_alias=AliasChoices("ENTRA_CLIENT_SECRET", "AZURE_AD_CLIENT_SECRET", "entra_client_secret"),
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
        validation_alias=AliasChoices("SESSION_SECRET_KEY", "SECRET_KEY", "session_secret_key"),
    )
    
    class Config:
        env_file = ".env"


settings = Settings()
