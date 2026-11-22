# Prueba integrada con Postman

Colección: `BarrioDigital-Prueba-Integrada.postman_collection.json` (18 peticiones con tests automáticos).

Prueba el flujo completo: **BFF → requests → catalog** (reserva de cupo) y **requests → Kafka → audit**.
Lo que Postman no puede ver (mensajes dentro de Kafka) se revisa por consola en el paso 4.

---

## 1. Levantar todo

Cada uno en su terminal (ver README principal de `barriodigital-infra`):

| Servicio | Puerto | Comando |
|----------|--------|---------|
| Infraestructura | — | `docker compose up -d` en `barriodigital-infra/local` |
| catalog | 8085 | `.\mvnw spring-boot:run "-Dmaven.test.skip=true"` |
| kafka-admin | 8086 | ídem |
| audit | 8087 | ídem |
| requests | 8081 | `.\mvnw clean spring-boot:run "-Dmaven.test.skip=true" "-Dspring-boot.run.arguments=--spring.config.import=optional:file:../.env[.properties]"` |
| bff | 8080 | ídem que requests |
| notifications (opcional, RabbitMQ) | 8082 | `.\mvnw spring-boot:run "-Dmaven.test.skip=true"` |
| front | 4200 | `npm start` (solo para sacar el token) |

## 2. Obtener el token (usuario **Funcionario**)

1. Entra a http://localhost:4200 con un usuario que tenga rol **Funcionario**.
2. `F12` → pestaña **Network** → recarga la página.
3. Clic en una petición a `localhost:8080` (ej. `requests`) → **Headers** → **Request Headers** → `Authorization`.
4. Copia **todo lo que viene después de** `Bearer ` (un texto largo que empieza con `eyJ...`).

> El token dura ~1 hora. Si las peticiones del BFF empiezan a dar **401**, repite este paso.

## 3. Importar y ejecutar

1. Postman → **Import** → arrastra los 3 archivos: la colección y los 2 environments (`BarrioDigital-Local` y `BarrioDigital-AWS`).
2. Arriba a la derecha, en el selector de environment, elige **Local** o **AWS**. Las variables del environment tienen prioridad sobre las de la colección.
3. Clic en el ojo 👁 (o *Environments* en la barra izquierda) → environment elegido → completa *Current value*:
   - `tokenFuncionario`: el token del paso 2, sacado del front **de ese entorno** (local: `localhost:4200`; AWS: `https://44.221.194.97`).
   - `vecinoEmail`: el email de un usuario vecino de tu tenant.
   - **Solo AWS** · `bff`: `<ApiGatewayUrl>/bff/requests` (`ApiGatewayUrl` está en *Salidas* de la pila `barriodigital-v2`).
   - `idRetiro`: id de `RETIRO_CACHUREOS` en catalog (`5` con los datos iniciales).
4. **Guardar** (`Ctrl+S`).
5. Clic derecho en la colección → **Run collection** → **Run**. Ejecuta todo **en orden**.

| Variable | Local | AWS |
|----------|-------|-----|
| `bff` | `http://localhost:8080/api/v1/bff/requests` | `<ApiGatewayUrl>/bff/requests` (pasa por el API Gateway con JWT) |
| `catalog` | `http://localhost:8085/...` | `http://13.218.252.124:8085/...` |
| `kafkaAdmin` | `http://localhost:8086/...` | `http://13.218.252.124:8086/...` |

Debe terminar con todos los tests en verde:

| Carpeta | Qué demuestra |
|---------|---------------|
| 0. Preparación | Cluster Kafka arriba, topics del caso creados, cupo reiniciado |
| 1. Flujo feliz | Crear (201) → admitir (200) → catalog descuenta el cupo → audit sin lag |
| 2. Sin cupo | Con cupo 0, admitir da **409** y el trámite sigue `INGRESADO` |
| 3. Validaciones | 401 sin token · 404 inexistente · 400 regla EN_TERRENO · 404 tipo desconocido en catalog · 400 topic interno protegido |

> El Runner crea 2 trámites nuevos por ejecución. Se puede correr varias veces: la carpeta 0 reinicia el cupo.

## 4. Revisar Kafka por consola

**Eventos publicados por requests** (key = id del trámite):
```powershell
docker exec -it kafka kafka-console-consumer --bootstrap-server kafka:9093 --topic requests.events --from-beginning --property print.key=true --property key.separator=" | "
```

**Historial de audit**: los registros del trámite de la carpeta 1 aparecen **en orden** (INGRESADO → ADMITIDO) con la misma key:
```powershell
docker exec -it kafka kafka-console-consumer --bootstrap-server kafka:9093 --topic audit.timeline --from-beginning --property print.key=true --property key.separator=" | "
```

**DLT**: mandar un mensaje inválido y verlo llegar:
```powershell
'esto no es json' | docker exec -i kafka kafka-console-producer --bootstrap-server kafka:9093 --topic requests.events
docker exec -it kafka kafka-console-consumer --bootstrap-server kafka:9093 --topic audit.DLT --from-beginning
```

`Ctrl+C` para salir de cada consumer.

## 5. Capturas para el informe

- [ ] Postman Runner con todos los tests en verde
- [ ] Respuesta de **1.3** (ADMITIDO) y de **2.3** (409 sin cupo)
- [ ] **1.4**: catalog con el cupo descontado
- [ ] **0.2**: topics del caso (`requests.events`, `audit.timeline`, `audit.DLT`)
- [ ] **1.5**: lag de `auditoria-processor` en 0
- [ ] Consola de `requests.events` con las keys
- [ ] Consola de `audit.timeline`: registros del mismo trámite en orden
- [ ] Consola de `audit.DLT` con el mensaje inválido y sus headers
- [ ] Log de audit con los 3 reintentos (`Record in retry and not yet recovered`) de un evento sin id
- [ ] Panel RabbitMQ (http://localhost:15672) → *Overview* → 2 nodos en verde
