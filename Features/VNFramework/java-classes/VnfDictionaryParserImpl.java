// =====================================================
// VNF Dictionary Parser Implementation
// Package: org.apache.cloudstack.network.vnf.impl
// =====================================================

package org.apache.cloudstack.network.vnf.impl;

import org.apache.cloudstack.network.vnf.*;
import org.yaml.snakeyaml.Yaml;
import org.yaml.snakeyaml.error.YAMLException;

import java.util.*;
import java.util.regex.*;

/**
 * Implementation of VNF Dictionary Parser
 * Uses SnakeYAML for parsing and supports template variable substitution
 */
public class VnfDictionaryParserImpl implements VnfDictionaryManager {
    
    private static final Pattern PLACEHOLDER_PATTERN = Pattern.compile("\\$\\{([^}]+)\\}");
    private static final Set<String> REQUIRED_SECTIONS = Set.of("services");
    private static final Set<String> COMMON_OPERATIONS = Set.of("create", "delete", "list");
    
    @Override
    public VnfDictionary parseDictionary(String yaml) throws DictionaryParseException {
        try {
            Yaml yamlParser = new Yaml();
            Map<String, Object> root = yamlParser.load(yaml);
            
            VnfDictionary dictionary = new VnfDictionary();
            dictionary.setYamlContent(yaml);
            
            // Parse metadata
            if (root.containsKey("version")) {
                dictionary.setSchemaVersion(root.get("version").toString());
            } else {
                dictionary.setSchemaVersion("1.0");
            }
            
            if (root.containsKey("vendor")) {
                dictionary.setVendor(root.get("vendor").toString());
            }
            
            if (root.containsKey("product")) {
                dictionary.setProduct(root.get("product").toString());
            }
            
            // Parse access configuration
            if (root.containsKey("access")) {
                AccessConfig accessConfig = parseAccessConfig(
                    (Map<String, Object>) root.get("access")
                );
                dictionary.setAccessConfig(accessConfig);
            }
            
            // Parse services
            if (!root.containsKey("services")) {
                throw new DictionaryParseException("Missing required 'services' section");
            }
            
            Map<String, ServiceDefinition> services = parseServices(
                (Map<String, Object>) root.get("services")
            );
            dictionary.setServices(services);
            
            return dictionary;
            
        } catch (YAMLException e) {
            throw new DictionaryParseException("Invalid YAML syntax: " + e.getMessage());
        } catch (ClassCastException e) {
            throw new DictionaryParseException("Invalid dictionary structure: " + e.getMessage());
        }
    }
    
    /**
     * Parse access configuration section
     */
    private AccessConfig parseAccessConfig(Map<String, Object> accessMap) {
        AccessConfig config = new AccessConfig();
        
        config.setProtocol(getStringValue(accessMap, "protocol", "https"));
        config.setPort(getIntValue(accessMap, "port", 443));
        config.setBasePath(getStringValue(accessMap, "basePath", ""));
        
        // Parse authentication
        String authTypeStr = getStringValue(accessMap, "authType", "none");
        config.setAuthType(AuthType.valueOf(authTypeStr.toUpperCase()));
        
        config.setUsernameRef(getStringValue(accessMap, "usernameRef", null));
        config.setPasswordRef(getStringValue(accessMap, "passwordRef", null));
        config.setTokenRef(getStringValue(accessMap, "tokenRef", null));
        config.setTokenHeader(getStringValue(accessMap, "tokenHeader", "Authorization"));
        
        return config;
    }
    
    /**
     * Parse services section
     */
    private Map<String, ServiceDefinition> parseServices(Map<String, Object> servicesMap) 
            throws DictionaryParseException {
        
        Map<String, ServiceDefinition> services = new HashMap<>();
        
        for (Map.Entry<String, Object> entry : servicesMap.entrySet()) {
            String serviceName = entry.getKey();
            Map<String, Object> serviceMap = (Map<String, Object>) entry.getValue();
            
            ServiceDefinition service = new ServiceDefinition();
            service.setName(serviceName);
            
            Map<String, OperationDefinition> operations = parseOperations(serviceMap);
            service.setOperations(operations);
            
            services.put(serviceName, service);
        }
        
        return services;
    }
    
