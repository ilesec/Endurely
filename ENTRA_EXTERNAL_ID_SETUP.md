# Entra External ID Authentication Setup

This guide walks you through setting up Microsoft Entra External ID (formerly Azure AD B2C) for multi-user authentication in the Triathlon Program Generator.

## Prerequisites

- Azure subscription with access to Microsoft Entra External ID
- Azure App Service already deployed (triathlon-program-generator.azurewebsites.net)
- Admin access to configure authentication

## Step 1: Create Entra External ID Tenant

1. Go to [Azure Portal](https://portal.azure.com)
2. Search for "Microsoft Entra External ID" in the search bar
3. Click "Create" to create a new External ID tenant
4. Choose tenant type: **External**
5. Fill in tenant details:
   - Organization name: `Triathlon Program Generator`
   - Initial domain name: `triathlonprogram` (or your preferred name)
   - Country/Region: Select your country
6. Click "Review + Create" and then "Create"
7. Note the **Tenant ID** (you'll need this later)

## Step 2: Register the Application

1. In your new External ID tenant, go to **App registrations**
2. Click "New registration"
3. Fill in the details:
   - Name: `Triathlon Program Generator`
   - Supported account types: **Accounts in any identity provider or organizational directory (for authenticating users with user flows)**
   - Redirect URI:
     - Platform: **Web**
     - URI: `https://triathlon-program-generator.azurewebsites.net/auth/callback`
4. Click "Register"
5. Note the **Application (client) ID** - this is your `ENTRA_CLIENT_ID`
6. Note the **Directory (tenant) ID** - this is your `ENTRA_TENANT_ID`

## Step 3: Create Client Secret

1. In your app registration, go to **Certificates & secrets**
2. Click "New client secret"
3. Add a description: `Triathlon App Secret`
4. Choose expiration: 24 months (or your preferred duration)
5. Click "Add"
6. **IMPORTANT**: Copy the **Value** immediately - this is your `ENTRA_CLIENT_SECRET`
   - You won't be able to see it again!

## Step 4: Configure API Permissions

1. In your app registration, go to **API permissions**
2. Verify that the following permissions are present:
   - Microsoft Graph: `openid` (Sign in and read user profile)
   - Microsoft Graph: `email` (View user's email address)
   - Microsoft Graph: `profile` (View user's basic profile)
3. If not present, click "Add a permission" → "Microsoft Graph" → "Delegated permissions"
4. Add the permissions above
5. Click "Grant admin consent" for your tenant

## Step 5: Configure Token Configuration (Optional)

1. In your app registration, go to **Token configuration**
2. Click "Add optional claim"
3. Select "ID" token type
4. Add the following claims:
   - `email`
   - `family_name`
   - `given_name`
5. Click "Add"

## Step 6: Create User Flow (Sign Up/Sign In)

1. In your External ID tenant, go to **User flows**
2. Click "New user flow"
3. Select "Sign up and sign in"
4. Choose version: **Recommended**
5. Configure user flow:
   - Name: `SignUpSignIn`
   - Identity providers: Select **Email signup**
   - User attributes and token claims:
     - Collect: Email Address, Display Name, Given Name, Surname
     - Return: Email Addresses, Display Name, Given Name, Surname, User's Object ID
6. Click "Create"

## Step 7: Configure Azure App Service Environment Variables

1. Go to your Azure App Service: `triathlon-program-generator`
2. Navigate to **Configuration** → **Application settings**
3. Add the following new application settings:

```
ENABLE_AUTH=true
ENTRA_TENANT_ID=<your-tenant-id>
ENTRA_CLIENT_ID=<your-client-id>
ENTRA_CLIENT_SECRET=<your-client-secret>
ENTRA_REDIRECT_URI=https://triathlon-program-generator.azurewebsites.net/auth/callback
SESSION_SECRET_KEY=<generate-a-secure-random-key>
```

**To generate a secure SESSION_SECRET_KEY**, run:
```bash
python -c "import secrets; print(secrets.token_urlsafe(32))"
```

4. Click "Save" and restart your App Service

## Step 8: Update Database Schema

The new authentication system requires database changes. You have two options:

### Option A: Recreate Database (Easiest for Development)

1. SSH into your App Service or use App Service Console
2. Delete the existing database:
```bash
rm triathlon.db
```
3. Restart the app - database will be recreated with new schema

### Option B: Migrate Existing Database

1. Create a backup of your current database
2. Run the migration script (you'll need to create this based on your needs):

```python
# migration.py
from sqlalchemy import create_engine, text

engine = create_engine('sqlite:///triathlon.db')

with engine.connect() as conn:
    # Add user table
    conn.execute(text("""
        CREATE TABLE IF NOT EXISTS users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            oid VARCHAR(255) UNIQUE NOT NULL,
            email VARCHAR(255) NOT NULL,
            name VARCHAR(255),
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            last_login TIMESTAMP,
            is_active BOOLEAN DEFAULT 1
        )
    """))
    
    # Add user_id to saved_programs
    conn.execute(text("""
        ALTER TABLE saved_programs ADD COLUMN user_id INTEGER 
        REFERENCES users(id)
    """))
    
    # Add user_id to workout_history
    conn.execute(text("""
        ALTER TABLE workout_history ADD COLUMN user_id INTEGER 
        REFERENCES users(id)
    """))
    
    conn.commit()
```

## Step 9: Test Authentication

1. Open your application: `https://triathlon-program-generator.azurewebsites.net`
2. You should see a "Sign In" button
3. Click "Sign In" - you'll be redirected to Entra External ID
4. Create a new account or sign in
5. After successful authentication, you'll be redirected back to the app
6. Verify that your email/name appears in the UI

## Step 10: Verify User Isolation

1. Create a workout program while signed in
2. Sign out and create a different account
3. Sign in with the new account
4. Verify that you can only see programs created with the current account
5. Sign back in with the first account and verify programs are isolated

## Troubleshooting

### Redirect URI Mismatch
**Error**: `AADB2C90006: The redirect URI provided in the request is not registered`

**Solution**: Verify that the redirect URI in your app registration exactly matches:
```
https://triathlon-program-generator.azurewebsites.net/auth/callback
```

### Invalid Client Secret
**Error**: `AADSTS7000215: Invalid client secret provided`

**Solution**: 
1. Go to app registration → Certificates & secrets
2. Create a new client secret
3. Update the `ENTRA_CLIENT_SECRET` in App Service configuration
4. Restart the App Service

### Token Validation Error
**Error**: Token signature validation fails

**Solution**:
1. Verify `ENTRA_TENANT_ID` and `ENTRA_CLIENT_ID` are correct
2. Check that the token issuer matches your tenant
3. Ensure system time is synchronized (important for token expiry)

### Session Cookie Not Persisting
**Error**: User gets logged out immediately after login

**Solution**:
1. Verify `SESSION_SECRET_KEY` is set and persistent
2. Check that your domain supports secure cookies (HTTPS)
3. Verify cookie settings in browser (not blocking third-party cookies)

### Database Errors After Migration
**Error**: `OperationalError: no such column: saved_programs.user_id`

**Solution**: The database schema wasn't updated. Follow Step 8 to migrate the database.

## Development Mode (Without Authentication)

For local development without setting up Entra External ID:

1. Set `ENABLE_AUTH=false` in your `.env` file
2. The app will use a default user (ID=1, email=dev@local)
3. All data will be associated with this default user
4. No login is required

**Warning**: Never deploy to production with `ENABLE_AUTH=false`

## Security Best Practices

1. **Rotate client secrets** every 12-24 months
2. **Use Azure Key Vault** for storing secrets in production
3. **Enable logging** for authentication events
4. **Monitor failed login attempts** for potential security issues
5. **Keep session timeout** reasonable (default: 7 days)
6. **Use HTTPS only** - never allow HTTP in production
7. **Implement rate limiting** on auth endpoints to prevent brute force

## Architecture Overview

```
User Browser
    ↓
    ├─→ /auth/login → Redirect to Entra External ID
    │                      ↓
    │                  User enters credentials
    │                      ↓
    │   ← Redirect with auth code ←
    │
    ├─→ /auth/callback (receives code)
    │       ↓
    │   Exchange code for tokens (MSAL)
    │       ↓
    │   Create session token
    │       ↓
    │   Set secure cookie
    │       ↓
    │   Redirect to /
    │
    ├─→ /api/* (protected endpoints)
    │       ↓
    │   Verify session token
    │       ↓
    │   Extract user info
    │       ↓
    │   Filter data by user_id
    │
    └─→ /auth/logout
            ↓
        Clear session cookie
            ↓
        Redirect to /
```

## Additional Resources

- [Microsoft Entra External ID Documentation](https://learn.microsoft.com/en-us/entra/external-id/)
- [MSAL Python Documentation](https://msal-python.readthedocs.io/)
- [OAuth 2.0 Authorization Code Flow](https://oauth.net/2/grant-types/authorization-code/)
- [FastAPI Security Documentation](https://fastapi.tiangolo.com/tutorial/security/)

## Support

If you encounter issues not covered in this guide:
1. Check the application logs in Azure App Service
2. Enable debug logging: Set `LOG_LEVEL=DEBUG` in App Service configuration
3. Review the MSAL library logs for authentication issues
4. Consult the Entra External ID troubleshooting guide

---

**Note**: This authentication system is production-ready but should be tested thoroughly in a staging environment before deploying to production.
