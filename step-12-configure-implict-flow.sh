#!/bin/bash
# step-12-configure-implicit-flow.sh - Configures the application to use implicit flow for authentication
# Run this script after step-10-setup.sh and before step-20-deploy.sh

set -e # Exit on any error

# Welcome banner
echo "=================================================="
echo "   CloudFront Cognito Serverless Application     "
echo "          Implicit Flow Configuration            "
echo "=================================================="
echo

# Check if .env exists
if [ ! -f .env ]; then
    echo "❌ .env file not found. Please run step-10-setup.sh first."
    exit 1
fi

# Load environment variables
source .env

# Check for app.js.template
if [ ! -f web/app.js.template ]; then
    echo "❌ web/app.js.template not found. Please run step-10-setup.sh first."
    exit 1
fi

echo "🔧 Configuring application to use OAuth 2.0 implicit flow..."

# 1. Update app.js.template to use implicit flow
echo "📝 Updating app.js.template..."
# Make a backup
cp web/app.js.template web/app.js.template.bak

# Replace 'response_type: "code"' with 'response_type: "token"'
if grep -q 'response_type: "code"' web/app.js.template; then
    sed -i.original 's/response_type: "code"/response_type: "token"/g' web/app.js.template
    echo "✅ Updated response_type to token in app.js.template"
elif grep -q "response_type: 'code'" web/app.js.template; then
    sed -i.original "s/response_type: 'code'/response_type: 'token'/g" web/app.js.template
    echo "✅ Updated response_type to token in app.js.template"
else
    echo "⚠️ Could not find response_type: code in app.js.template"
    echo "   Please manually update the login function to use response_type: token"
fi

# 2. Enhance callback.html to handle tokens properly
echo "📝 Enhancing callback.html..."
# Make a backup
cp web/callback.html web/callback.html.bak

# Create the enhanced callback.html
cat > web/callback.html << 'CALLBACK_HTML'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Authentication Callback</title>
    <link rel="stylesheet" href="styles.css">
</head>
<body>
    <div class="container">
        <h1>Processing Authentication...</h1>
        <p>Please wait while we process your sign-in.</p>
        <div id="status-messages" style="background-color: #f0f0f0; padding: 10px; margin-top: 20px; border-radius: 5px;"></div>
    </div>
    
    <script src="https://cdn.jsdelivr.net/npm/amazon-cognito-identity-js/dist/amazon-cognito-identity.min.js"></script>
    <script src="https://sdk.amazonaws.com/js/aws-sdk-2.1000.0.min.js"></script>
    
    <script>
        // For debugging
        const status = document.getElementById('status-messages');
        function log(message) {
            console.log(message);
            const p = document.createElement('p');
            p.textContent = message;
            p.style.margin = '5px 0';
            status.appendChild(p);
        }
        
        // Handle authentication response
        window.onload = function() {
            // Check for errors
            const urlParams = new URLSearchParams(window.location.search);
            const error = urlParams.get('error');
            const errorDescription = urlParams.get('error_description');
            
            if (error) {
                log(`Error: ${error}`);
                if (errorDescription) log(`Description: ${errorDescription}`);
                log('Redirecting back to login page in 3 seconds...');
                setTimeout(() => { window.location.href = 'index.html'; }, 3000);
                return;
            }
            
            // Check for implicit flow - tokens in URL fragment
            const fragment = window.location.hash.substring(1);
            if (fragment) {
                log('Processing tokens from URL fragment');
                const params = new URLSearchParams(fragment);
                
                // Get tokens
                const idToken = params.get('id_token');
                const accessToken = params.get('access_token');
                
                if (idToken) {
                    localStorage.setItem('id_token', idToken);
                    log('ID token stored in localStorage');
                    
                    // Parse the token to get user info
                    try {
                        const payload = JSON.parse(atob(idToken.split('.')[1]));
                        log(`Authenticated as: ${payload.email || 'Unknown user'}`);
                    } catch (e) {
                        log('Error parsing token: ' + e.message);
                    }
                }
                
                if (accessToken) {
                    localStorage.setItem('access_token', accessToken);
                    log('Access token stored in localStorage');
                }
                
                log('Authentication successful! Redirecting...');
                setTimeout(() => { window.location.href = 'index.html'; }, 1500);
                return;
            }
            
            // Check for authorization code flow
            const code = urlParams.get('code');
            if (code) {
                log(`Received authorization code`);
                localStorage.setItem('auth_code', code);
                
                // Note: In a real app with a backend, you would exchange this code for tokens
                log('Code flow detected - requires backend exchange. Redirecting to main page...');
                setTimeout(() => { window.location.href = 'index.html'; }, 1500);
                return;
            }
            
            // No authentication info found
            log('No authentication information found in URL');
            setTimeout(() => { window.location.href = 'index.html'; }, 2000);
        };
    </script>
