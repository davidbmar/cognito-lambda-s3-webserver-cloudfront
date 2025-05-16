// Configuration - to be updated after deployment do not edit.
const config = {
    userPoolId: 'us-east-2_xGof4XEwA',
    userPoolClientId: '5klu3u1d9em86f62hhj2r0nvg7',
    identityPoolId: 'us-east-2:5a42d5a1-2101-4197-973d-f6c86254bba2',
    region: 'us-east-2', // Your AWS region
    apiUrl: 'https://7qgztkr7xe.execute-api.us-east-2.amazonaws.com/dev/data',
    appUrl: 'http://cloudfront-cognito-app-dbm-website-dev-821850226835.s3-website.us-east-2.amazonaws.com' // This will be replaced during deployment
};

// DOM elements
const loginButton = document.getElementById('login-button');
const logoutButton = document.getElementById('logout-button');
const getDataButton = document.getElementById('get-data-button');
const userEmailSpan = document.getElementById('user-email');
const dataOutput = document.getElementById('data-output');
const loginSection = document.getElementById('login-section');
const authenticatedSection = document.getElementById('authenticated-section');

// Check if user is authenticated
function checkAuthentication() {
    const idToken = localStorage.getItem('id_token');
    
    if (idToken) {
        // User is authenticated
        loginSection.style.display = 'none';
        authenticatedSection.style.display = 'block';
        
        // Parse the JWT token to get the email
        const payload = JSON.parse(atob(idToken.split('.')[1]));
        userEmailSpan.textContent = payload.email;
    } else {
        // User is not authenticated
        loginSection.style.display = 'block';
        authenticatedSection.style.display = 'none';
    }
}

// Initialize when page loads
document.addEventListener('DOMContentLoaded', function() {
    checkAuthentication();
    
    // Set up event listeners
    loginButton.addEventListener('click', login);
    logoutButton.addEventListener('click', logout);
    getDataButton.addEventListener('click', getData);
});

// Login function
function login() {
    const authUrl = `https://${config.userPoolId.split('_')[0]}.auth.${config.region}.amazoncognito.com/login`;
    const redirectUri = `${config.appUrl}/callback.html`;
    
    const queryParams = new URLSearchParams({
        client_id: config.userPoolClientId,
        response_type: 'token',
        scope: 'email openid profile',
        redirect_uri: redirectUri,
    });
    
    window.location.href = `${authUrl}?${queryParams.toString()}`;
}

// Logout function
function logout() {
    localStorage.removeItem('id_token');
    localStorage.removeItem('access_token');
    checkAuthentication();
}

// Get data from Lambda function
async function getData() {
    const idToken = localStorage.getItem('id_token');
    
    if (!idToken) {
        dataOutput.textContent = 'You must be logged in to access the API.';
        return;
    }
    
    try {
        const response = await fetch(config.apiUrl, {
            headers: {
                'Authorization': `Bearer ${idToken}`
            }
        });
        
        if (!response.ok) {
            throw new Error(`API request failed: ${response.status}`);
        }
        
        const data = await response.json();
        dataOutput.textContent = JSON.stringify(data, null, 2);
    } catch (error) {
        dataOutput.textContent = `Error: ${error.message}`;
    }
}
