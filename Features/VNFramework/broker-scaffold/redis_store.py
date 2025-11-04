"""
Redis-based idempotency store for VNF Broker
Replaces in-memory store for production deployment
"""
import redis
import json
import logging
from typing import Optional, Dict, Any
from datetime import timedelta

logger = logging.getLogger(__name__)


class RedisIdempotencyStore:
    """Redis-backed idempotency store with TTL support"""
    
    def __init__(self, redis_url: str = "redis://localhost:6379/0", ttl_hours: int = 24):
        """
        Initialize Redis store
        
        Args:
            redis_url: Redis connection URL
            ttl_hours: Time-to-live for cached responses in hours
        """
        self.client = redis.from_url(redis_url, decode_responses=True)
        self.ttl = timedelta(hours=ttl_hours)
        logger.info(f"Connected to Redis: {redis_url}")
    
    def _make_key(self, rule_id: str) -> str:
        """Generate Redis key for rule ID"""
        return f"vnf:idempotency:{rule_id}"
    
    def get(self, rule_id: str) -> Optional[Dict[str, Any]]:
        """
        Get cached response for rule ID
        
        Args:
            rule_id: The rule ID to lookup
            
        Returns:
            Cached response dict or None if not found/expired
        """
        try:
            key = self._make_key(rule_id)
            data = self.client.get(key)
            
            if data:
                logger.info(f"Cache HIT for rule_id: {rule_id}")
                return json.loads(data)
            
            logger.debug(f"Cache MISS for rule_id: {rule_id}")
            return None
            
        except redis.RedisError as e:
            logger.error(f"Redis GET error: {e}")
            return None
    
    def set(self, rule_id: str, response: Dict[str, Any]) -> bool:
        """
        Store response for rule ID with TTL
        
        Args:
            rule_id: The rule ID
            response: Response dict to cache
            
        Returns:
            True if stored successfully
        """
        try:
            key = self._make_key(rule_id)
            data = json.dumps(response)
            
            self.client.setex(
                name=key,
                time=self.ttl,
                value=data
            )
            
            logger.info(f"Cached response for rule_id: {rule_id} (TTL: {self.ttl})")
            return True
            
        except redis.RedisError as e:
            logger.error(f"Redis SET error: {e}")
            return False
    
    def delete(self, rule_id: str) -> bool:
        """
        Delete cached response for rule ID
        
        Args:
            rule_id: The rule ID to delete
            
        Returns:
            True if deleted
        """
        try:
            key = self._make_key(rule_id)
            result = self.client.delete(key)
            
            if result:
                logger.info(f"Deleted cache for rule_id: {rule_id}")
            
            return bool(result)
            
        except redis.RedisError as e:
            logger.error(f"Redis DELETE error: {e}")
            return False
    
    def exists(self, rule_id: str) -> bool:
        """Check if rule ID exists in cache"""
        try:
            key = self._make_key(rule_id)
            return bool(self.client.exists(key))
        except redis.RedisError as e:
            logger.error(f"Redis EXISTS error: {e}")
            return False
    
    def get_ttl(self, rule_id: str) -> Optional[int]:
        """Get remaining TTL in seconds for rule ID"""
        try:
            key = self._make_key(rule_id)
            ttl = self.client.ttl(key)
            return ttl if ttl > 0 else None
        except redis.RedisError as e:
            logger.error(f"Redis TTL error: {e}")
            return None
    
    def clear_all(self) -> int:
        """
        Clear all idempotency cache entries (USE WITH CAUTION)
        
        Returns:
            Number of keys deleted
        """
        try:
            pattern = "vnf:idempotency:*"
            keys = self.client.keys(pattern)
            
            if keys:
                count = self.client.delete(*keys)
                logger.warning(f"Cleared {count} idempotency cache entries")
                return count
            
            return 0
            
        except redis.RedisError as e:
            logger.error(f"Redis CLEAR error: {e}")
            return 0
    
    def get_stats(self) -> Dict[str, Any]:
        """Get cache statistics"""
        try:
            pattern = "vnf:idempotency:*"
            keys = self.client.keys(pattern)
            
            info = self.client.info("stats")
            
            return {
                "cached_rules": len(keys),
                "total_keys": info.get("db0", {}).get("keys", 0),
                "hits": info.get("keyspace_hits", 0),
                "misses": info.get("keyspace_misses", 0),
                "hit_rate": info.get("keyspace_hits", 0) / (info.get("keyspace_hits", 0) + info.get("keyspace_misses", 1)) * 100
            }
            
        except redis.RedisError as e:
            logger.error(f"Redis STATS error: {e}")
            return {"error": str(e)}
    
    def health_check(self) -> bool:
        """Check Redis connection health"""
        try:
            return self.client.ping()
        except redis.RedisError:
            return False


class FallbackIdempotencyStore:
    """
    Fallback in-memory store when Redis is unavailable
    NOT for production use - loses data on restart
    """
    
    def __init__(self, ttl_hours: int = 24):
        self.store: Dict[str, Dict[str, Any]] = {}
        self.ttl_hours = ttl_hours
        logger.warning("Using in-memory fallback store - not suitable for production!")
    
    def get(self, rule_id: str) -> Optional[Dict[str, Any]]:
        """Get from in-memory store"""
        if rule_id in self.store:
            logger.info(f"Memory cache HIT for rule_id: {rule_id}")
            return self.store[rule_id]
        return None
    
    def set(self, rule_id: str, response: Dict[str, Any]) -> bool:
        """Store in memory"""
        self.store[rule_id] = response
        logger.info(f"Stored in memory for rule_id: {rule_id}")
        return True
    
    def delete(self, rule_id: str) -> bool:
        """Delete from memory"""
        if rule_id in self.store:
            del self.store[rule_id]
            return True
        return False
    
    def exists(self, rule_id: str) -> bool:
        """Check existence in memory"""
        return rule_id in self.store
    
    def get_ttl(self, rule_id: str) -> Optional[int]:
        """TTL not implemented for fallback"""
        return None
    
    def clear_all(self) -> int:
        """Clear all entries"""
        count = len(self.store)
        self.store.clear()
        return count
    
    def get_stats(self) -> Dict[str, Any]:
        """Get basic stats"""
        return {"cached_rules": len(self.store), "backend": "in-memory"}
    
    def health_check(self) -> bool:
        """Always healthy"""
        return True


def create_idempotency_store(redis_url: Optional[str] = None, ttl_hours: int = 24):
    """
    Factory function to create idempotency store
    
    Args:
        redis_url: Redis connection URL (None = fallback to in-memory)
        ttl_hours: TTL for cached entries
        
    Returns:
        RedisIdempotencyStore or FallbackIdempotencyStore
    """
    if redis_url:
        try:
            store = RedisIdempotencyStore(redis_url, ttl_hours)
            if store.health_check():
                logger.info("Using Redis idempotency store")
                return store
            else:
                logger.warning("Redis health check failed, using fallback")
        except Exception as e:
            logger.error(f"Failed to connect to Redis: {e}, using fallback")
    
    return FallbackIdempotencyStore(ttl_hours)
