"""
VNF Broker Dictionary Engine
Loads vendor YAML dictionaries and executes templated API calls
"""
import yaml
import httpx
import json
from typing import Dict, Any, Optional
from jinja2 import Template
from jsonpath_ng import parse
import logging

logger = logging.getLogger(__name__)


class DictionaryEngine:
    """Engine for loading and executing vendor-specific API dictionaries"""
    
    def __init__(self, dictionary_path: str):
        """
        Initialize dictionary engine
        
        Args:
            dictionary_path: Path to YAML dictionary file
        """
        with open(dictionary_path, 'r') as f:
            self.dictionary = yaml.safe_load(f)
        
        self.vendor = self.dictionary.get('vendor')
        self.api_base_url_template = Template(self.dictionary.get('api_base_url', ''))
        self.timeout = self.dictionary.get('timeout_seconds', 30)
        self.retry_attempts = self.dictionary.get('retry_attempts', 3)
        
        logger.info(f"Loaded dictionary for vendor: {self.vendor}")
    
    def get_api_base_url(self, context: Dict[str, Any]) -> str:
        """Render API base URL with context variables"""
        return self.api_base_url_template.render(**context)
    
    def get_auth_config(self, context: Dict[str, Any]) -> Dict[str, Any]:
        """Get authentication configuration"""
        auth_config = self.dictionary.get('authentication', {})
        auth_type = auth_config.get('type')
        
        if auth_type == 'basic':
            creds = auth_config.get('credentials', {})
            username_template = Template(creds.get('username', ''))
            password_template = Template(creds.get('password', ''))
            return {
                'type': 'basic',
                'username': username_template.render(**context),
                'password': password_template.render(**context)
            }
        elif auth_type == 'bearer':
            token_template = Template(auth_config.get('token', ''))
            return {
                'type': 'bearer',
                'token': token_template.render(**context)
            }
        
        return {'type': 'none'}
    
    async def execute_operation(
        self,
        operation_name: str,
        context: Dict[str, Any]
    ) -> Dict[str, Any]:
        """
        Execute a VNF operation using the dictionary
        
        Args:
            operation_name: Name of operation (e.g., 'create_firewall_rule')
            context: Context variables for templating
            
        Returns:
            Response dictionary with vendor_ref, success, error_code, message
        """
        operations = self.dictionary.get('operations', {})
        operation_def = operations.get(operation_name)
        
        if not operation_def:
            raise ValueError(f"Operation '{operation_name}' not found in dictionary")
        
        # Build request
        method = operation_def['method']
        endpoint_template = Template(operation_def['endpoint'])
        endpoint = endpoint_template.render(**context)
        
        # Render request body
        request_template_str = operation_def.get('request_template', '{}')
        request_template = Template(request_template_str)
        request_body_str = request_template.render(**context)
        request_body = json.loads(request_body_str) if request_body_str.strip() else {}
        
        # Get auth
        auth_config = self.get_auth_config(context)
        base_url = self.get_api_base_url(context)
        full_url = base_url + endpoint
        
        # Build headers
        headers = {'Content-Type': 'application/json'}
        if auth_config['type'] == 'bearer':
            headers['Authorization'] = f"Bearer {auth_config['token']}"
        
        # Execute HTTP request
        logger.info(f"Executing {method} {full_url}")
        
        async with httpx.AsyncClient(timeout=self.timeout, verify=False) as client:
            auth = None
            if auth_config['type'] == 'basic':
                auth = (auth_config['username'], auth_config['password'])
            
            response = await client.request(
                method=method,
                url=full_url,
                json=request_body if method in ['POST', 'PUT', 'PATCH'] else None,
                headers=headers,
                auth=auth
            )
        
        # Parse response
        result = self._parse_response(operation_def, response, context)
        
        # Execute post-operation hooks
        if result.get('success'):
            await self._execute_hooks(operation_name, context)
        
        return result
    
    def _parse_response(
        self,
        operation_def: Dict[str, Any],
        response: httpx.Response,
        context: Dict[str, Any]
    ) -> Dict[str, Any]:
        """Parse HTTP response using dictionary mappings"""
        response_mapping = operation_def.get('response_mapping', {})
        error_mapping = operation_def.get('error_mapping', {})
        
        status_code = response.status_code
        
        # Check for errors
        if status_code >= 400:
            error_code = error_mapping.get(status_code, 'VNF_UPSTREAM')
            try:
                error_data = response.json()
                error_message = error_data.get('message', response.text)
            except:
                error_message = response.text
            
            return {
                'success': False,
                'error_code': error_code,
                'message': error_message,
                'vendor_ref': None
            }
        
        # Parse success response
        try:
            response_data = response.json()
        except:
            response_data = {'text': response.text}
        
        # Extract vendor reference using JSONPath
        vendor_ref = None
        if 'vendor_ref' in response_mapping:
            jsonpath_expr = parse(response_mapping['vendor_ref'])
            matches = jsonpath_expr.find(response_data)
            if matches:
                vendor_ref = str(matches[0].value)
        
        # Check success indicator
        success = True
        if 'success_indicator' in response_mapping:
            success_expr = response_mapping['success_indicator']
            # Simple evaluation (in production, use safer method)
            try:
                # Replace $ with response_data reference
                eval_expr = success_expr.replace('$.', 'response_data.')
                success = eval(eval_expr)
            except:
                success = status_code < 300
        
        return {
            'success': success,
            'vendor_ref': vendor_ref,
            'message': 'Operation completed successfully',
            'error_code': None
        }
    
    async def _execute_hooks(
        self,
        operation_name: str,
        context: Dict[str, Any]
    ):
        """Execute post-operation hooks"""
        hooks = self.dictionary.get('post_operation_hooks', [])
        
        for hook in hooks:
            # Check condition
            condition = hook.get('condition', '')
            if condition:
                condition_template = Template(condition)
                should_execute = eval(condition_template.render(operation=operation_name))
                if not should_execute:
                    continue
            
            # Execute hook
            method = hook['method']
            endpoint_template = Template(hook['endpoint'])
            endpoint = endpoint_template.render(**context)
            
            base_url = self.get_api_base_url(context)
            full_url = base_url + endpoint
            
            logger.info(f"Executing hook: {method} {full_url}")
            
            try:
                auth_config = self.get_auth_config(context)
                headers = {'Content-Type': 'application/json'}
                
                async with httpx.AsyncClient(timeout=self.timeout, verify=False) as client:
                    auth = None
                    if auth_config['type'] == 'basic':
                        auth = (auth_config['username'], auth_config['password'])
                    
                    response = await client.request(
                        method=method,
                        url=full_url,
                        headers=headers,
                        auth=auth
                    )
                    
                    if response.status_code >= 400 and not hook.get('ignore_errors', False):
                        logger.warning(f"Hook failed: {response.text}")
            except Exception as e:
                if not hook.get('ignore_errors', False):
                    logger.error(f"Hook execution error: {e}")
                    raise
    
    async def health_check(self, context: Dict[str, Any]) -> bool:
        """Execute health check against VNF"""
        health_config = self.dictionary.get('health_check')
        if not health_config:
            return True
        
        endpoint_template = Template(health_config['endpoint'])
        endpoint = endpoint_template.render(**context)
        method = health_config.get('method', 'GET')
        
        base_url = self.get_api_base_url(context)
        full_url = base_url + endpoint
        
        try:
            auth_config = self.get_auth_config(context)
            headers = {}
            
            timeout = health_config.get('timeout_seconds', 5)
            
            async with httpx.AsyncClient(timeout=timeout, verify=False) as client:
                auth = None
                if auth_config['type'] == 'basic':
                    auth = (auth_config['username'], auth_config['password'])
                
                response = await client.request(
                    method=method,
                    url=full_url,
                    headers=headers,
                    auth=auth
                )
                
                # Check success indicator
                success_indicator = health_config.get('success_indicator')
                if success_indicator:
                    response_data = response.json()
                    eval_expr = success_indicator.replace('$.', 'response_data.')
                    return eval(eval_expr)
                
                return response.status_code < 300
        except Exception as e:
            logger.error(f"Health check failed: {e}")
            return False
