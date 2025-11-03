// =====================================================
// VNF Framework - Java Class Structure and Interfaces
// Package: org.apache.cloudstack.network.vnf
// =====================================================
// This file defines the core Java interfaces and classes for the VNF framework.
// Actual implementation would be split across multiple files in a real project.

package org.apache.cloudstack.network.vnf;

import java.util.*;
import com.cloud.network.Network;
import com.cloud.network.element.NetworkElement;
import com.cloud.exception.*;
import com.cloud.vm.VirtualMachine;
import com.cloud.offering.NetworkOffering;

// =====================================================
// 1. CORE INTERFACES
// =====================================================

/**
 * Main interface for VNF network provider
 * Implements CloudStack's network element interfaces for various services
 */
public interface VnfProvider extends NetworkElement, 
                                      FirewallServiceProvider,
                                      PortForwardingServiceProvider,
                                      StaticNatServiceProvider,
                                      LoadBalancingServiceProvider {
    
    /**
     * Check if this provider can handle the given network
     */
    boolean canHandle(Network network);
    
    /**
     * Deploy a VNF appliance for a network
     */
    VnfAppliance deployVnfAppliance(Network network, VnfTemplate template) 
        throws CloudException;
    
    /**
     * Destroy a VNF appliance
     */
    boolean destroyVnfAppliance(VnfAppliance appliance) 
        throws CloudException;
    
    /**
     * Get VNF appliance for a network
     */
    VnfAppliance getVnfApplianceForNetwork(long networkId);
    
    /**
     * Test connectivity to VNF device
     */
    VnfConnectivityResult testConnectivity(VnfAppliance appliance) 
        throws CloudException;
    
    /**
     * Reconcile network state with VNF device
     */
    VnfReconciliationResult reconcileNetwork(Network network, boolean dryRun) 
        throws CloudException;
}

/**
 * Dictionary management interface
 */
public interface VnfDictionaryManager {
    
    /**
     * Load and parse a YAML dictionary
     */
    VnfDictionary parseDictionary(String yaml) 
        throws DictionaryParseException;
    
    /**
     * Validate dictionary structure and contents
     */
    DictionaryValidationResult validateDictionary(VnfDictionary dictionary);
    
    /**
     * Store dictionary in database
     */
    VnfDictionary storeDictionary(VnfDictionary dictionary, Long templateId, Long networkId)
        throws CloudException;
    
    /**
     * Get dictionary for template or network
     */
    VnfDictionary getDictionary(Long templateId, Long networkId);
    
    /**
     * Delete dictionary
     */
    boolean deleteDictionary(String uuid);
}

/**
 * Request builder that translates CloudStack operations to VNF commands
 */
public interface VnfRequestBuilder {
    
    /**
     * Build a request for a firewall rule operation
     */
    VnfRequest buildFirewallRequest(
        VnfDictionary dictionary,
        FirewallRuleOperation operation,
        FirewallRule rule
    ) throws RequestBuildException;
    
    /**
     * Build a request for NAT operation
     */
    VnfRequest buildNatRequest(
        VnfDictionary dictionary,
        NatOperation operation,
        PortForwardingRule rule
    ) throws RequestBuildException;
    
    /**
     * Build a request for load balancer operation
     */
    VnfRequest buildLoadBalancerRequest(
        VnfDictionary dictionary,
        LoadBalancerOperation operation,
        LoadBalancingRule rule
    ) throws RequestBuildException;
    
    /**
     * Build a list request to query device state
     */
    VnfRequest buildListRequest(
        VnfDictionary dictionary,
        String serviceName
    ) throws RequestBuildException;
}

/**
 * Broker client interface for communicating with VNF via VR or direct
 */
public interface VnfBrokerClient {
    
    /**
     * Send a request to VNF device and get response
     */
    VnfResponse sendRequest(VnfAppliance appliance, VnfRequest request)
        throws CommunicationException;
    
    /**
     * Send request with retry logic
     */
    VnfResponse sendRequestWithRetry(
        VnfAppliance appliance,
        VnfRequest request,
        int maxRetries
    ) throws CommunicationException;
    
    /**
     * Test basic connectivity
     */
    boolean isReachable(VnfAppliance appliance);
    
