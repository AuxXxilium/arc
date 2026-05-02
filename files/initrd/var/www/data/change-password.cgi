#!/usr/bin/env python3
"""
Change Password CGI script for Arc Web Config
Updates user password in /etc/shadow
"""

import cgi
import cgitb
import json
import sys
import subprocess
import os

# Enable debugging (remove in production)
cgitb.enable()

def send_json_response(data):
    """Send JSON response with proper headers"""
    print("Content-Type: application/json")
    print("Cache-Control: no-cache, no-store, must-revalidate")
    print("Pragma: no-cache")
    print("Expires: 0")
    print()
    print(json.dumps(data))

def verify_password(username, password):
    """Verify password using crypt"""
    try:
        with open('/etc/shadow', 'r') as f:
            for line in f:
                parts = line.strip().split(':')
                if parts[0] == username and len(parts) >= 2:
                    shadow_hash = parts[1]
                    if shadow_hash and shadow_hash not in ['*', '!', '!!']:
                        import crypt
                        result = crypt.crypt(password, shadow_hash)
                        return result == shadow_hash
    except Exception as e:
        print(f"Error verifying password: {e}", file=sys.stderr)
    return False

def change_password(username, new_password):
    """Change user password using passwd command"""
    try:
        # BusyBox/embedded systems often use simpler passwd
        # Try: echo -e "newpass\nnewpass" | passwd username
        process = subprocess.Popen(
            ['passwd', username],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )
        
        # passwd expects password entered twice
        passwd_input = f"{new_password}\n{new_password}\n"
        stdout, stderr = process.communicate(input=passwd_input, timeout=5)
        
        if process.returncode == 0 or "success" in stdout.lower() or "success" in stderr.lower():
            return True, "Password changed successfully"
        else:
            # Try alternative method with shell
            try:
                result = subprocess.run(
                    f"echo -e '{new_password}\\n{new_password}' | passwd {username}",
                    shell=True,
                    capture_output=True,
                    text=True,
                    timeout=5
                )
                
                if result.returncode == 0 or "success" in result.stdout.lower() or "success" in result.stderr.lower():
                    return True, "Password changed successfully"
                else:
                    return False, f"Failed to change password: {result.stderr}"
            except Exception as e:
                return False, f"passwd command failed: {str(e)}"


            
    except Exception as e:
        return False, f"Error changing password: {str(e)}"

def main():
    """Main CGI handler"""
    
    # Parse form data
    form = cgi.FieldStorage()
    username = form.getvalue('username', '').strip()
    current_password = form.getvalue('currentPassword', '')
    new_password = form.getvalue('newPassword', '')
    
    # Validate input
    if not username or not current_password or not new_password:
        send_json_response({
            'success': False,
            'message': 'All fields are required'
        })
        return
    
    # Validate new password length
    if len(new_password) < 4:
        send_json_response({
            'success': False,
            'message': 'Password must be at least 4 characters'
        })
        return
    
    # Verify current password
    if not verify_password(username, current_password):
        send_json_response({
            'success': False,
            'message': 'Current password is incorrect'
        })
        return
    
    # Change password
    success, message = change_password(username, new_password)
    
    send_json_response({
        'success': success,
        'message': message
    })

if __name__ == '__main__':
    main()
