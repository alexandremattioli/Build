import json

try:
    with open('coordination/messages.json', 'r') as f:
        data = json.load(f)
    
    # Handle both array and object with "messages" key
    if isinstance(data, dict) and 'messages' in data:
        messages = data['messages']
    elif isinstance(data, list):
        messages = data
    else:
        print(f"Unexpected data structure: {type(data)}")
        messages = []
    
    print(f"Messages loaded: {len(messages)}")
    if messages:
        print(f"Last message ID: {messages[-1].get('id', 'NO ID')}")
        print(f"Last message timestamp: {messages[-1].get('timestamp', 'NO TIMESTAMP')}")
    print("JSON is valid!")
except json.JSONDecodeError as e:
    print(f"JSON ERROR: {e}")
except Exception as e:
    print(f"ERROR: {e}")