    /**
     * Parse operations within a service
     */
    private Map<String, OperationDefinition> parseOperations(Map<String, Object> serviceMap) {
        Map<String, OperationDefinition> operations = new HashMap<>();
        
        for (Map.Entry<String, Object> entry : serviceMap.entrySet()) {
            String opName = entry.getKey();
            Map<String, Object> opMap = (Map<String, Object>) entry.getValue();
            
            OperationDefinition operation = new OperationDefinition();
            operation.setMethod(getStringValue(opMap, "method", "GET"));
            operation.setEndpoint(getStringValue(opMap, "endpoint", null));
            operation.setBody(getStringValue(opMap, "body", null));
            
            // Parse headers
            if (opMap.containsKey("headers")) {
                Map<String, Object> headersMap = (Map<String, Object>) opMap.get("headers");
                Map<String, String> headers = new HashMap<>();
                for (Map.Entry<String, Object> h : headersMap.entrySet()) {
                    headers.put(h.getKey(), h.getValue().toString());
                }
                operation.setHeaders(headers);
            }
            
            // Parse response mapping
            if (opMap.containsKey("responseMapping")) {
                ResponseMapping mapping = parseResponseMapping(
                    (Map<String, Object>) opMap.get("responseMapping")
                );
                operation.setResponseMapping(mapping);
            }
            
            // CLI specific
            operation.setSuccessPattern(getStringValue(opMap, "successPattern", null));
            
            operations.put(opName, operation);
        }
        
        return operations;
    }
    
    /**
     * Parse response mapping configuration
     */
    private ResponseMapping parseResponseMapping(Map<String, Object> mappingMap) {
        ResponseMapping mapping = new ResponseMapping();
        
        mapping.setSuccessCode(getIntValue(mappingMap, "successCode", 200));
        mapping.setIdPath(getStringValue(mappingMap, "idPath", null));
        mapping.setListPath(getStringValue(mappingMap, "listPath", null));
        
        // Parse item field mappings
        if (mappingMap.containsKey("item")) {
            Map<String, Object> itemMap = (Map<String, Object>) mappingMap.get("item");
            Map<String, String> itemPaths = new HashMap<>();
            for (Map.Entry<String, Object> entry : itemMap.entrySet()) {
                itemPaths.put(entry.getKey(), entry.getValue().toString());
            }
            mapping.setItemPaths(itemPaths);
        }
        
        return mapping;
    }
    
    @Override
    public DictionaryValidationResult validateDictionary(VnfDictionary dictionary) {
        DictionaryValidationResult result = new DictionaryValidationResult();
        
        // Check version
        if (dictionary.getSchemaVersion() == null) {
            result.addWarning("No schema version specified, assuming 1.0");
        } else if (!dictionary.getSchemaVersion().equals("1.0")) {
            result.addWarning("Schema version " + dictionary.getSchemaVersion() + 
                              " may not be fully supported");
        }
        
        // Check access config
        if (dictionary.getAccessConfig() == null) {
            result.addError("Missing access configuration");
        } else {
            validateAccessConfig(dictionary.getAccessConfig(), result);
        }
        
        // Check services
        if (dictionary.getServices() == null || dictionary.getServices().isEmpty()) {
            result.addError("No services defined");
        } else {
            validateServices(dictionary.getServices(), result);
        }
        
        return result;
    }
    
    /**
     * Validate access configuration
     */
    private void validateAccessConfig(AccessConfig config, DictionaryValidationResult result) {
        if (config.getProtocol() == null) {
            result.addError("Access protocol not specified");
        } else {
            String protocol = config.getProtocol().toLowerCase();
            if (!Set.of("http", "https", "ssh", "telnet").contains(protocol)) {
                result.addError("Unknown protocol: " + protocol);
            }
        }
        
        if (config.getPort() <= 0 || config.getPort() > 65535) {
            result.addError("Invalid port number: " + config.getPort());
        }
        
        // Validate auth references
        AuthType authType = config.getAuthType();
        if (authType == AuthType.BASIC && 
            (config.getUsernameRef() == null || config.getPasswordRef() == null)) {
            result.addWarning("BASIC auth configured but missing username/password references");
        }
        
        if (authType == AuthType.TOKEN && config.getTokenRef() == null) {
            result.addWarning("TOKEN auth configured but missing token reference");
        }
    }
    
