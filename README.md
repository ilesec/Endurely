# Endurely

AI-powered endurance training program generator for triathlon, running, cycling, and multi-sport athletes using Azure OpenAI.

## ✨ Features

- **Multi-Sport Support**: Programs for triathlon, running, cycling, duathlon, and aquathlon
- **Multi-User Support**: Secure authentication with Microsoft Entra External ID
- **User Data Isolation**: Each user only sees their own training programs
- **Structured Workouts**: Detailed workouts with intervals and recovery
- **Intelligent Scheduling**: Workouts automatically distributed across the week
- **Periodization**: Monthly training plans with progressive overload
- **Multiple Race Distances**: Sprint, Olympic, Half Ironman, Full Ironman
- **Flexible AI Backend**: Azure OpenAI with Managed Identity (no API keys!)
- **Web Interface**: Easy-to-use interface for program generation
- **REST API**: Full API for integration

---

## 🚀 Quick Start

### Option 1: Deploy to Azure (Recommended)

**Prerequisites:** Azure CLI installed and logged in

```powershell
# Clone and navigate to project
cd triathlon-program-generator

# Deploy with Azure OpenAI + Managed Identity (no API keys!)
.\deploy-azure-openai.ps1
```

This will:
- Create Azure OpenAI resource with GPT-4o-mini
- Set up App Service with Managed Identity  
- Configure secure authentication
- Deploy your application

**Time:** ~5-10 minutes | **Cost:** ~$15-20/month

### Option 2: Docker (Local or Cloud)

```bash
# Copy and configure environment
cp .env.example .env
# Edit .env with your API keys

# Run with Docker Compose
docker-compose up -d

# Access at http://localhost:8000
```

### Option 3: Local Python

```bash
python -m venv venv
source venv/bin/activate  # Windows: venv\Scripts\activate
pip install -r requirements.txt
cp .env.example .env
# Edit .env with your API keys
python app/main.py
```

---

## ⚙️ Configuration

### Environment Variables

**Azure OpenAI v1 API** - Automatic access to latest features with managed identity (no API keys needed!)

Create `.env` file from `.env.example`:

```bash
# Azure OpenAI Configuration
AZURE_AI_ENDPOINT=https://your-resource.openai.azure.com/
AZURE_AI_DEPLOYMENT_NAME=gpt-4o-mini
AZURE_AI_AUTH=entra_id  # Use managed identity (recommended for Azure)

# Authentication (Required for multi-user)
ENABLE_AUTH=true
ENTRA_TENANT_ID=your-tenant-id
ENTRA_CLIENT_ID=your-client-id
ENTRA_CLIENT_SECRET=your-client-secret
ENTRA_REDIRECT_URI=https://your-app.azurewebsites.net/auth/callback
ENTRA_CIAM_DOMAIN=your-domain
SESSION_SECRET_KEY=generate-a-secure-random-key

# Database
DATABASE_URL=sqlite:///./workouts.db
```

### Authentication Modes

**Managed Identity (Recommended for Azure)**
```bash
AZURE_AI_AUTH=entra_id
# No API key needed - uses Azure managed identity
```

**API Key (Development/Testing)**
```bash
AZURE_AI_AUTH=api_key
AZURE_AI_API_KEY=your-api-key
```

**For detailed authentication setup, see [ENTRA_EXTERNAL_ID_SETUP.md](ENTRA_EXTERNAL_ID_SETUP.md)**

---

## 📡 API Endpoints

### Health Checks
- `GET /health` - Basic health status
- `GET /health/ready` - Readiness check (database + LLM)
- `GET /health/live` - Liveness check

### Workouts
- `POST /api/workouts/generate` - Generate training program
- `GET /api/workouts` - List saved workouts
- `GET /api/workouts/{id}` - Get specific workout
- `DELETE /api/workouts/{id}` - Delete workout

### Example Request

```bash
curl -X POST https://your-app.azurewebsites.net/api/workouts/generate \
  -H "Content-Type: application/json" \
  -d '{
    "goal": "sprint",
    "fitness_level": "beginner",
    "available_hours_per_week": 6,
    "duration_weeks": 12
  }'
```

---

## 🏗️ Project Structure

```
triathlon-program-generator/
├── app/
│   ├── agent_azure_ai.py     # Azure OpenAI agent
│   ├── prompts.py            # Shared prompt templates
│   ├── models.py             # Pydantic data models
│   ├── database.py           # SQLAlchemy database
│   ├── repository.py         # Data access layer
│   ├── utils.py              # Helper functions
│   ├── config.py             # Configuration
│   ├── main.py               # FastAPI application
│   └── templates/            # Web UI templates
├── requirements.txt          # Python dependencies
├── Dockerfile                # Container definition
├── docker-compose.yml        # Local Docker setup
├── startup.sh                # App Service startup
├── deploy-azure-openai.ps1   # Azure deployment script
└── .env.example              # Environment template
```

---

## 🔒 Security Best Practices

### Production Checklist
- ✅ Use Azure Managed Identity (no API keys)
- ✅ Enable HTTPS only
- ✅ Use Azure Key Vault for secrets
- ✅ Enable App Service authentication
- ✅ Configure CORS properly
- ✅ Use PostgreSQL/Azure SQL for production database

### Managed Identity Setup (No API Keys!)

```bash
# Enable managed identity
az webapp identity assign --resource-group rg --name app-name

# Grant access to Azure OpenAI
az role assignment create \
  --role "Cognitive Services OpenAI User" \
  --assignee <identity-principal-id> \
  --scope <openai-resource-id>
```

---

## 📚 Additional Documentation

- **[README.Docker.md](README.Docker.md)** - Docker deployment guide
- **[AZURE_OPENAI_GUIDE.md](AZURE_OPENAI_GUIDE.md)** - Azure OpenAI reference
- **[DEPLOYMENT.md](DEPLOYMENT.md)** - Detailed deployment options

---

## 🛠️ Development

### Local Development

```bash
# Install dependencies
pip install -r requirements.txt

# Run in dev mode with hot reload
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

### Code Structure

- **Agents**: Azure OpenAI integration
- **Prompts**: Shared prompt templates
- **Models**: Pydantic schemas for validation
- **Utils**: Weekday assignment, helpers
- **Repository**: Database operations

---

## 🆘 Troubleshooting

**"Authorization failed" or "AZURE_AI_API_KEY is required" with Managed Identity**
```bash
# Verify environment variables are set correctly
az webapp config appsettings list --resource-group <rg> --name <app> | grep AZURE_AI

# Should see: AZURE_AI_AUTH=entra_id (not api_key!)

# Re-grant permissions if needed
az role assignment create \
  --role "Cognitive Services OpenAI User" \
  --assignee <principal-id> \
  --scope <openai-resource-id>

# Restart the app
az webapp restart --resource-group <rg> --name <app>
```

**App won't start**
```bash
az webapp log tail --resource-group rg --name app-name
az webapp restart --resource-group rg --name app-name
```

---

## 💰 Cost Estimates

**Azure Setup (monthly):**
- App Service B1: ~$13
- Azure OpenAI: ~$3-10 (usage-based)
- **Total: ~$15-25/month**

**Free Tier Option:**
- App Service F1: $0 (with limitations)
- Azure OpenAI: ~$3-10/month (usage-based)
- **Total: ~$3-10/month**

---

## 📝 License

MIT License

---

**Built with ❤️ for triathletes**

🌐 **Live Demo**: https://triathlon-program-generator.azurewebsites.net
