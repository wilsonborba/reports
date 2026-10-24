//! Temporary cache in Redis/Valkey (namespace `reports:`). Redis is never a source of truth:
//! every failure is a cache miss with a warning, and the durable stores still answer.

use std::collections::{HashMap, HashSet};
use std::sync::Mutex;
use std::time::{Duration, Instant};

use async_trait::async_trait;
use redis::aio::{ConnectionManager, ConnectionManagerConfig};
use redis::{AsyncCommands, Script};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LockState {
    /// This caller holds the lock.
    Acquired,
    /// Another caller holds the lock.
    Busy,
    /// Redis does not answer: the caller computes without a distributed lock.
    Unavailable,
}

#[async_trait]
pub trait CacheStore: Send + Sync {
    async fn get(&self, key: &str) -> Option<String>;
    async fn set(&self, key: &str, value: &str, ttl_secs: u64);
    async fn delete(&self, key: &str);
    /// Adds `key` to the dependency set `tag` (the set expires with the longest entry).
    async fn tag(&self, tag: &str, key: &str, ttl_secs: u64);
    /// Deletes every key in the dependency set `tag` and the set. Returns the number of keys.
    async fn invalidate_tag(&self, tag: &str) -> usize;
    async fn try_lock(&self, key: &str, token: &str, ttl_secs: u64) -> LockState;
    async fn unlock(&self, key: &str, token: &str);
    async fn health(&self) -> bool;
}

// --- Redis ------------------------------------------------------------------

/// Seconds between two reconnect attempts after Redis failed.
const RECONNECT_PAUSE: Duration = Duration::from_secs(15);

pub struct RedisCache {
    client: redis::Client,
    namespace: String,
    connection: tokio::sync::Mutex<Option<ConnectionManager>>,
    last_failure: Mutex<Option<Instant>>,
}

impl RedisCache {
    pub fn new(url: &str, namespace: &str) -> Result<Self, redis::RedisError> {
        Ok(Self {
            client: redis::Client::open(url)?,
            namespace: namespace.to_string(),
            connection: tokio::sync::Mutex::new(None),
            last_failure: Mutex::new(None),
        })
    }

    fn key(&self, key: &str) -> String {
        format!("{}{}", self.namespace, key)
    }

    /// A live connection, or None while Redis is down (no retry storm).
    async fn connection(&self) -> Option<ConnectionManager> {
        let mut guard = self.connection.lock().await;
        if let Some(c) = guard.as_ref() {
            return Some(c.clone());
        }
        if let Some(t) = *self.last_failure.lock().unwrap() {
            if t.elapsed() < RECONNECT_PAUSE {
                return None;
            }
        }
        let config = ConnectionManagerConfig::new()
            .set_connection_timeout(Duration::from_secs(2))
            .set_response_timeout(Duration::from_secs(2))
            .set_number_of_retries(1);
        match self.client.get_connection_manager_with_config(config).await {
            Ok(c) => {
                *guard = Some(c.clone());
                *self.last_failure.lock().unwrap() = None;
                Some(c)
            }
            Err(e) => {
                tracing::warn!("Redis is unavailable, using no cache: {}", e);
                *self.last_failure.lock().unwrap() = Some(Instant::now());
                None
            }
        }
    }

    fn failed(&self, op: &str, e: redis::RedisError) {
        tracing::warn!("Redis {} failed (treated as a cache miss): {}", op, e);
        *self.last_failure.lock().unwrap() = Some(Instant::now());
    }
}

#[async_trait]
impl CacheStore for RedisCache {
    async fn get(&self, key: &str) -> Option<String> {
        let mut c = self.connection().await?;
        match c.get::<_, Option<String>>(self.key(key)).await {
            Ok(v) => v,
            Err(e) => {
                self.failed("GET", e);
                None
            }
        }
    }

    async fn set(&self, key: &str, value: &str, ttl_secs: u64) {
        if let Some(mut c) = self.connection().await {
            if let Err(e) = c.set_ex::<_, _, ()>(self.key(key), value, ttl_secs).await {
                self.failed("SET", e);
            }
        }
    }

    async fn delete(&self, key: &str) {
        if let Some(mut c) = self.connection().await {
            if let Err(e) = c.del::<_, ()>(self.key(key)).await {
                self.failed("DEL", e);
            }
        }
    }

    async fn tag(&self, tag: &str, key: &str, ttl_secs: u64) {
        if let Some(mut c) = self.connection().await {
            let set = self.key(&format!("dep:{tag}"));
            let result: redis::RedisResult<()> = redis::pipe()
                .sadd(&set, self.key(key))
                .ignore()
                .expire(&set, ttl_secs as i64)
                .ignore()
                .query_async(&mut c)
                .await;
            if let Err(e) = result {
                self.failed("SADD", e);
            }
        }
    }

