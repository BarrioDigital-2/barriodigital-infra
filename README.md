# barriodigital-infra

Infraestructura de **BarrioDigital** con Docker Compose: RabbitMQ, Kafka y MySQL.
No tiene código de aplicación: solo los archivos para levantar lo que necesitan los microservicios.

```
barriodigital-infra/
├── local/
│   └── docker-compose.yml          ← desarrollo en tu PC (todo en uno)
├── aws/
│   └── mensajeria/                 ← EC2 de mensajería (RabbitMQ + notifications + rabbit-admin)
│       ├── docker-compose.yml
│       └── .env.example
└── docker/rabbitmq/
    └── cluster-entrypoint.sh       ← arma el cluster de 2 nodos (lo usan local y aws)
```

---

## Desarrollo local

### Requisitos
- **Docker Desktop** encendido (`docker ps` debe responder sin error).
- Puertos libres: 5672, 5673, 15672, 15673, 2181, 9092, 9093, 3307.

### Levantar

```powershell
git clone https://github.com/BarrioDigital-2/barriodigital-infra.git
cd barriodigital-infra/local
docker compose up -d
docker compose ps
```

Deben quedar **5 contenedores** arriba: `rabbit1`, `rabbit2`, `zookeeper`, `kafka`, `barriodigital-mysql`.
RabbitMQ y MySQL tardan unos 30 segundos en pasar a `healthy`.

### Qué queda disponible

| Servicio | Desde tu PC | Desde un contenedor | Credenciales |
|----------|-------------|---------------------|--------------|
| RabbitMQ (AMQP) | `localhost:5672` | `rabbit1:5672` | `barriodigital` / `barrio2026Rabbit` |
| RabbitMQ (panel) | http://localhost:15672 | — | ídem |
| Kafka | `localhost:9092` | `kafka:9093` | — |
| MySQL | `localhost:3307` | `mysql:3306` | `root` / `root` |

> MySQL va en el **3307** porque el 3306 suele estar ocupado por un MySQL instalado en Windows.
> Cada microservicio crea su propia base al arrancar (`createDatabaseIfNotExist=true`).

### Después: levantar los microservicios

Cada microservicio se corre desde su carpeta con:

```powershell
.\mvnw spring-boot:run "-Dmaven.test.skip=true"
```

| Microservicio | Puerto | Usa |
|---------------|--------|-----|
| ms-barriodigital-requests | 8081 | MySQL, RabbitMQ, Kafka |
| ms-barriodigital-notifications | 8082 | RabbitMQ |
| ms-barriodigital-rabbit-admin | 8083 | RabbitMQ |
| ms-barriodigital-audit | 8087 | Kafka |
| ms-barriodigital-report | 8084 | MySQL, Kafka |
| ms-barriodigital-catalog | 8085 | MySQL |
| ms-barriodigital-kafka-admin | 8086 | Kafka |
| barrioDigital-front-angular | 4200 | (llama al BFF) |

> ms-requests usa por defecto el MySQL en 3306: para este entorno, levántalo con `$env:DB_PORT="3307"` antes del `mvnw`.

### Comandos útiles

```powershell
docker compose ps                  # estado de los contenedores
docker compose logs -f kafka       # ver logs de un servicio (Ctrl+C para salir)
docker compose stop                # detener sin borrar datos
docker compose up -d               # volver a levantar (los datos siguen ahí)
docker compose down -v             # ⚠️ borrar TODO, incluidos los datos, y empezar de cero
```

Kafka:
```powershell
docker exec kafka kafka-topics --bootstrap-server kafka:9093 --list
docker exec kafka kafka-consumer-groups --bootstrap-server kafka:9093 --list
```

RabbitMQ:
```powershell
docker exec rabbit1 rabbitmqctl cluster_status     # deben aparecer rabbit@rabbit1 y rabbit@rabbit2
```

MySQL:
```powershell
docker exec -it barriodigital-mysql mysql -uroot -proot -e "SHOW DATABASES;"
```

### Problemas comunes

| Problema | Solución |
|----------|----------|
| `kafka` aparece como `Exited` (log con `NodeExistsException`) | Pasa tras apagar el PC sin detener Docker. Se reintenta solo (`restart: on-failure`); si no, `docker start kafka` |
| `InconsistentClusterIdException` en Kafka | `docker compose down`, `docker volume rm barriodigital-rabbitmq_kafka_data` y `docker compose up -d` (se pierden los topics) |
| Un nodo RabbitMQ queda en `health: starting` | Se levantó solo uno; `docker compose up -d` levanta los dos (en RabbitMQ 4.x cada nodo espera al otro) |
| `rabbit2` no se une al cluster | `docker compose down -v` y `docker compose up -d` (borra los datos) |
| `port is already allocated` | Otro programa usa ese puerto: ciérralo o cambia el puerto de la izquierda en `ports:` |
| Microservicio: `Communications link failure` | MySQL no está arriba o no apuntas al 3307 |

---

## AWS: EC2 de mensajería

Cluster RabbitMQ + ms-notifications + ms-rabbit-admin. Clonar los repos uno al lado del otro:

```bash
mkdir -p ~/barriodigital && cd ~/barriodigital
git clone https://github.com/BarrioDigital-2/barriodigital-infra.git
git clone https://github.com/BarrioDigital-2/ms-BarrioDigital-Notifications.git ms-barriodigital-notifications
git clone https://github.com/BarrioDigital-2/ms-barriodigital-rabbit-admin.git

cd barriodigital-infra/aws/mensajeria
cp .env.example .env        # completar usuario, clave y cookie
docker compose up -d --build
docker compose ps           # rabbit1, rabbit2, ms-notifications, ms-rabbit-admin
```

> La EC2 de datos (MySQL + ms-requests) sigue con el compose del repo `ms-barriodigital-requests`.
> La EC2 de Kafka y la de apps se agregan en `aws/` como parte del despliegue (Tarea 7).

---

## Reglas del repo

- Ramas: `feature/xxx` → Pull Request a `develop` → `main` solo al entregar.
- **Nunca** subir un `.env` con credenciales reales (está en `.gitignore`); usar `.env.example` como plantilla.
- Los scripts `.sh` deben quedar con fin de línea **LF** (lo fuerza `.gitattributes`); con CRLF fallan dentro del contenedor.
