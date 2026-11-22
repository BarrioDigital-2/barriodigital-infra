# Despliegue en AWS (Learner Lab) con CloudFormation

Template: `cloudformation/barriodigital-v2.yaml`. Crea **4 EC2 + Security Groups + IP elástica + API Gateway**.

| EC2 | Tipo | Qué corre | Compose |
|-----|------|-----------|---------|
| web | t3.small | front (HTTPS) + BFF | `web/` |
| apps | t3.medium | requests, catalog, audit, kafka-admin + MySQL | `apps/` |
| mq | t3.medium | RabbitMQ ×2 + notifications + rabbit-admin | `mensajeria/` |
| kafka | t3.medium | Kafka ×3 + Zookeeper ×3 + Kafka UI | `kafka/` |

Cada EC2 ejecuta `bootstrap.sh <rol>`: swap → Docker → clona repos → `.env` → `docker compose up -d --build`.

> Costo aproximado con las 4 encendidas: **~0,15 USD/hora**. Detener las instancias cuando no se usen.

---

## 1. Antes de crear el stack

- [ ] **Código en la rama a desplegar.** El parámetro `Rama` (`main` o `develop`) define qué rama se clona de cada repo y de dónde se descarga `bootstrap.sh`. Para la entrega: fusionar `develop` → `main` en todos los repos (incluido este). Si un repo no tiene la rama, se usa su rama por defecto.
- [ ] **Tu IP pública** (para `MiIpCidr`): buscar "what is my ip" y agregar `/32` (ej. `181.43.211.131/32`).
- [ ] **Bajar el stack o las EC2 anteriores** y **liberar sus IPs elásticas** (EC2 → *IPs elásticas* → *Liberar*): cobran aunque no estén asociadas.
- [ ] **Llave SSH**: en el Learner Lab → *AWS Details* → *Download PEM* (`labsuser.pem`). El par se llama `vockey`.

## 2. Crear el stack

1. Consola AWS → **CloudFormation** → **Crear pila** → *Con recursos nuevos*.
2. **Cargar un archivo de plantilla** → `cloudformation/barriodigital-v2.yaml`.
3. Nombre: `barriodigital-v2`. Parámetros:

| Parámetro | Valor |
|-----------|-------|
| KeyName | `vockey` |
| MiIpCidr | tu IP con `/32` |
| AzureTenantId / AzureClientId | dejar los valores por defecto (los de la app de Azure) |
| DbRootPassword, DbPassword | claves de 8+ caracteres (letras, números, `-`, `_`) |
| RabbitUsername | `barriodigital` |
| RabbitPassword | clave de 8+ caracteres |
| RabbitErlangCookie | texto al azar de 20+ caracteres |
| Rama | `main` (entrega) o `develop` (prueba) |

4. Siguiente → Siguiente → **Enviar**. El stack queda en `CREATE_COMPLETE` en ~3 min, pero las EC2 siguen **instalando y compilando ~15-20 min** más.

## 3. Registrar la redirect URI en Azure

Pestaña **Salidas (Outputs)** del stack → copiar `AzureRedirectUri` (`https://<IP elástica>`).

Azure Portal → **Microsoft Entra ID** → **Registros de aplicaciones** → la app → **Autenticación** → **Aplicación de página única** → **Agregar URI** → pegar → **Guardar**.
Sin borrar `http://localhost:4200`.

## 4. Verificar

**Ver el avance de cada EC2** (SSH con la IP de la consola de EC2):
```bash
ssh -i labsuser.pem ec2-user@<IP>
sudo tail -f /var/log/barriodigital-init.log      # termina con "== EC2 '<rol>' LISTA"
docker ps                                          # contenedores del rol
```

**URLs** (pestaña Outputs):

| Output | Qué es |
|--------|--------|
| `FrontUrl` | El front. Aceptar la advertencia del certificado autofirmado |
| `ApiGatewayUrl` | API Gateway (`.../api/v1`) |
| `KafkaUiUrl` | Kafka UI: 3 brokers y los topics |
| `RabbitPanelUrl` | Panel de RabbitMQ: 2 nodos |
| `CatalogUrl`, `KafkaAdminUrl` | Para Postman |

> Las IP públicas de apps, mq y kafka **cambian si el lab se reinicia** (la de web es elástica y no cambia). Si un Output no responde, revisa la IP actual en la consola de EC2.

## 5. Probar con Postman

En la colección `postman/`, cambiar las variables (*Current value*):

| Variable | Valor en AWS |
|----------|--------------|
| `bff` | `<ApiGatewayUrl>/bff/requests` |
| `catalog` | `http://<IP apps>:8085/api/v1/catalog/procedures` |
| `kafkaAdmin` | `http://<IP apps>:8086/api/v1/kafka-admin` |
| `tokenFuncionario` | token sacado del front **de AWS** (`FrontUrl`), igual que en local |

Run collection → todo en verde. En **0.2** deberían aparecer los topics con **3 réplicas**.

## 6. Problemas comunes

| Problema | Revisar |
|----------|---------|
| Login de Azure: `AADSTS50011` | Falta registrar `AzureRedirectUri` (paso 3) |
| El front carga pero no muestra trámites | `docker logs ms-bff` en web; ¿apps terminó de levantar? |
| requests no publica en Kafka | En apps: `docker logs ms-requests`; en kafka: `docker ps` (3 brokers arriba) |
| Una EC2 nunca dice "LISTA" | `sudo cat /var/log/barriodigital-init.log` para ver en qué paso falló |
| `OOMKilled` en `docker ps -a` | Falta memoria: subir el `mem_limit` del servicio o bajar `MaxRAMPercentage` |

## 7. Reabrir el lab (otro día u otro PC)

Al terminar la sesión, el Learner Lab **detiene** las EC2; al abrirlo de nuevo las **enciende**. Todo vuelve solo:
contenedores (`restart: unless-stopped`), datos (volúmenes), front/Azure/API Gateway (IP elástica) y la comunicación entre EC2 (IPs privadas).

**Checklist (~5 min):**
1. **Start Lab** → esperar las 4 EC2 "En ejecución" y **3-5 min más** para los contenedores.
2. Abrir `FrontUrl` e iniciar sesión → si funciona, la app está bien.
3. **Desde otro PC/red**: CloudFormation → pila → **Actualizar** → *Usar la plantilla actual* → `MiIpCidr` = IP de ese PC + `/32` → Enviar (~2 min). Sin esto no hay SSH ni paneles (el front y la API sí funcionan).
4. IPs públicas **nuevas** de apps, mq y kafka: consola de EC2 (para paneles y Postman).
5. SSH: volver a descargar `labsuser.pem` (*AWS Details*).

> Ensayo recomendado tras el primer despliegue: **End Lab → Start Lab** y repetir este checklist.

## 8. Al terminar

- **Detener** las 4 EC2 (consola EC2 → *Estado de la instancia* → *Detener*) cuando no se usen.
- Al cerrar el ramo: **Eliminar la pila** en CloudFormation (borra todo, incluida la IP elástica).
