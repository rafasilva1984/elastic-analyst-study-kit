# KQL Cheat Sheet

## Igualdade
```
status_code : 500
```

## Intervalo
```
status_code >= 500
```

## Lista de valores
```
host.name : ("server01" or "server02")
```

## Combinando condições
```
service.name : "api-gateway" and status_code >= 400
```
