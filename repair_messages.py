import json
import os
from datetime import datetime, timedelta

def repair_messages():
    messages_file = 'coordination/messages.json'
    backup_file = f'coordination/messages_backup_{datetime.now().strftime("%Y%m%d_%H%M%S")}.json'
    
    print(f"Reading {messages_file}...")
    
    # Read raw file content
    with open(messages_file, 'r') as f:
        content = f.read()
    
    print(f"File size: {len(content)} bytes")
    
    # Try to find the last valid message before corruption
    # Strategy: Parse character by character until we hit valid JSON
    valid_messages = []
    
    # File uses {"messages": [...]} structure, not direct array
    # Try to find where it breaks
    try:
        # First, let's extract just up to the corruption point
        # Read line by line until error position
        lines = content.split('\n')
        print(f"Total lines: {len(lines)}")
        
        # Build content up to line 10205 (before corruption at 10206)
        partial_content = '\n'.join(lines[:10205])
        
        # Try to close the structure properly
        # Remove trailing comma if exists
        partial_content = partial_content.rstrip().rstrip(',')
        
        # Add closing brackets
        if not partial_content.endswith(']}'):
            partial_content += '\n  ]\n}'
        
        print("Attempting to parse partial content...")
        data = json.loads(partial_content)
        
        if 'messages' in data:
            valid_messages = data['messages']
            print(f"Successfully extracted {len(valid_messages)} messages")
        else:
            print("ERROR: No 'messages' key found in parsed data")
            return False
            
    except Exception as e:
        print(f"Parse error: {e}")
        # If that fails, try even more aggressive truncation
        print("Trying alternative repair method...")
        
        # Find the last complete message object
        # Search backwards for pattern "},\n    {"
        pos = content.rfind('},\n    {')
        if pos == -1:
            pos = content.rfind('},')
        
        if pos > 0:
            partial_content = content[:pos+1]  # Include the closing }
            partial_content += '\n  ]\n}'
            
            try:
                data = json.loads(partial_content)
                if 'messages' in data:
                    valid_messages = data['messages']
                    print(f"Alternative method: extracted {len(valid_messages)} messages")
                else:
                    return False
            except Exception as e2:
                print(f"Alternative method also failed: {e2}")
                return False
        else:
            return False
    
    if not valid_messages:
        print("ERROR: Could not find any valid messages!")
        return False
    
    print(f"Total valid messages found: {len(valid_messages)}")
    
    # Keep only recent messages (last 500)
    cutoff_count = 500
    if len(valid_messages) > cutoff_count:
        print(f"Archiving old messages, keeping last {cutoff_count}...")
        archived_messages = valid_messages[:-cutoff_count]
        valid_messages = valid_messages[-cutoff_count:]
        
        # Save archived messages
        archive_file = f'coordination/messages_archive_{datetime.now().strftime("%Y%m%d")}.json'
        with open(archive_file, 'w') as f:
            json.dump(archived_messages, f, indent=2)
        print(f"Archived {len(archived_messages)} messages to {archive_file}")
    
    # Backup original
    print(f"Backing up original to {backup_file}...")
    os.rename(messages_file, backup_file)
    
    # Write repaired messages
    print(f"Writing {len(valid_messages)} messages to {messages_file}...")
    with open(messages_file, 'w') as f:
        json.dump({"messages": valid_messages}, f, indent=2)
    
    print("Repair complete!")
    print(f"Messages retained: {len(valid_messages)}")
    if valid_messages:
        print(f"Oldest message: {valid_messages[0]['id']} at {valid_messages[0]['timestamp']}")
        print(f"Newest message: {valid_messages[-1]['id']} at {valid_messages[-1]['timestamp']}")
    
    return True

if __name__ == '__main__':
    repair_messages()
