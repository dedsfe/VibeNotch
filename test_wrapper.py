#!/usr/bin/env python3
import socket
import json
import time
import sys

def send_to_notch(type_str, message=""):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        s.connect(("127.0.0.1", 8123))
    except ConnectionRefusedError:
        print("🚨 BoringNotch app is not running or listening on port 8123.")
        return None

    msg = json.dumps({"type": type_str, "message": message})
    s.sendall(msg.encode('utf-8'))
    
    # Wait for response if it's a prompt
    if type_str == "prompt":
        print(f"⏳ Sent prompt to Notch... waiting for user to click Allow/Deny")
        response = s.recv(1024).decode('utf-8').strip()
        return response
    else:
        # Just close for messages
        s.close()
        return None

if __name__ == "__main__":
    print("🤖 Claude Code (Wrapper Mock) is starting...")
    
    # Send a message to Notch without buttons
    send_to_notch("message", "I am thinking about how to solve your task...")
    time.sleep(4)
    
    # Send another message
    send_to_notch("message", "Reading files in your project...")
    time.sleep(3)
    
    print("\n⚠️  The AI wants to execute a command!")
    # Send a prompt to Notch with buttons
    answer = send_to_notch("prompt", "Do you want to allow this command? 'rm -rf /' [Y/n]")
    
    if answer and answer.lower() == "y":
        print("✅ Command was APPROVED via Notch!")
        send_to_notch("message", "Command executing! Please wait...")
        time.sleep(2)
    else:
        print("❌ Command was DENIED via Notch!")
        send_to_notch("message", "Command was denied. Continuing...")
        time.sleep(2)
        
    # Tell Notch to close the UI
    send_to_notch("close")
    print("👋 Done!")
