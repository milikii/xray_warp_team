# Deprecation Timeline Template

## Field: `oldFieldName`

| Event | Version | Date | Details |
|-------|---------|------|---------|
| Introduced | v1.0.0 | YYYY-MM-DD | Initial support |
| Deprecated | v1.5.0 | YYYY-MM-DD | Use `newFieldName` instead |
| Removed | v1.8.0 | YYYY-MM-DD | Config rejected if present |

### Migration Path
```json
{
  "old": { "oldFieldName": "value" },
  "new": { "newFieldName": "value" }
}
```

### Source References
- Deprecation commit: `abc1234`
- Removal commit: `def5678`
- Release note: https://github.com/XTLS/Xray-core/releases/tag/v1.5.0

---

*Use one file per deprecated/removed field or feature.*