    /**
     * Validate services and their operations
     */
    private void validateServices(Map<String, ServiceDefinition> services, 
                                   DictionaryValidationResult result) {
        
        for (Map.Entry<String, ServiceDefinition> entry : services.entrySet()) {
            String serviceName = entry.getKey();
            ServiceDefinition service = entry.getValue();
            
            result.addService(serviceName);
            
            if (service.getOperations() == null || service.getOperations().isEmpty()) {
                result.addWarning("Service '" + serviceName + "' has no operations defined");
                continue;
            }
            
            // Check for create/delete pairs
            boolean hasCreate = service.getOperations().containsKey("create");
            boolean hasDelete = service.getOperations().containsKey("delete");
            
            if (hasCreate && !hasDelete) {
                result.addWarning("Service '" + serviceName + 
                                  "' has 'create' but no 'delete' operation");
            }
            
            // Validate each operation
            for (Map.Entry<String, OperationDefinition> opEntry : 
                 service.getOperations().entrySet()) {
                
                String opName = opEntry.getKey();
                OperationDefinition op = opEntry.getValue();
                
                validateOperation(serviceName, opName, op, result);
            }
        }
    }
    
    /**
     * Validate individual operation
     */
    private void validateOperation(String serviceName, String opName, 
                                    OperationDefinition op, DictionaryValidationResult result) {
        
        if (op.getMethod() == null) {
            result.addError("Service '" + serviceName + "', operation '" + opName + 
                            "': missing method");
            return;
        }
        
        String method = op.getMethod().toUpperCase();
        if (method.equals("SSH") || method.equals("CLI")) {
            // CLI operation - need command
            if (op.getEndpoint() == null || op.getEndpoint().isEmpty()) {
                result.addError("Service '" + serviceName + "', operation '" + opName + 
                                "': missing command for SSH/CLI operation");
            }
        } else {
            // HTTP operation - need endpoint
            if (op.getEndpoint() == null || op.getEndpoint().isEmpty()) {
                result.addError("Service '" + serviceName + "', operation '" + opName + 
                                "': missing endpoint");
            }
            
            // Check HTTP method validity
            if (!Set.of("GET", "POST", "PUT", "DELETE", "PATCH").contains(method)) {
                result.addWarning("Service '" + serviceName + "', operation '" + opName + 
                                  "': unusual HTTP method '" + method + "'");
            }
            
            // POST/PUT should have body
            if ((method.equals("POST") || method.equals("PUT")) && 
                (op.getBody() == null || op.getBody().isEmpty())) {
                result.addWarning("Service '" + serviceName + "', operation '" + opName + 
                                  "': " + method + " operation without body");
            }
        }
        
        // Check for placeholders
        Set<String> placeholders = extractPlaceholders(op);
        if (!placeholders.isEmpty()) {
            // Validate placeholder names (could check against known CloudStack fields)
            for (String placeholder : placeholders) {
                if (!isValidPlaceholder(placeholder)) {
                    result.addWarning("Service '" + serviceName + "', operation '" + opName + 
                                      "': unknown placeholder '${" + placeholder + "}'");
                }
            }
        }
    }
    
    /**
     * Extract all placeholders from an operation
     */
    private Set<String> extractPlaceholders(OperationDefinition op) {
        Set<String> placeholders = new HashSet<>();
        
        if (op.getEndpoint() != null) {
            placeholders.addAll(findPlaceholders(op.getEndpoint()));
        }
        
        if (op.getBody() != null) {
            placeholders.addAll(findPlaceholders(op.getBody()));
        }
        
        if (op.getHeaders() != null) {
            for (String headerValue : op.getHeaders().values()) {
                placeholders.addAll(findPlaceholders(headerValue));
            }
        }
        
        return placeholders;
    }
    
