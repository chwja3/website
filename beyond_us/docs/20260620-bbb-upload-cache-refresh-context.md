# BBB upload cache refresh context

The user saw this Supabase Storage error.

```json
{"statusCode":"400","error":"InvalidKey","message":"Invalid key: BBB_missions/듀듀/m2/1781933218819_be5cs5ynas9.jpg"}
```

The local and remote `app.js?v=20260620e` files already use `storageUserPathPart(currentNickname)`, which produces `user_{hash}` path segments instead of raw nicknames. Therefore the observed request was produced by a stale client bundle. This change bumps the app version and service-worker cache version so clients are prompted to load the fresh bundle.
