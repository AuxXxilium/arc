#!/usr/bin/env python3
"""
Authentication CGI script for Arc Web Config
Handles login, logout, and session verification against /etc/shadow
"""

import cgi
import cgitb
import json
import os
import sys
import hashlib
import time
from pathlib import Path

# Enable debugging (remove in production)
cgitb.enable()

# Session storage directory
SESSION_DIR = '/tmp/arc_sessions'
SESSION_LIFETIME = 86400  # 24 hours in seconds

def read_shadow_entry(username):
    """Read password hash from /etc/shadow for given username"""
    try:
        with open('/etc/shadow', 'r') as f:
            for line in f:
                parts = line.strip().split(':')
                if parts[0] == username and len(parts) >= 2:
                    return parts[1]  # Return the password hash
    except PermissionError:
        return None
    except FileNotFoundError:
        return None
    return None

def verify_password(username, password):
    """Verify password against /etc/shadow entry"""
    shadow_hash = read_shadow_entry(username)
    
    if not shadow_hash or shadow_hash in ['*', '!', '!!']:
        return False
    
    # Import crypt for password verification
    try:
        import crypt
        # Verify the password using crypt
        result = crypt.crypt(password, shadow_hash)
        return result == shadow_hash
    except Exception as e:
        print(f"Error verifying password: {e}", file=sys.stderr)
        return False

def create_session_token(username):
    """Create a secure session token"""
    timestamp = str(time.time())
    random_data = os.urandom(32).hex()
    token_source = f"{username}{timestamp}{random_data}"
    token = hashlib.sha256(token_source.encode()).hexdigest()
    return token

def save_session(username, token):
    """Save session to filesystem"""
    try:
        Path(SESSION_DIR).mkdir(parents=True, exist_ok=True)
        session_file = os.path.join(SESSION_DIR, token)
        
        with open(session_file, 'w') as f:
            f.write(f"{username}\n{int(time.time())}\n")
        
        # Set restrictive permissions
        os.chmod(session_file, 0o600)
        return True
    except Exception as e:
        print(f"Error saving session: {e}", file=sys.stderr)
        return False

def verify_session(username, token):
    """Verify if session token is valid"""
    try:
        session_file = os.path.join(SESSION_DIR, token)
        
        if not os.path.exists(session_file):
            return False
        
        with open(session_file, 'r') as f:
            stored_username = f.readline().strip()
            timestamp = int(f.readline().strip())
        
        # Check if session belongs to the user and hasn't expired
        current_time = int(time.time())
        if stored_username == username and (current_time - timestamp) < SESSION_LIFETIME:
            return True
        else:
            # Session expired, remove it
            os.remove(session_file)
            return False
            
    except Exception as e:
        print(f"Error verifying session: {e}", file=sys.stderr)
        return False

def delete_session(token):
    """Delete session file"""
    try:
        session_file = os.path.join(SESSION_DIR, token)
        if os.path.exists(session_file):
            os.remove(session_file)
        return True
    except Exception as e:
        print(f"Error deleting session: {e}", file=sys.stderr)
        return False

def cleanup_expired_sessions():
    """Remove expired session files"""
    try:
        if not os.path.exists(SESSION_DIR):
            return
        
        current_time = int(time.time())
        for filename in os.listdir(SESSION_DIR):
            session_file = os.path.join(SESSION_DIR, filename)
            try:
                with open(session_file, 'r') as f:
                    f.readline()  # Skip username
                    timestamp = int(f.readline().strip())
                
                if (current_time - timestamp) >= SESSION_LIFETIME:
                    os.remove(session_file)
            except:
                pass
    except Exception as e:
        print(f"Error cleaning up sessions: {e}", file=sys.stderr)

def send_json_response(data):
    """Send JSON response with proper headers"""
    print("Content-Type: application/json")
    print("Cache-Control: no-cache, no-store, must-revalidate")
    print("Pragma: no-cache")
    print("Expires: 0")
    print()
    print(json.dumps(data))

def main():
    """Main CGI handler"""
    
    # Clean up expired sessions periodically
    cleanup_expired_sessions()
    
    # Parse form data
    form = cgi.FieldStorage()
    action = form.getvalue('action', '')
    
    if action == 'login':
        username = form.getvalue('username', '').strip()
        password = form.getvalue('password', '')
        
        if not username or not password:
            send_json_response({
                'success': False,
                'message': 'Username and password are required'
            })
            return
        
        # Verify credentials
        if verify_password(username, password):
            # Create session
            token = create_session_token(username)
            if save_session(username, token):
                send_json_response({
                    'success': True,
                    'token': token,
                    'username': username
                })
            else:
                send_json_response({
                    'success': False,
                    'message': 'Failed to create session'
                })
        else:
            send_json_response({
                'success': False,
                'message': 'Invalid username or password'
            })
    
    elif action == 'verify':
        username = form.getvalue('username', '').strip()
        token = form.getvalue('token', '').strip()
        
        if not username or not token:
            send_json_response({'success': False})
            return
        
        if verify_session(username, token):
            send_json_response({'success': True})
        else:
            send_json_response({'success': False})
    
    elif action == 'logout':
        token = form.getvalue('token', '').strip()
        
        if token:
            delete_session(token)
        
        send_json_response({'success': True})
    
    else:
        send_json_response({
            'success': False,
            'message': 'Invalid action'
        })

if __name__ == '__main__':
    main()