    /**
     * Get broker type (VR, Direct, External)
     */
    BrokerType getBrokerType();
}

/**
 * Response parser interface
 */
public interface VnfResponseParser {
    
    /**
     * Parse response and extract external ID
     */
    String extractExternalId(VnfResponse response, VnfDictionary dictionary, String operation);
    
    /**
     * Parse list response into structured data
     */
    List<VnfDeviceRule> parseListResponse(
        VnfResponse response,
        VnfDictionary dictionary,
        String serviceName
    );
    
    /**
     * Check if response indicates success
     */
    boolean isSuccess(VnfResponse response, VnfDictionary dictionary, String operation);
    
    /**
     * Extract error message from response
     */
    String extractErrorMessage(VnfResponse response);
}

// =====================================================
// 2. DATA MODELS
// =====================================================

/**
 * Represents a VNF dictionary
 */
public class VnfDictionary {
    private String id;
    private String uuid;
    private Long templateId;
    private Long networkId;
    private String name;
    private String yamlContent;
    private String schemaVersion;
    private String vendor;
    private String product;
    private Date created;
    private Date updated;
    
    // Parsed structure
    private AccessConfig accessConfig;
    private Map<String, ServiceDefinition> services;
    
    // Getters and setters
    public String getId() { return id; }
    public void setId(String id) { this.id = id; }
    
    public String getSchemaVersion() { return schemaVersion; }
    public void setSchemaVersion(String version) { this.schemaVersion = version; }
    
    public AccessConfig getAccessConfig() { return accessConfig; }
    public void setAccessConfig(AccessConfig config) { this.accessConfig = config; }
    
    public Map<String, ServiceDefinition> getServices() { return services; }
    public void setServices(Map<String, ServiceDefinition> services) { this.services = services; }
    
    public ServiceDefinition getService(String name) { return services.get(name); }
}

/**
 * Access configuration from dictionary
 */
public class AccessConfig {
    private String protocol;  // "https", "ssh", "http"
    private int port;
    private String basePath;
    private AuthType authType;
    private String usernameRef;
    private String passwordRef;
    private String tokenRef;
    private String tokenHeader;
    
    // Getters and setters
    public String getProtocol() { return protocol; }
    public void setProtocol(String protocol) { this.protocol = protocol; }
    
    public int getPort() { return port; }
    public void setPort(int port) { this.port = port; }
    
    public AuthType getAuthType() { return authType; }
    public void setAuthType(AuthType authType) { this.authType = authType; }
}

/**
 * Service definition (e.g., Firewall, NAT)
 */
public class ServiceDefinition {
    private String name;
    private Map<String, OperationDefinition> operations;
    
    public OperationDefinition getOperation(String opName) {
        return operations.get(opName);
    }
    
    public void setOperations(Map<String, OperationDefinition> ops) {
        this.operations = ops;
    }
}

/**
 * Operation definition (e.g., create, delete, list)
 */
public class OperationDefinition {
    private String method;       // HTTP method or "SSH"
    private String endpoint;     // URL path or CLI command
    private String body;         // Request body template
    private Map<String, String> headers;
    private ResponseMapping responseMapping;
    private String successPattern;  // For CLI responses
    
    // Getters and setters
    public String getMethod() { return method; }
    public void setMethod(String method) { this.method = method; }
    
    public String getEndpoint() { return endpoint; }
    public void setEndpoint(String endpoint) { this.endpoint = endpoint; }
    
    public String getBody() { return body; }
    public void setBody(String body) { this.body = body; }
    
    public ResponseMapping getResponseMapping() { return responseMapping; }
    public void setResponseMapping(ResponseMapping mapping) { this.responseMapping = mapping; }
}

/**
 * Response mapping configuration
 */
public class ResponseMapping {
    private int successCode = 200;
    private String idPath;           // JSONPath to extract ID
    private String listPath;         // JSONPath to list of items
    private Map<String, String> itemPaths;  // Field mappings
    
    public int getSuccessCode() { return successCode; }
    public void setSuccessCode(int code) { this.successCode = code; }
    
    public String getIdPath() { return idPath; }
    public void setIdPath(String path) { this.idPath = path; }
}