</body>
</html>
CALLBACK_HTML

echo "✅ Enhanced callback.html with better token handling"

# 3. Create the enhanced authentication function file
echo "📝 Creating enhanced authentication function file..."

cat > web/enhance-auth-function.js << 'EOF'
// Enhanced checkAuthentication function for app.js.template
// To use this, replace the checkAuthentication function in app.js.template
// with this improved version that includes token expiration checking

// Check if user is authenticated
function checkAuthentication() {
    console.log("Checking authentication...");
    const idToken = localStorage.getItem('id_token');
    
    if (idToken) {
        console.log("Found ID token, verifying...");
        try {
            // Parse the JWT token to get the email
            const payload = JSON.parse(atob(idToken.split('.')[1]));
            
            // Check if token is expired
            const now = Math.floor(Date.now() / 1000);
            if (payload.exp && payload.exp < now) {
                console.log("Token expired, logging out");
                localStorage.removeItem('id_token');
                localStorage.removeItem('access_token');
                loginSection.style.display = 'block';
                authenticatedSection.style.display = 'none';
                return;
            }
            
            console.log("Token valid, displaying authenticated section");
            // User is authenticated
            loginSection.style.display = 'none';
            authenticatedSection.style.display = 'block';
            userEmailSpan.textContent = payload.email || 'User';
        } catch (error) {
            console.error('Error parsing token:', error);
            userEmailSpan.textContent = 'Authenticated User';
            // Still show authenticated section even if we can't parse the token
            loginSection.style.display = 'none';
            authenticatedSection.style.display = 'block';
        }
    } else {
        console.log("No token found, displaying login section");
        // User is not authenticated
        loginSection.style.display = 'block';
        authenticatedSection.style.display = 'none';
    }
}
EOF

# 4. Create a helper script to apply the enhanced authentication function
echo "📝 Creating helper script to apply enhanced authentication function..."

cat > apply-enhanced-auth.sh << 'EOF'
#!/bin/bash
# Helper script to apply the enhanced authentication function
# This uses pattern matching to replace the checkAuthentication function

# Find the start and end of the current checkAuthentication function
START_LINE=$(grep -n "function checkAuthentication" web/app.js.template | cut -d: -f1)
if [ -z "$START_LINE" ]; then
    echo "❌ Could not find checkAuthentication function in app.js.template"
    exit 1
fi

# Use the new function from the enhance-auth-function.js file
NEW_FUNCTION=$(cat web/enhance-auth-function.js)

# Make a backup
cp web/app.js.template web/app.js.template.auth.bak

# Use awk to replace the function
awk -v start="$START_LINE" -v new_func="$NEW_FUNCTION" '
    NR == start {
        print new_func
        in_func = 1
        next
    }
    in_func && /^}/ {
        in_func = 0
        next
    }
    !in_func {
        print
    }
' web/app.js.template.auth.bak > web/app.js.template

echo "✅ Enhanced authentication function applied to app.js.template"
EOF

chmod +x apply-enhanced-auth.sh

echo "⚠️ To apply the enhanced authentication function, run: ./apply-enhanced-auth.sh"
echo "   This script will replace the checkAuthentication function in app.js.template"

echo
echo "✅ Configuration completed successfully!"
echo
echo "Next steps:"
echo "1. Run './apply-enhanced-auth.sh' to update the authentication function (optional but recommended)"
echo "2. Run './step-20-deploy.sh' to deploy your application"
echo "3. After deployment, run './step-22-update-cognito-client.sh' to configure Cognito for implicit flow"
echo
echo "Note: The step-22-update-cognito-client.sh script should be in your repository."
echo "If it's not, you can create it using the provided template."
echo "=================================================="
