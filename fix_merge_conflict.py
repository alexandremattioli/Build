import json
import re
from datetime import datetime

def remove_merge_conflicts():
    messages_file = 'coordination/messages.json'
    backup_file = f'coordination/messages_backup_{datetime.now().strftime("%Y%m%d_%H%M%S")}.json'
    
    print(f"Reading {messages_file}...")
    
    with open(messages_file, 'r') as f:
        content = f.read()
    
    print(f"File size: {len(content)} bytes")
    
    # Backup original
    print(f"Backing up to {backup_file}...")
    with open(backup_file, 'w') as f:
        f.write(content)
    
    # Find merge conflict markers
    if '<<<<<<< HEAD' in content:
        print("Found merge conflict markers!")
        
        # Strategy: Keep the HEAD version (before =======)
        # Remove everything from <<<<<<< HEAD to >>>>>>> [hash]
        
        # Pattern: <<<<<<< HEAD\n(content)\n=======\n(content)\n>>>>>>> hash
        pattern = r',?\s*\{\s*<<<<<<< HEAD.*?>>>>>>> [a-f0-9]+\s*\}'
        
        # First, let's extract the conflict section manually
        start_marker = content.find('<<<<<<< HEAD')
        end_marker = content.find('>>>>>>>')
        
        if start_marker != -1 and end_marker != -1:
            # Find the end of the merge marker line
            end_line = content.find('\n', end_marker)
            
            print(f"Conflict section: {start_marker} to {end_line}")
            print(f"Content before: ...{content[start_marker-50:start_marker]}")
            print(f"Conflict marker: {content[start_marker:start_marker+100]}")
            
            # Extract HEAD section (between <<<<<<< HEAD and =======)
            middle_marker = content.find('=======', start_marker)
            head_section = content[start_marker:middle_marker]
            
            # Remove the <<<<<<< HEAD line
            head_section = head_section.replace('<<<<<<< HEAD\n', '').strip()
            
            # Find the opening { before the conflict
            brace_pos = content.rfind('{', 0, start_marker)
            
            # Extract the full HEAD message
            head_message_start = brace_pos
            head_message_content = head_section
            
            # Parse the HEAD message to ensure it's complete
            print(f"HEAD section length: {len(head_section)} chars")
            
            # Build new content: everything before conflict + HEAD section + everything after
            # Find the complete bracketed section
            before_conflict = content[:head_message_start]
            after_conflict = content[end_line+1:]
            
            # Clean up the HEAD section - extract just the message object
            # It should be between { and }
            head_start = content.find('{', start_marker-500)
            head_content = content[head_start:middle_marker].strip()
            
            # Remove the merge marker
            head_content = head_content.replace('<<<<<<< HEAD\n', '').strip()
            
            # Reconstruct
            new_content = content[:head_start] + head_content + after_conflict
            
            # Write repaired content
            print("Writing repaired file...")
            with open(messages_file, 'w') as f:
                f.write(new_content)
            
            # Verify it parses
            print("Verifying repair...")
            try:
                with open(messages_file, 'r') as f:
                    data = json.load(f)
                print(f"SUCCESS! Loaded {len(data.get('messages', []))} messages")
                return True
            except Exception as e:
                print(f"Verification failed: {e}")
                print("Restoring backup...")
                with open(backup_file, 'r') as f:
                    original = f.read()
                with open(messages_file, 'w') as f:
                    f.write(original)
                return False
    else:
        print("No merge conflict markers found")
        return False

if __name__ == '__main__':
    remove_merge_conflicts()