/**
 * Represents a VNF appliance instance
 */
public class VnfAppliance {
    private Long id;
    private String uuid;
    private Long vmInstanceId;
    private Long networkId;
    private Long templateId;
    private Long dictionaryId;
    private String managementIp;
    private String guestIp;
    private String publicIp;
    private Long brokerVmId;
    private VnfState state;
    private HealthStatus healthStatus;
    private Date lastContact;
    private Date created;
    
    // Lazy-loaded associations
    private VirtualMachine vmInstance;
    private Network network;
    private VnfDictionary dictionary;
    
    // Getters and setters
    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }
    
    public String getUuid() { return uuid; }
    public void setUuid(String uuid) { this.uuid = uuid; }
    
    public Long getVmInstanceId() { return vmInstanceId; }
    public void setVmInstanceId(Long id) { this.vmInstanceId = id; }
    
    public String getManagementIp() { return managementIp; }
    public void setManagementIp(String ip) { this.managementIp = ip; }
    
    public VnfState getState() { return state; }
    public void setState(VnfState state) { this.state = state; }
    
    public HealthStatus getHealthStatus() { return healthStatus; }
    public void setHealthStatus(HealthStatus status) { this.healthStatus = status; }
}

/**
 * VNF request to be sent to device
 */
public class VnfRequest {
    private String targetIp;
    private String protocol;
    private String method;
    private String uri;
    private Map<String, String> headers;
    private String body;
    private int timeoutSeconds;
    private String jwtToken;  // For broker authorization
    
    // Getters and setters
    public String getTargetIp() { return targetIp; }
    public void setTargetIp(String ip) { this.targetIp = ip; }
    
    public String getProtocol() { return protocol; }
    public void setProtocol(String protocol) { this.protocol = protocol; }
    
    public String getMethod() { return method; }
    public void setMethod(String method) { this.method = method; }
    
    public String getUri() { return uri; }
    public void setUri(String uri) { this.uri = uri; }
    
    public Map<String, String> getHeaders() { return headers; }
    public void setHeaders(Map<String, String> headers) { this.headers = headers; }
    
    public String getBody() { return body; }
    public void setBody(String body) { this.body = body; }
    
    public String getJwtToken() { return jwtToken; }
    public void setJwtToken(String token) { this.jwtToken = token; }
}

/**
 * VNF response from device
 */
public class VnfResponse {
    private int statusCode;
    private String body;
    private Map<String, String> headers;
    private long durationMs;
    private boolean success;
    private String errorMessage;
    
    // Getters and setters
    public int getStatusCode() { return statusCode; }
    public void setStatusCode(int code) { this.statusCode = code; }
    
    public String getBody() { return body; }
    public void setBody(String body) { this.body = body; }
    
    public boolean isSuccess() { return success; }
    public void setSuccess(boolean success) { this.success = success; }
    
    public long getDurationMs() { return durationMs; }
    public void setDurationMs(long ms) { this.durationMs = ms; }
}

/**
 * Device rule structure from list operation
 */
public class VnfDeviceRule {
    private String externalId;
    private String serviceName;  // "Firewall", "NAT", etc.
    private Map<String, Object> properties;
    
    public String getExternalId() { return externalId; }
    public void setExternalId(String id) { this.externalId = id; }
    
    public Map<String, Object> getProperties() { return properties; }
    public void setProperty(String key, Object value) { properties.put(key, value); }
}

/**
 * Reconciliation result
 */
public class VnfReconciliationResult {
    private boolean success;
    private boolean driftDetected;
    private int rulesChecked;
    private int missingRules;
    private int extraRules;
    private int rulesReapplied;
    private int rulesRemoved;
    private List<ReconciliationAction> actions;
    private String errorMessage;
    
    // Getters and setters
    public boolean isDriftDetected() { return driftDetected; }
    public void setDriftDetected(boolean detected) { this.driftDetected = detected; }
    
    public int getMissingRules() { return missingRules; }
    public void setMissingRules(int count) { this.missingRules = count; }
    
    public List<ReconciliationAction> getActions() { return actions; }
    public void addAction(ReconciliationAction action) { actions.add(action); }
}

/**
 * Individual reconciliation action
 */