    /**
     * Find all ${...} placeholders in a string
     */
    private Set<String> findPlaceholders(String text) {
        Set<String> placeholders = new HashSet<>();
        Matcher matcher = PLACEHOLDER_PATTERN.matcher(text);
        
        while (matcher.find()) {
            placeholders.add(matcher.group(1));
        }
        
        return placeholders;
    }
    
    /**
     * Check if placeholder name is valid (known CloudStack field)
     */
    private boolean isValidPlaceholder(String name) {
        // Known CloudStack placeholders for various operations
        Set<String> knownPlaceholders = Set.of(
            // Common
            "ruleId", "externalId", "networkId",
            
            // Firewall
            "sourceCidr", "destCidr", "protocol", "startPort", "endPort",
            "publicPort", "icmpType", "icmpCode", "action",
            
            // NAT / Port Forwarding
            "sourceIp", "publicIp", "destIp", "privateIp", "publicPort", "privatePort",
            
            // Load Balancer
            "lbName", "algorithm", "vipId", "memberIp", "memberPort",
            
            // VPN
            "remoteSubnet", "localSubnet", "sharedSecret", "ikePolicy", "ipsecPolicy",
            
            // References to secrets
            "username", "password", "apiKey", "token"
        );
        
        return knownPlaceholders.contains(name);
    }
    
    // Helper methods
    private String getStringValue(Map<String, Object> map, String key, String defaultValue) {
        Object value = map.get(key);
        return value != null ? value.toString() : defaultValue;
    }
    
    private int getIntValue(Map<String, Object> map, String key, int defaultValue) {
        Object value = map.get(key);
        if (value == null) return defaultValue;
        
        if (value instanceof Integer) {
            return (Integer) value;
        }
        
        try {
            return Integer.parseInt(value.toString());
        } catch (NumberFormatException e) {
            return defaultValue;
        }
    }
    
    // Database operations (stub implementations)
    @Override
    public VnfDictionary storeDictionary(VnfDictionary dictionary, Long templateId, Long networkId)
            throws CloudException {
        // Implementation would use DAO to persist to vnf_dictionaries table
        throw new UnsupportedOperationException("Not implemented in this example");
    }
    
    @Override
    public VnfDictionary getDictionary(Long templateId, Long networkId) {
        // Implementation would query vnf_dictionaries table
        throw new UnsupportedOperationException("Not implemented in this example");
    }
    
    @Override
    public boolean deleteDictionary(String uuid) {
        // Implementation would soft-delete from vnf_dictionaries table
        throw new UnsupportedOperationException("Not implemented in this example");
    }
}

/**
 * Template renderer that replaces placeholders with actual values
 */
public class VnfTemplateRenderer {
    
    private static final Pattern PLACEHOLDER_PATTERN = Pattern.compile("\\$\\{([^}]+)\\}");
    
    /**
     * Render a template string with context variables
     */
    public static String render(String template, TemplateContext context) {
        if (template == null) {
            return null;
        }
        
        StringBuffer result = new StringBuffer();
        Matcher matcher = PLACEHOLDER_PATTERN.matcher(template);
        
        while (matcher.find()) {
            String placeholder = matcher.group(1);
            Object value = context.get(placeholder);
            
            String replacement = value != null ? value.toString() : "";
            matcher.appendReplacement(result, Matcher.quoteReplacement(replacement));
        }
        
        matcher.appendTail(result);
        return result.toString();
    }
    
    /**
     * Render and escape for JSON context
     */
    public static String renderJson(String template, TemplateContext context) {
        String rendered = render(template, context);
        // Could add JSON escaping here if needed
        return rendered;
    }
    
    /**
     * Check if template has all required placeholders filled
     */
    public static boolean hasUnresolvedPlaceholders(String rendered) {
        return PLACEHOLDER_PATTERN.matcher(rendered).find();
    }
}
