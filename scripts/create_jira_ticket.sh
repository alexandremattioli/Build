#!/bin/bash

# Load Jira configuration
source ~/.config/jira/config
JIRA_TOKEN=$(cat ~/.config/jira/api_token)

# Ticket details
SUMMARY="$1"
DESCRIPTION="$2"
ISSUE_TYPE="${3:-Task}"

if [ -z "$SUMMARY" ]; then
    echo "Usage: $0 <summary> [description] [issue_type]"
    exit 1
fi

# Create Jira ticket
curl -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: Basic $(echo -n "${JIRA_EMAIL}:${JIRA_TOKEN}" | base64)" \
  "${JIRA_URL}/rest/api/3/issue" \
  -d "{
    \"fields\": {
      \"project\": {
        \"key\": \"${JIRA_PROJECT}\"
      },
      \"summary\": \"${SUMMARY}\",
      \"description\": {
        \"type\": \"doc\",
        \"version\": 1,
        \"content\": [
          {
            \"type\": \"paragraph\",
            \"content\": [
              {
                \"type\": \"text\",
                \"text\": \"${DESCRIPTION:-Test ticket created via API}\"
              }
            ]
          }
        ]
      },
      \"issuetype\": {
        \"name\": \"${ISSUE_TYPE}\"
      }
    }
  }"
