package org.apache.cloudstack.vnf.utils;

import java.io.FileInputStream;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.security.KeyFactory;
import java.security.PrivateKey;
import java.security.PublicKey;
import java.security.spec.PKCS8EncodedKeySpec;
import java.security.spec.X509EncodedKeySpec;
import java.util.Base64;
import java.util.Date;
import java.util.HashMap;
import java.util.Map;

import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.SignatureAlgorithm;

/**
 * JWT Token Generator and Validator for VNF Broker
 * 
 * Supports both HS256 (shared secret) and RS256 (public/private key) algorithms.
 * 
 * Usage:
 * 
 * HS256 (Development):
 *   String token = JwtTokenGenerator.generateHS256("my-secret", "cloudstack-mgmt", 300);
 * 
 * RS256 (Production):
 *   String token = JwtTokenGenerator.generateRS256("/path/to/private.pem", "cloudstack-mgmt", 300);
 *   boolean valid = JwtTokenGenerator.validateRS256(token, "/path/to/public.pem");
 */
public class JwtTokenGenerator {
    
    /**
     * Generate JWT token using HS256 (shared secret)
     * 
     * @param secret Shared secret key
     * @param subject Token subject (e.g., "cloudstack-mgmt")
     * @param expirySeconds Token validity in seconds
     * @return JWT token string
     */
    public static String generateHS256(String secret, String subject, int expirySeconds) {
        long nowMillis = System.currentTimeMillis();
        Date now = new Date(nowMillis);
        Date expiry = new Date(nowMillis + (expirySeconds * 1000L));
        
        Map<String, Object> claims = new HashMap<>();
        claims.put("scope", "vnf:rw");
        claims.put("issuer", "cloudstack");
        
        return Jwts.builder()
            .setClaims(claims)
            .setSubject(subject)
            .setIssuedAt(now)
            .setExpiration(expiry)
            .signWith(SignatureAlgorithm.HS256, secret.getBytes())
            .compact();
    }
    
    /**
     * Generate JWT token using RS256 (private key)
     * 
     * @param privateKeyPath Path to PEM-encoded private key
     * @param subject Token subject (e.g., "cloudstack-mgmt")
     * @param expirySeconds Token validity in seconds
     * @return JWT token string
     * @throws Exception If key loading or signing fails
     */
    public static String generateRS256(String privateKeyPath, String subject, int expirySeconds) throws Exception {
        PrivateKey privateKey = loadPrivateKey(privateKeyPath);
        
        long nowMillis = System.currentTimeMillis();
        Date now = new Date(nowMillis);
        Date expiry = new Date(nowMillis + (expirySeconds * 1000L));
        
        Map<String, Object> claims = new HashMap<>();
        claims.put("scope", "vnf:rw");
        claims.put("issuer", "cloudstack");
        
        return Jwts.builder()
            .setClaims(claims)
            .setSubject(subject)
            .setIssuedAt(now)
            .setExpiration(expiry)
            .signWith(SignatureAlgorithm.RS256, privateKey)
            .compact();
    }
    
    /**
     * Validate JWT token using RS256 (public key)
     * 
     * @param token JWT token to validate
     * @param publicKeyPath Path to PEM-encoded public key
     * @return true if token is valid, false otherwise
     */
    public static boolean validateRS256(String token, String publicKeyPath) {
        try {
            PublicKey publicKey = loadPublicKey(publicKeyPath);
            
            Jwts.parser()
                .setSigningKey(publicKey)
                .parseClaimsJws(token);
            
            return true;
        } catch (Exception e) {
            return false;
        }
    }
    
    /**
     * Load private key from PEM file
     * 
     * @param filePath Path to PEM file
     * @return PrivateKey object
     * @throws Exception If file reading or key parsing fails
     */
    private static PrivateKey loadPrivateKey(String filePath) throws Exception {
        String pemContent = new String(Files.readAllBytes(Paths.get(filePath)));
        
        // Remove PEM headers and decode Base64
        pemContent = pemContent
            .replace("-----BEGIN PRIVATE KEY-----", "")
            .replace("-----END PRIVATE KEY-----", "")
            .replace("-----BEGIN RSA PRIVATE KEY-----", "")
            .replace("-----END RSA PRIVATE KEY-----", "")
            .replaceAll("\\s", "");
        
        byte[] keyBytes = Base64.getDecoder().decode(pemContent);
        
        PKCS8EncodedKeySpec spec = new PKCS8EncodedKeySpec(keyBytes);
        KeyFactory keyFactory = KeyFactory.getInstance("RSA");
        return keyFactory.generatePrivate(spec);
    }
    
    /**
     * Load public key from PEM file
     * 
     * @param filePath Path to PEM file
     * @return PublicKey object
     * @throws Exception If file reading or key parsing fails
     */
    private static PublicKey loadPublicKey(String filePath) throws Exception {
        String pemContent = new String(Files.readAllBytes(Paths.get(filePath)));
        
        // Remove PEM headers and decode Base64
        pemContent = pemContent
            .replace("-----BEGIN PUBLIC KEY-----", "")
            .replace("-----END PUBLIC KEY-----", "")
            .replaceAll("\\s", "");
        
        byte[] keyBytes = Base64.getDecoder().decode(pemContent);
        
        X509EncodedKeySpec spec = new X509EncodedKeySpec(keyBytes);
        KeyFactory keyFactory = KeyFactory.getInstance("RSA");
        return keyFactory.generatePublic(spec);
    }
    
    /**
     * Main method for testing and command-line usage
     */
    public static void main(String[] args) {
        if (args.length < 1) {
            System.out.println("Usage:");
            System.out.println("  Generate HS256: java JwtTokenGenerator hs256 <secret> [subject] [expiry-seconds]");
            System.out.println("  Generate RS256: java JwtTokenGenerator rs256 <private-key-path> [subject] [expiry-seconds]");
            System.out.println("  Validate RS256: java JwtTokenGenerator validate <token> <public-key-path>");
            System.exit(1);
        }
        
        try {
            String mode = args[0];
            
            if ("hs256".equals(mode)) {
                String secret = args[1];
                String subject = args.length > 2 ? args[2] : "cloudstack-mgmt";
                int expiry = args.length > 3 ? Integer.parseInt(args[3]) : 300;
                
                String token = generateHS256(secret, subject, expiry);
                System.out.println("Generated HS256 Token:");
                System.out.println(token);
                
            } else if ("rs256".equals(mode)) {
                String keyPath = args[1];
                String subject = args.length > 2 ? args[2] : "cloudstack-mgmt";
                int expiry = args.length > 3 ? Integer.parseInt(args[3]) : 300;
                
                String token = generateRS256(keyPath, subject, expiry);
                System.out.println("Generated RS256 Token:");
                System.out.println(token);
                
            } else if ("validate".equals(mode)) {
                String token = args[1];
                String publicKeyPath = args[2];
                
                boolean valid = validateRS256(token, publicKeyPath);
                System.out.println("Token Valid: " + valid);
                System.exit(valid ? 0 : 1);
                
            } else {
                System.out.println("Unknown mode: " + mode);
                System.exit(1);
            }
            
        } catch (Exception e) {
            System.err.println("Error: " + e.getMessage());
            e.printStackTrace();
            System.exit(1);
        }
    }
}