public class ReconciliationAction {
    private String service;
    private ActionType actionType;
    private String ruleId;
    private String description;
    
    public enum ActionType {
        REAPPLIED, REMOVED, FLAGGED, NO_ACTION
    }
    
    public ReconciliationAction(String service, ActionType type, String ruleId, String desc) {
        this.service = service;
        this.actionType = type;
        this.ruleId = ruleId;
        this.description = desc;
    }
}

/**
 * Connectivity test result
 */
public class VnfConnectivityResult {
    private boolean reachable;
    private long latencyMs;
    private String method;
    private int responseCode;
    private String message;
    
    public boolean isReachable() { return reachable; }
    public void setReachable(boolean reachable) { this.reachable = reachable; }
    
    public long getLatencyMs() { return latencyMs; }
    public void setLatencyMs(long ms) { this.latencyMs = ms; }
}

// =====================================================
// 3. ENUMERATIONS
// =====================================================

public enum VnfState {
    DEPLOYING,
    RUNNING,
    STOPPED,
    ERROR,
    DESTROYED
}

public enum HealthStatus {
    HEALTHY,
    UNHEALTHY,
    UNKNOWN
}

public enum AuthType {
    NONE,
    BASIC,
    TOKEN,
    SSH_KEY,
    SSH_PASSWORD
}

public enum BrokerType {
    VIRTUAL_ROUTER,
    DIRECT,
    EXTERNAL_CONTROLLER
}

public enum FirewallRuleOperation {
    CREATE, DELETE, LIST
}

public enum NatOperation {
    CREATE, DELETE, LIST
}

public enum LoadBalancerOperation {
    CREATE, DELETE, UPDATE, LIST
}

// =====================================================
// 4. EXCEPTIONS
// =====================================================

public class DictionaryParseException extends CloudException {
    private List<String> errors;
    
    public DictionaryParseException(String message) {
        super(message);
    }
    
    public DictionaryParseException(String message, List<String> errors) {
        super(message);
        this.errors = errors;
    }
    
    public List<String> getErrors() { return errors; }
}

public class RequestBuildException extends CloudException {
    public RequestBuildException(String message) {
        super(message);
    }
    
    public RequestBuildException(String message, Throwable cause) {
        super(message, cause);
    }
}

public class CommunicationException extends CloudException {
    private boolean retriable;
    
    public CommunicationException(String message, boolean retriable) {
        super(message);
        this.retriable = retriable;
    }
    
    public boolean isRetriable() { return retriable; }
}

// =====================================================
// 5. VALIDATION RESULT
// =====================================================

public class DictionaryValidationResult {
    private boolean valid;
    private List<String> errors;
    private List<String> warnings;
    private List<String> servicesFound;
    
    public DictionaryValidationResult() {
        this.errors = new ArrayList<>();
        this.warnings = new ArrayList<>();
        this.servicesFound = new ArrayList<>();
        this.valid = true;
    }
    
    public boolean isValid() { return valid && errors.isEmpty(); }
    public void setValid(boolean valid) { this.valid = valid; }
    
    public List<String> getErrors() { return errors; }
    public void addError(String error) { 
        errors.add(error);
        valid = false;
    }
    
    public List<String> getWarnings() { return warnings; }
    public void addWarning(String warning) { warnings.add(warning); }
    
    public List<String> getServicesFound() { return servicesFound; }
    public void addService(String service) { servicesFound.add(service); }
}

// =====================================================
// 6. HELPER CLASSES
// =====================================================

/**
 * Template rendering context with placeholders
 */
public class TemplateContext {
    private Map<String, Object> variables;
    
    public TemplateContext() {
        this.variables = new HashMap<>();
    }
    
    public void set(String key, Object value) {
        variables.put(key, value);
    }
    
    public Object get(String key) {
        return variables.get(key);
    }
    
    public Map<String, Object> getAll() {
        return variables;
    }
}

/**
 * JWT token generator for broker authorization
 */
public interface JwtTokenGenerator {
    
    /**
     * Generate JWT token for VNF request
     */
    String generateToken(
        VnfAppliance appliance,
        String operation,
        int expirySeconds
    );
    
    /**
     * Validate JWT token
     */
    boolean validateToken(String token);
}