    async fn invalidate_tag(&self, tag: &str) -> usize {
        let Some(mut c) = self.connection().await else {
            return 0;
        };
        let set = self.key(&format!("dep:{tag}"));
        let members: Vec<String> = match c.smembers(&set).await {
            Ok(m) => m,
            Err(e) => {
                self.failed("SMEMBERS", e);
                return 0;
            }
        };
        let mut keys = members.clone();
        keys.push(set);
        if let Err(e) = c.del::<_, ()>(keys).await {
            self.failed("DEL", e);
            return 0;
        }
        members.len()
    }

    async fn try_lock(&self, key: &str, token: &str, ttl_secs: u64) -> LockState {
        let Some(mut c) = self.connection().await else {
            return LockState::Unavailable;
        };
        let result: redis::RedisResult<Option<String>> = redis::cmd("SET")
            .arg(self.key(&format!("gate:{key}")))
            .arg(token)
            .arg("NX")
            .arg("EX")
            .arg(ttl_secs)
            .query_async(&mut c)
            .await;
        match result {
            Ok(Some(_)) => LockState::Acquired,
            Ok(None) => LockState::Busy,
            Err(e) => {
                self.failed("SET NX", e);
                LockState::Unavailable
            }
        }
    }

    async fn unlock(&self, key: &str, token: &str) {
        if let Some(mut c) = self.connection().await {
            // Deletes the lock only when this caller still owns it.
            let script = Script::new(
                "if redis.call('get', KEYS[1]) == ARGV[1] then return redis.call('del', KEYS[1]) else return 0 end",
            );
            let result: redis::RedisResult<i64> = script
                .key(self.key(&format!("gate:{key}")))
                .arg(token)
                .invoke_async(&mut c)
                .await;
            if let Err(e) = result {
                self.failed("unlock", e);
            }
        }
    }

    async fn health(&self) -> bool {
        match self.connection().await {
            Some(mut c) => redis::cmd("PING").query_async::<String>(&mut c).await.is_ok(),
            None => false,
        }
    }
}

// --- in-process cache for tests ---------------------------------------------

/// Test double with TTL, tags and locks. Not used in production.
#[derive(Default)]
pub struct MemoryCache {
    values: Mutex<HashMap<String, (String, Instant)>>,
    tags: Mutex<HashMap<String, HashSet<String>>>,
    locks: Mutex<HashMap<String, (String, Instant)>>,
    pub offline: std::sync::atomic::AtomicBool,
    pub hits: std::sync::atomic::AtomicUsize,
    pub misses: std::sync::atomic::AtomicUsize,
}

impl MemoryCache {
    fn online(&self) -> bool {
        !self.offline.load(std::sync::atomic::Ordering::SeqCst)
    }

    pub fn len(&self) -> usize {
        self.values.lock().unwrap().len()
    }

    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }
}

#[async_trait]
impl CacheStore for MemoryCache {
    async fn get(&self, key: &str) -> Option<String> {
        use std::sync::atomic::Ordering::SeqCst;
        if !self.online() {
            return None;
        }
        let mut values = self.values.lock().unwrap();
        let hit = match values.get(key) {
            Some((v, until)) if Instant::now() < *until => Some(v.clone()),
            Some(_) => {
                values.remove(key);
                None
            }
            None => None,
        };
        if hit.is_some() {
            self.hits.fetch_add(1, SeqCst);
        } else {
            self.misses.fetch_add(1, SeqCst);
        }
        hit
    }

    async fn set(&self, key: &str, value: &str, ttl_secs: u64) {
        if self.online() {
            self.values
                .lock()
                .unwrap()
                .insert(key.to_string(), (value.to_string(), Instant::now() + Duration::from_secs(ttl_secs)));
        }
    }

    async fn delete(&self, key: &str) {
        self.values.lock().unwrap().remove(key);
    }

    async fn tag(&self, tag: &str, key: &str, _ttl_secs: u64) {
        if self.online() {
            self.tags.lock().unwrap().entry(tag.to_string()).or_default().insert(key.to_string());
        }
    }

    async fn invalidate_tag(&self, tag: &str) -> usize {
        if !self.online() {
            return 0;
        }
        let keys = self.tags.lock().unwrap().remove(tag).unwrap_or_default();
        let mut values = self.values.lock().unwrap();
        for k in &keys {
            values.remove(k);
        }
        keys.len()
    }

    async fn try_lock(&self, key: &str, token: &str, ttl_secs: u64) -> LockState {
        if !self.online() {
            return LockState::Unavailable;
        }
        let mut locks = self.locks.lock().unwrap();
        match locks.get(key) {
            Some((_, until)) if Instant::now() < *until => LockState::Busy,
            _ => {
                locks.insert(key.to_string(), (token.to_string(), Instant::now() + Duration::from_secs(ttl_secs)));
                LockState::Acquired
            }
        }
    }

    async fn unlock(&self, key: &str, token: &str) {
        let mut locks = self.locks.lock().unwrap();
        if locks.get(key).map(|(t, _)| t == token).unwrap_or(false) {
            locks.remove(key);
        }
    }

    async fn health(&self) -> bool {
        self.online()
    }
}
