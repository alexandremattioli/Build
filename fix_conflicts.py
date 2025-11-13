import json
import re
from datetime import datetime

def fix_merge_conflicts():
    messages_file = 'coordination/messages.json'
    backup_file = f'coordination/messages_backup_{datetime.now().strftime("%Y%m%d_%H%M%S")}.json'
    
    print(f"Reading {messages_file}...")
    
    with open(messages_file, 'r', encoding='utf-8') as f:
        content = f.read()
    
    print(f"File size: {len(content)} bytes")
    
    # Backup
    print(f"Backing up to {backup_file}...")
    with open(backup_file, 'w', encoding='utf-8') as f:
        f.write(content)
    
    # Find all conflict markers
    conflicts = []
    pos = 0
    while True:
        head_pos = content.find('<<<<<<< HEAD', pos)
        if head_pos == -1:
            break
        
        mid_pos = content.find('=======', head_pos)
        end_pos = content.find('>>>>>>>', mid_pos)
        end_line = content.find('\n', end_pos)
        
        conflicts.append((head_pos, mid_pos, end_line))
        pos = end_line + 1
    
    print(f"Found {len(conflicts)} merge conflicts")
    
    if not conflicts:
        print("No conflicts to fix!")
        return
    
    # Fix conflicts by keeping the HEAD version (first part)
    # Work backwards to preserve positions
    new_content = content
    for head_pos, mid_pos, end_line in reversed(conflicts):
        print(f"Fixing conflict at position {head_pos}")
        
        # Extract HEAD section (between <<<<<<< HEAD and =======)
        head_section = new_content[head_pos:mid_pos]
        # Remove the <<<<<<< HEAD marker line
        head_section = head_section.split('\n', 1)[1] if '\n' in head_section else head_section
        
        # Replace entire conflict block with just the HEAD section
        new_content = new_content[:head_pos] + head_section + new_content[end_line+1:]
    
    # Clean up any duplicate fields that might have been introduced
    print("Cleaning up duplicate fields...")
    
    # Write fixed content
    print(f"Writing fixed content...")
    with open(messages_file, 'w', encoding='utf-8') as f:
        f.write(new_content)
    
    # Verify JSON
    print("Verifying JSON structure...")
    try:
        with open(messages_file, 'r', encoding='utf-8') as f:
            data = json.load(f)
        
        messages = data.get('messages', [])
        print(f"SUCCESS! Loaded {len(messages)} messages")
        
        # Remove duplicates if any
        seen_ids = set()
        unique_messages = []
        duplicates = 0
        
        for msg in messages:
            msg_id = msg.get('id')
            if msg_id not in seen_ids:
                seen_ids.add(msg_id)
                unique_messages.append(msg)
            else:
                duplicates += 1
        
        if duplicates > 0:
            print(f"Removing {duplicates} duplicate messages...")
            data['messages'] = unique_messages
            with open(messages_file, 'w', encoding='utf-8') as f:
                json.dump(data, f, indent=2)
            print(f"Final count: {len(unique_messages)} unique messages")
        
        return True
        
    except json.JSONDecodeError as e:
        print(f"JSON verification failed: {e}")
        print("Restoring backup...")
        with open(backup_file, 'r', encoding='utf-8') as f:
            original = f.read()
        with open(messages_file, 'w', encoding='utf-8') as f:
            f.write(original)
        return False

if __name__ == '__main__':
    fix_merge_conflicts()
