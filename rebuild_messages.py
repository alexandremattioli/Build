import json
from datetime import datetime

def rebuild_messages():
    messages_file = 'coordination/messages.json'
    backup_file = f'coordination/messages_rebuild_backup_{datetime.now().strftime("%Y%m%d_%H%M%S")}.json'
    
    print(f"Reading {messages_file}...")
    
    with open(messages_file, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    
    print(f"Total lines: {len(lines)}")
    
    # Backup
    print(f"Backing up to {backup_file}...")
    with open(backup_file, 'w', encoding='utf-8') as f:
        f.writelines(lines)
    
    # Remove conflict markers and their sections
    # Line 10228 is ======= (index 10227)
    # Line 10240 is >>>>>>> (index 10239)
    # We want to keep everything except the section between ======= and >>>>>>>
    
    # Find ALL conflict markers
    conflicts = []
    i = 0
    while i < len(lines):
        line = lines[i].strip()
        if line == '=======':
            # Found a separator, look for the end marker
            separator_idx = i
            end_idx = None
            for j in range(i+1, min(i+100, len(lines))):  # Look ahead up to 100 lines
                if lines[j].strip().startswith('>>>>>>>'):
                    end_idx = j
                    break
            
            if end_idx:
                conflicts.append((separator_idx, end_idx))
                print(f"Found conflict: lines {separator_idx+1} to {end_idx+1}")
                i = end_idx + 1
            else:
                i += 1
        else:
            i += 1
    
    if conflicts:
        print(f"Total conflicts found: {len(conflicts)}")
        
        # Remove all conflict sections (work backwards to preserve indices)
        new_lines = lines[:]
        for separator_line, end_marker_line in reversed(conflicts):
            print(f"Removing lines {separator_line+1} to {end_marker_line+1}")
            new_lines = new_lines[:separator_line] + new_lines[end_marker_line+1:]
        
        # Write back
        print("Writing cleaned content...")
        with open(messages_file, 'w', encoding='utf-8') as f:
            f.writelines(new_lines)
        
        # Verify
        print("Verifying JSON...")
        try:
            with open(messages_file, 'r', encoding='utf-8') as f:
                data = json.load(f)
            
            messages = data.get('messages', [])
            print(f"SUCCESS! Loaded {len(messages)} messages")
            
            # Clean up duplicates
            seen_ids = set()
            unique_messages = []
            duplicates = 0
            
            for msg in messages:
                msg_id = msg.get('id')
                if msg_id and msg_id not in seen_ids:
                    seen_ids.add(msg_id)
                    unique_messages.append(msg)
                elif msg_id:
                    duplicates += 1
            
            if duplicates > 0:
                print(f"Removing {duplicates} duplicate messages...")
                data['messages'] = unique_messages
                with open(messages_file, 'w', encoding='utf-8') as f:
                    json.dump(data, f, indent=2)
                print(f"Final count: {len(unique_messages)} unique messages")
            
            return True
            
        except json.JSONDecodeError as e:
            print(f"JSON error: {e}")
            print("Restoring backup...")
            with open(backup_file, 'r', encoding='utf-8') as f:
                original_lines = f.readlines()
            with open(messages_file, 'w', encoding='utf-8') as f:
                f.writelines(original_lines)
            return False
    else:
        print("Could not find conflict markers!")
        return False

if __name__ == '__main__':
    rebuild_messages()
